import mc_defs_pkg::*;

module shared_bus (
    input  logic                         clk,
    input  logic                         rst,

    input  logic [1:0]                   l1_req_valid,
    output logic [1:0]                   l1_req_ready,
    input  mc_bus_txn_t                  l1_req_txn_0,
    input  mc_bus_txn_t                  l1_req_txn_1,
    input  logic [MC_ADDR_WIDTH-1:0]     l1_req_line_addr_0,
    input  logic [MC_ADDR_WIDTH-1:0]     l1_req_line_addr_1,
    input  logic [MC_LINE_WIDTH-1:0]     l1_req_wdata_0,
    input  logic [MC_LINE_WIDTH-1:0]     l1_req_wdata_1,

    output logic [1:0]                   l1_rsp_valid,
    output logic [MC_LINE_WIDTH-1:0]     l1_rsp_data_0,
    output logic [MC_LINE_WIDTH-1:0]     l1_rsp_data_1,
    output logic [1:0]                   l1_rsp_shared,
    output logic [1:0]                   l1_rsp_error,

    output logic [1:0]                   snoop_valid,
    output mc_bus_txn_t                  snoop_txn,
    output logic [MC_ADDR_WIDTH-1:0]     snoop_line_addr,
    output logic                         snoop_requester_id,
    input  logic [1:0]                   snoop_rsp_valid,
    input  logic [1:0]                   snoop_rsp_present,
    input  logic [1:0]                   snoop_rsp_dirty,
    input  logic [1:0]                   snoop_rsp_data_valid,
    input  logic [MC_LINE_WIDTH-1:0]     snoop_rsp_data_0,
    input  logic [MC_LINE_WIDTH-1:0]     snoop_rsp_data_1,

    output logic                         memory_req_valid,
    input  logic                         memory_req_ready,
    output mc_line_mem_op_t              memory_req_op,
    output logic [MC_ADDR_WIDTH-1:0]     memory_req_line_addr,
    output logic [MC_LINE_WIDTH-1:0]     memory_req_wdata,
    input  logic                         memory_rsp_valid,
    input  logic [MC_LINE_WIDTH-1:0]     memory_rsp_rdata,
    input  logic                         memory_rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [2:0]
        BUS_IDLE          = 3'd0,
        BUS_SNOOP         = 3'd1,
        BUS_MEMORY_REQ    = 3'd2,
        BUS_MEMORY_WAIT   = 3'd3,
        BUS_RESPOND       = 3'd4;

    logic [2:0]                   state;
    logic                         owner_id;
    mc_bus_txn_t                  active_txn;
    logic [MC_ADDR_WIDTH-1:0]     active_line_addr;
    logic [MC_LINE_WIDTH-1:0]     active_wdata;
    logic [MC_LINE_WIDTH-1:0]     final_rsp_data;
    logic                         final_rsp_shared;
    logic                         final_rsp_error;

    logic [1:0] arb_grant;
    logic       arb_txn_done;

    wire peer_rsp_valid =
        owner_id ? snoop_rsp_valid[0] : snoop_rsp_valid[1];
    wire peer_rsp_present =
        owner_id ? snoop_rsp_present[0] : snoop_rsp_present[1];
    wire peer_rsp_dirty =
        owner_id ? snoop_rsp_dirty[0] : snoop_rsp_dirty[1];

    rr_arbiter arbiter (
        .clk(clk),
        .rst(rst),
        .req(l1_req_valid),
        .txn_done(arb_txn_done),
        .grant(arb_grant)
    );

    always @* begin
        l1_req_ready      = 2'b00;
        l1_rsp_valid      = 2'b00;
        l1_rsp_data_0     = {MC_LINE_WIDTH{1'b0}};
        l1_rsp_data_1     = {MC_LINE_WIDTH{1'b0}};
        l1_rsp_shared     = 2'b00;
        l1_rsp_error      = 2'b00;

        snoop_valid        = 2'b00;
        snoop_txn          = active_txn;
        snoop_line_addr    = active_line_addr;
        snoop_requester_id = owner_id;

        memory_req_valid     = 1'b0;
        memory_req_op        = mc_line_mem_op_t'(
            (active_txn == MC_BUS_WRITEBACK)
            ? MC_LINE_WRITE : MC_LINE_READ
        );
        memory_req_line_addr = active_line_addr;
        memory_req_wdata     = active_wdata;

        arb_txn_done = (state == BUS_RESPOND);

        if (state == BUS_IDLE)
            l1_req_ready = arb_grant;

        if (state == BUS_SNOOP) begin
            if (owner_id)
                snoop_valid = 2'b01;
            else
                snoop_valid = 2'b10;
        end

        if (state == BUS_MEMORY_REQ)
            memory_req_valid = 1'b1;

        if (state == BUS_RESPOND) begin
            if (owner_id) begin
                l1_rsp_valid[1]  = 1'b1;
                l1_rsp_data_1    = final_rsp_data;
                l1_rsp_shared[1] = final_rsp_shared;
                l1_rsp_error[1]  = final_rsp_error;
            end else begin
                l1_rsp_valid[0]  = 1'b1;
                l1_rsp_data_0    = final_rsp_data;
                l1_rsp_shared[0] = final_rsp_shared;
                l1_rsp_error[0]  = final_rsp_error;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= BUS_IDLE;
            owner_id         <= 1'b0;
            active_txn       <= MC_BUS_RD;
            active_line_addr <= {MC_ADDR_WIDTH{1'b0}};
            active_wdata     <= {MC_LINE_WIDTH{1'b0}};
            final_rsp_data   <= {MC_LINE_WIDTH{1'b0}};
            final_rsp_shared <= 1'b0;
            final_rsp_error  <= 1'b0;
        end else begin
            case (state)
                BUS_IDLE: begin
                    if (arb_grant[0]) begin
                        owner_id         <= 1'b0;
                        active_txn       <= l1_req_txn_0;
                        active_line_addr <= {
                            l1_req_line_addr_0[
                                MC_ADDR_WIDTH-1:MC_LINE_OFFSET_BITS
                            ],
                            {MC_LINE_OFFSET_BITS{1'b0}}
                        };
                        active_wdata     <= l1_req_wdata_0;
                        final_rsp_data   <= {MC_LINE_WIDTH{1'b0}};
                        final_rsp_shared <= 1'b0;
                        final_rsp_error  <= 1'b0;
                        state            <= BUS_SNOOP;
                    end else if (arb_grant[1]) begin
                        owner_id         <= 1'b1;
                        active_txn       <= l1_req_txn_1;
                        active_line_addr <= {
                            l1_req_line_addr_1[
                                MC_ADDR_WIDTH-1:MC_LINE_OFFSET_BITS
                            ],
                            {MC_LINE_OFFSET_BITS{1'b0}}
                        };
                        active_wdata     <= l1_req_wdata_1;
                        final_rsp_data   <= {MC_LINE_WIDTH{1'b0}};
                        final_rsp_shared <= 1'b0;
                        final_rsp_error  <= 1'b0;
                        state            <= BUS_SNOOP;
                    end
                end

                BUS_SNOOP: begin
                    if (peer_rsp_valid) begin
                        final_rsp_shared <= peer_rsp_present;

                        if (peer_rsp_dirty) begin
                            final_rsp_data  <= {MC_LINE_WIDTH{1'b0}};
                            final_rsp_error <= 1'b1;
                            state           <= BUS_RESPOND;
                        end else begin
                            state <= BUS_MEMORY_REQ;
                        end
                    end
                end

                BUS_MEMORY_REQ: begin
                    if (memory_req_ready)
                        state <= BUS_MEMORY_WAIT;
                end

                BUS_MEMORY_WAIT: begin
                    if (memory_rsp_valid) begin
                        final_rsp_data  <= memory_rsp_rdata;
                        final_rsp_error <= memory_rsp_error;
                        state           <= BUS_RESPOND;
                    end
                end

                BUS_RESPOND: state <= BUS_IDLE;

                default: state <= BUS_IDLE;
            endcase
        end
    end

    wire _unused_snoop_data = &{
        1'b0,
        snoop_rsp_data_valid,
        snoop_rsp_data_0[0],
        snoop_rsp_data_1[0]
    };
endmodule
