import mc_defs_pkg::*;

module shared_memory #(
    parameter integer LINE_COUNT       = 256,
    parameter integer RESPONSE_LATENCY = 2
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         memory_req_valid,
    output logic                         memory_req_ready,
    input  mc_line_mem_op_t              memory_req_op,
    input  logic [MC_ADDR_WIDTH-1:0]     memory_req_line_addr,
    input  logic [MC_LINE_WIDTH-1:0]     memory_req_wdata,
    output logic                         memory_rsp_valid,
    output logic [MC_LINE_WIDTH-1:0]     memory_rsp_rdata,
    output logic                         memory_rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer INDEX_WIDTH =
        (LINE_COUNT <= 1) ? 1 : $clog2(LINE_COUNT);
    localparam integer LATENCY_CYCLES =
        (RESPONSE_LATENCY < 1) ? 1 : RESPONSE_LATENCY;
    localparam integer LATENCY_WIDTH =
        (LATENCY_CYCLES <= 1) ? 1 : $clog2(LATENCY_CYCLES + 1);
    localparam logic [31:0] LINE_COUNT_U32 = LINE_COUNT;
    localparam logic [LATENCY_WIDTH-1:0] LATENCY_VALUE =
        LATENCY_CYCLES[LATENCY_WIDTH-1:0];
    localparam logic [LATENCY_WIDTH-1:0] ONE_COUNT = 1'b1;

    logic [MC_LINE_WIDTH-1:0] storage [0:LINE_COUNT-1];

    logic                         pending;
    logic                         request_seen;
    mc_line_mem_op_t              pending_op;
    logic [INDEX_WIDTH-1:0]       pending_index;
    logic [MC_LINE_WIDTH-1:0]     pending_wdata;
    logic                         pending_error;
    logic [LATENCY_WIDTH-1:0]     latency_count;

    wire [31:0] request_line_number = {
        {MC_LINE_OFFSET_BITS{1'b0}},
        memory_req_line_addr[MC_ADDR_WIDTH-1:MC_LINE_OFFSET_BITS]
    };
    wire request_unaligned =
        |memory_req_line_addr[MC_LINE_OFFSET_BITS-1:0];
    wire request_out_of_range =
        request_line_number >= LINE_COUNT_U32;

    always @* begin
        memory_req_ready = !rst && !pending && !request_seen;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pending         <= 1'b0;
            request_seen    <= 1'b0;
            pending_op      <= MC_LINE_READ;
            pending_index   <= {INDEX_WIDTH{1'b0}};
            pending_wdata   <= {MC_LINE_WIDTH{1'b0}};
            pending_error   <= 1'b0;
            latency_count   <= {LATENCY_WIDTH{1'b0}};
            memory_rsp_valid <= 1'b0;
            memory_rsp_rdata <= {MC_LINE_WIDTH{1'b0}};
            memory_rsp_error <= 1'b0;
        end else begin
            memory_rsp_valid <= 1'b0;

            if (!memory_req_valid)
                request_seen <= 1'b0;

            if (!pending) begin
                if (memory_req_valid && memory_req_ready) begin
                    pending         <= 1'b1;
                    request_seen    <= 1'b1;
                    pending_op      <= memory_req_op;
                    pending_index   <=
                        request_line_number[INDEX_WIDTH-1:0];
                    pending_wdata   <= memory_req_wdata;
                    pending_error   <=
                        request_unaligned || request_out_of_range;
                    latency_count   <= LATENCY_VALUE;
                end
            end else if (latency_count > ONE_COUNT) begin
                latency_count <= latency_count - ONE_COUNT;
            end else begin
                memory_rsp_rdata <= {MC_LINE_WIDTH{1'b0}};
                memory_rsp_error <= pending_error;

                if (!pending_error) begin
                    if (pending_op == MC_LINE_WRITE)
                        storage[pending_index] <= pending_wdata;
                    else
                        memory_rsp_rdata <= storage[pending_index];
                end

                memory_rsp_valid <= 1'b1;
                pending          <= 1'b0;
                latency_count    <= {LATENCY_WIDTH{1'b0}};
            end
        end
    end
endmodule
