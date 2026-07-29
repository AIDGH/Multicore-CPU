`timescale 1ns/1ps

module l1_cache_mesi #(
    parameter INDEX_BITS = 4,
    parameter LINE_COUNT = (1 << INDEX_BITS)
) (
    input  logic        clk,
    input  logic        rst_n,

    // ==========================================
    // Core to Cache Interface (interfaces.md)
    // ==========================================
    input  logic        data_req_valid,
    output logic        data_req_ready,
    input  logic [31:0] data_req_addr,
    input  logic        data_req_write,
    input  logic [31:0] data_req_wdata,
    
    output logic        data_rsp_valid,
    output logic [31:0] data_rsp_rdata,
    output logic        data_rsp_error,

    // Signal to Shahab's reservation unit
    output logic        cancel_reservation,

    // ==========================================
    // Cache to Bus Interface (Master Role)
    // ==========================================
    output logic        bus_req,
    output logic        bus_req_rdx,     // 0: BusRd, 1: BusRdX
    output logic [31:0] bus_req_addr,
    input  logic        bus_gnt,
    input  logic        bus_rsp_valid,
    input  logic [127:0] bus_rsp_rdata,

    // ==========================================
    // Snoop Interface (Snooping Role)
    // ==========================================
    input  logic        snoop_valid,
    input  logic [31:0] snoop_addr,
    input  logic        snoop_rdx,       // 0: BusRd, 1: BusRdX
    output logic        snoop_shared,
    output logic        snoop_flush,
    output logic [127:0] snoop_wdata
);

    localparam TAG_BITS = 32 - INDEX_BITS - 4;

    // MESI State Encoding
    typedef enum logic [1:0] {
        STATE_I = 2'b00, // Invalid
        STATE_S = 2'b01, // Shared
        STATE_E = 2'b10, // Exclusive
        STATE_M = 2'b11  // Modified
    } mesi_state_t;

    // Cache Datapath Arrays
    mesi_state_t        state_array [0:LINE_COUNT-1];
    logic [TAG_BITS-1:0] tag_array   [0:LINE_COUNT-1];
    logic [127:0]        data_array  [0:LINE_COUNT-1];

    // FSM States for Core Requests
    typedef enum logic [2:0] {
        C_IDLE,
        C_LOOKUP,
        C_WRITEBACK,
        C_BUS_REQ,
        C_BUS_WAIT,
        C_RESPONSE
    } cache_fsm_t;

    cache_fsm_t fsm_state, next_fsm_state;

    // Latched Core Request Registers
    logic [31:0] req_addr_reg;
    logic        req_write_reg;
    logic [31:0] req_wdata_reg;

    // Performance Counters
    logic [31:0] cnt_hits;
    logic [31:0] cnt_misses;
    logic [31:0] cnt_flushes;
    logic [31:0] cnt_invalidations;
    logic [31:0] cnt_state_transitions;

    // Address Decoding Helpers
    wire [INDEX_BITS-1:0] req_index = req_addr_reg[INDEX_BITS+3:4];
    wire [TAG_BITS-1:0]   req_tag   = req_addr_reg[31:INDEX_BITS+4];
    wire [1:0]            req_word  = req_addr_reg[3:2];

    wire [INDEX_BITS-1:0] curr_index = data_req_addr[INDEX_BITS+3:4];
    wire [TAG_BITS-1:0]   curr_tag   = data_req_addr[31:INDEX_BITS+4];

    // Hit Logic
    wire line_valid = (state_array[req_index] != STATE_I);
    wire tag_match  = (tag_array[req_index] == req_tag);
    wire is_hit     = line_valid && tag_match;

    // Helper to replace word in 128-bit line
    function automatic logic [127:0] replace_word(
        input logic [127:0] old_line,
        input logic [1:0]   word_idx,
        input logic [31:0]  new_word
    );
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

    // Helper to extract word from 128-bit line
    function automatic logic [31:0] get_word(
        input logic [127:0] line,
        input logic [1:0]   word_idx
    );
        case (word_idx)
            2'b00: return line[31:0];
            2'b01: return line[63:32];
            2'b10: return line[95:64];
            2'b11: return line[127:96];
        endcase
    endfunction

    // ==========================================
    // 1. Snooping Logic (Combinational & Async)
    // ==========================================
    wire [INDEX_BITS-1:0] snoop_index = snoop_addr[INDEX_BITS+3:4];
    wire [TAG_BITS-1:0]   snoop_tag   = snoop_addr[31:INDEX_BITS+4];

    wire snoop_hit = snoop_valid && 
                     (state_array[snoop_index] != STATE_I) && 
                     (tag_array[snoop_index] == snoop_tag);

    assign snoop_shared = snoop_hit;
    assign snoop_flush  = snoop_hit && (state_array[snoop_index] == STATE_M);
    assign snoop_wdata  = data_array[snoop_index];

    // Remote Write Invalidation Signal for Shahab's Reservation Station
    assign cancel_reservation = snoop_hit && snoop_rdx;

// Snoop State Updates (Synchronous)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_flushes       <= 32'b0;
            cnt_invalidations <= 32'b0;
        end else if (snoop_hit) begin
            if (snoop_rdx) begin
                // Invalidation on remote write
                if (state_array[snoop_index] == STATE_M) begin
                    cnt_flushes <= cnt_flushes + 1;
                end
                state_array[snoop_index] <= STATE_I;
                cnt_invalidations        <= cnt_invalidations + 1;
            end else begin
                // Remote read transition to Shared
                if (state_array[snoop_index] == STATE_M) begin
                    cnt_flushes <= cnt_flushes + 1;
                end
                state_array[snoop_index] <= STATE_S;
            end
        end
    end

    // ==========================================
    // 2. Core Request FSM & Bus Master Logic
    // ==========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state             <= C_IDLE;
            data_req_ready        <= 1'b1;
            data_rsp_valid        <= 1'b0;
            data_rsp_error        <= 1'b0;
            bus_req               <= 1'b0;
            cnt_hits              <= 32'b0;
            cnt_misses            <= 32'b0;
            cnt_state_transitions <= 32'b0;

            for (int i = 0; i < LINE_COUNT; i++) begin
                state_array[i] <= STATE_I;
                tag_array[i]   <= '0;
                data_array[i]  <= '0;
            end
        end else begin
            case (fsm_state)
                C_IDLE: begin
                    data_rsp_valid <= 1'b0;
                    data_req_ready <= 1'b1;

                    if (data_req_valid) begin
                        req_addr_reg   <= data_req_addr;
                        req_write_reg  <= data_req_write;
                        req_wdata_reg  <= data_req_wdata;
                        data_req_ready <= 1'b0;
                        fsm_state      <= C_LOOKUP;
                    end
                end

                C_LOOKUP: begin
                    if (is_hit) begin
                        if (!req_write_reg) begin
                            // Read Hit
                            data_rsp_rdata <= get_word(data_array[req_index], req_word);
                            data_rsp_valid <= 1'b1;
                            cnt_hits       <= cnt_hits + 1;
                            fsm_state      <= C_RESPONSE;
                        end else begin
                            // Write Hit
                            if (state_array[req_index] == STATE_M || state_array[req_index] == STATE_E) begin
                                data_array[req_index]  <= replace_word(data_array[req_index], req_word, req_wdata_reg);
                                state_array[req_index] <= STATE_M;
                                data_rsp_valid         <= 1'b1;
                                cnt_hits               <= cnt_hits + 1;
                                cnt_state_transitions  <= cnt_state_transitions + 1;
                                fsm_state              <= C_RESPONSE;
                            end else begin
                                // Shared Hit -> Need BusRdX to upgrade
                                bus_req      <= 1'b1;
                                bus_req_rdx  <= 1'b1;
                                bus_req_addr <= req_addr_reg;
                                fsm_state    <= C_BUS_REQ;
                            end
                        end
                    end else begin
                        // Miss Logic
                        cnt_misses <= cnt_misses + 1;
                        if (line_valid && state_array[req_index] == STATE_M) begin
                            // Dirty line replacement -> Writeback first
                            bus_req      <= 1'b1;
                            bus_req_rdx  <= 1'b1;
                            bus_req_addr <= {tag_array[req_index], req_index, 4'b0000};
                            fsm_state    <= C_WRITEBACK;
                        end else begin
                            // Clean Miss -> Fetch from Bus
                            bus_req      <= 1'b1;
                            bus_req_rdx  <= req_write_reg;
                            bus_req_addr <= req_addr_reg;
                            fsm_state    <= C_BUS_REQ;
                        end
                    end
                end

                C_WRITEBACK: begin
                    if (bus_gnt) begin
                        // Complete Writeback then request new line
                        bus_req_rdx  <= req_write_reg;
                        bus_req_addr <= req_addr_reg;
                        fsm_state    <= C_BUS_REQ;
                    end
                end

                C_BUS_REQ: begin
                    if (bus_gnt) begin
                        fsm_state <= C_BUS_WAIT;
                    end
                end

                C_BUS_WAIT: begin
                    if (bus_rsp_valid) begin
                        bus_req <= 1'b0;
                        tag_array[req_index] <= req_tag;

                        if (!req_write_reg) begin
                            // Read Miss Fill
                            data_array[req_index]  <= bus_rsp_rdata;
                        
                            if (snoop_shared)
                                state_array[req_index] <= STATE_S;
                            else
                                state_array[req_index] <= STATE_E;
                                
                            data_rsp_rdata         <= get_word(bus_rsp_rdata, req_word);
                        end else begin
                            // Write Miss Fill
                            data_array[req_index]  <= replace_word(bus_rsp_rdata, req_word, req_wdata_reg);
                            state_array[req_index] <= STATE_M;
                        end

                        cnt_state_transitions <= cnt_state_transitions + 1;
                        data_rsp_valid        <= 1'b1;
                        fsm_state             <= C_RESPONSE;
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