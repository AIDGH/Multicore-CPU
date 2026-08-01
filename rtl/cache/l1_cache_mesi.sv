`timescale 1ns/1ps

module l1_cache_mesi #(
    parameter INDEX_BITS = 4,
    parameter LINE_COUNT = (1 << INDEX_BITS)
) (
    input  logic        clk,
    input  logic        rst_n,

    // ==========================================
    // Core to Cache Interface (Updated for Atomics)
    // ==========================================
    input  logic        data_req_valid,
    output logic        data_req_ready,
    input  logic [31:0] data_req_addr,
    input  logic [2:0]  data_req_op,     // 0:LD, 1:ST, 2:LR, 3:SC, 4:AMOADD
    input  logic [31:0] data_req_wdata,
    
    output logic        data_rsp_valid,
    output logic [31:0] data_rsp_rdata,
    output logic        data_rsp_error,

    output logic        cancel_reservation,

    // ==========================================
    // Cache to Bus Interface 
    // ==========================================
    output logic        bus_req,
    output logic        bus_req_rdx,
    output logic [31:0] bus_req_addr,
    input  logic        bus_gnt,
    input  logic        bus_rsp_valid,
    input  logic [127:0] bus_rsp_rdata,

    // ==========================================
    // Snoop Interface 
    // ==========================================
    input  logic        snoop_valid,
    input  logic [31:0] snoop_addr,
    input  logic        snoop_rdx,
    output logic        snoop_shared,
    output logic        snoop_flush,
    output logic [127:0] snoop_wdata
);

    localparam TAG_BITS = 32 - INDEX_BITS - 4;

    // Core Memory Operations
    localparam [2:0]
        OP_LOAD   = 3'd0,
        OP_STORE  = 3'd1,
        OP_LR     = 3'd2,
        OP_SC     = 3'd3,
        OP_AMOADD = 3'd4;

    // MESI State Encoding
    typedef enum logic [1:0] {
        STATE_I = 2'b00,
        STATE_S = 2'b01,
        STATE_E = 2'b10,
        STATE_M = 2'b11
    } mesi_state_t;

    // Cache Datapath
    mesi_state_t         state_array [0:LINE_COUNT-1];
    logic [TAG_BITS-1:0] tag_array   [0:LINE_COUNT-1];
    logic [127:0]        data_array  [0:LINE_COUNT-1];

    typedef enum logic [2:0] {
        C_IDLE, C_LOOKUP, C_WRITEBACK, C_BUS_REQ, C_BUS_WAIT, C_RESPONSE
    } cache_fsm_t;

    cache_fsm_t fsm_state;

    // Latched Core Requests
    logic [31:0] req_addr_reg;
    logic [2:0]  req_op_reg;
    logic [31:0] req_wdata_reg;

    // Operation Decoding
    wire is_read  = (req_op_reg == OP_LOAD)  || (req_op_reg == OP_LR);
    wire is_write = (req_op_reg == OP_STORE) || (req_op_reg == OP_SC);
    wire is_amo   = (req_op_reg == OP_AMOADD);
    wire needs_exclusive = is_write || is_amo;

    // Performance Counters
    logic [31:0] cnt_hits, cnt_misses, cnt_flushes, cnt_invalidations, cnt_state_transitions;

    wire [INDEX_BITS-1:0] req_index = req_addr_reg[INDEX_BITS+3:4];
    wire [TAG_BITS-1:0]   req_tag   = req_addr_reg[31:INDEX_BITS+4];
    wire [1:0]            req_word  = req_addr_reg[3:2];

    wire line_valid = (state_array[req_index] != STATE_I);
    wire tag_match  = (tag_array[req_index] == req_tag);
    wire is_hit     = line_valid && tag_match;

    // Word Replacement Helper
    function automatic logic [127:0] replace_word(input logic [127:0] old_line, input logic [1:0] word_idx, input logic [31:0] new_word);
        logic [127:0] line;
        line = old_line;
        case (word_idx)
            2'b00: line[31:0]   = new_word;
            2'b01: line[63:32]  = new_word;
            2'b10: line[95:64]  = new_word;
            2'b11: line[127:96] = new_word;
        endcase
        return line;
    endfunction

    // Word Extraction Helper
    function automatic logic [31:0] get_word(input logic [127:0] line, input logic [1:0] word_idx);
        case (word_idx)
            2'b00: return line[31:0];
            2'b01: return line[63:32];
            2'b10: return line[95:64];
            2'b11: return line[127:96];
        endcase
    endfunction

    // ==========================================
    // 1. Snooping Logic 
    // ==========================================
    wire [INDEX_BITS-1:0] snoop_index = snoop_addr[INDEX_BITS+3:4];
    wire [TAG_BITS-1:0]   snoop_tag   = snoop_addr[31:INDEX_BITS+4];

    wire snoop_hit = snoop_valid && (state_array[snoop_index] != STATE_I) && (tag_array[snoop_index] == snoop_tag);

    assign snoop_shared = snoop_hit;
    assign snoop_flush  = snoop_hit && (state_array[snoop_index] == STATE_M);
    assign snoop_wdata  = data_array[snoop_index];

    // Cancel reservation on remote write targeting our line
    assign cancel_reservation = snoop_hit && snoop_rdx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_flushes <= '0; cnt_invalidations <= '0;
        end else if (snoop_hit) begin
            if (snoop_rdx) begin
                if (state_array[snoop_index] == STATE_M) cnt_flushes <= cnt_flushes + 1;
                state_array[snoop_index] <= STATE_I;
                cnt_invalidations <= cnt_invalidations + 1;
            end else begin
                if (state_array[snoop_index] == STATE_M) cnt_flushes <= cnt_flushes + 1;
                state_array[snoop_index] <= STATE_S;
            end
        end
    end

    // ==========================================
    // 2. Core Request FSM 
    // ==========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state <= C_IDLE;
            data_req_ready <= 1'b1; data_rsp_valid <= 1'b0; data_rsp_error <= 1'b0;
            bus_req <= 1'b0;
            cnt_hits <= '0; cnt_misses <= '0; cnt_state_transitions <= '0;
            for (int i = 0; i < LINE_COUNT; i++) begin
                state_array[i] <= STATE_I; tag_array[i] <= '0; data_array[i] <= '0;
            end
        end else begin
            case (fsm_state)
                C_IDLE: begin
                    data_rsp_valid <= 1'b0;
                    data_req_ready <= 1'b1;
                    if (data_req_valid) begin
                        req_addr_reg   <= data_req_addr;
                        req_op_reg     <= data_req_op;
                        req_wdata_reg  <= data_req_wdata;
                        data_req_ready <= 1'b0;
                        fsm_state      <= C_LOOKUP;
                    end
                end

                C_LOOKUP: begin
                    if (is_hit) begin
                        if (is_read) begin
                            // Normal Read or Load-Reserved
                            data_rsp_rdata <= get_word(data_array[req_index], req_word);
                            data_rsp_valid <= 1'b1;
                            cnt_hits       <= cnt_hits + 1;
                            fsm_state      <= C_RESPONSE;
                        end else begin
                            // Write, SC, or AMOADD
                            if (state_array[req_index] == STATE_M || state_array[req_index] == STATE_E) begin
                                if (is_amo) begin
                                    // Atomic Read-Modify-Write
                                    data_rsp_rdata <= get_word(data_array[req_index], req_word);
                                    data_array[req_index] <= replace_word(data_array[req_index], req_word, get_word(data_array[req_index], req_word) + req_wdata_reg);
                                end else begin
                                    // Normal Write or SC
                                    data_array[req_index] <= replace_word(data_array[req_index], req_word, req_wdata_reg);
                                end
                                state_array[req_index] <= STATE_M;
                                data_rsp_valid         <= 1'b1;
                                cnt_hits               <= cnt_hits + 1;
                                cnt_state_transitions  <= cnt_state_transitions + 1;
                                fsm_state              <= C_RESPONSE;
                            end else begin
                                // Shared Hit -> Need BusRdX for exclusive ownership
                                bus_req      <= 1'b1;
                                bus_req_rdx  <= 1'b1;
                                bus_req_addr <= req_addr_reg;
                                fsm_state    <= C_BUS_REQ;
                            end
                        end
                    end else begin
                        // Miss Handling
                        cnt_misses <= cnt_misses + 1;
                        if (line_valid && state_array[req_index] == STATE_M) begin
                            bus_req      <= 1'b1;
                            bus_req_rdx  <= 1'b1;
                            bus_req_addr <= {tag_array[req_index], req_index, 4'b0000};
                            fsm_state    <= C_WRITEBACK;
                        end else begin
                            bus_req      <= 1'b1;
                            bus_req_rdx  <= needs_exclusive;
                            bus_req_addr <= req_addr_reg;
                            fsm_state    <= C_BUS_REQ;
                        end
                    end
                end

                C_WRITEBACK: begin
                    if (bus_gnt) begin
                        bus_req_rdx  <= needs_exclusive;
                        bus_req_addr <= req_addr_reg;
                        fsm_state    <= C_BUS_REQ;
                    end
                end

                C_BUS_REQ: begin
                    if (bus_gnt) fsm_state <= C_BUS_WAIT;
                end

                C_BUS_WAIT: begin
                    if (bus_rsp_valid) begin
                        bus_req <= 1'b0;
                        tag_array[req_index] <= req_tag;

                        if (is_read) begin
                            data_array[req_index]  <= bus_rsp_rdata;
                            if (snoop_shared) state_array[req_index] <= STATE_S;
                            else              state_array[req_index] <= STATE_E;
                            data_rsp_rdata <= get_word(bus_rsp_rdata, req_word);
                            
                        end else if (is_amo) begin
                            data_rsp_rdata <= get_word(bus_rsp_rdata, req_word);
                            data_array[req_index] <= replace_word(bus_rsp_rdata, req_word, get_word(bus_rsp_rdata, req_word) + req_wdata_reg);
                            state_array[req_index] <= STATE_M;
                                                    
                        end else begin
                            data_array[req_index] <= replace_word(bus_rsp_rdata, req_word, req_wdata_reg);
                            state_array[req_index] <= STATE_M;
                        end

                        cnt_state_transitions <= cnt_state_transitions + 1;
                        data_rsp_valid <= 1'b1;
                        fsm_state      <= C_RESPONSE;
                    end
                end

                C_RESPONSE: begin
                    data_rsp_valid <= 1'b0;
                    data_req_ready <= 1'b1;
                    fsm_state      <= C_IDLE;
                end

                default: fsm_state <= C_IDLE;
            endcase
        end
    end
endmodule