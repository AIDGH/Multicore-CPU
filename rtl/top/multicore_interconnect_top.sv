import mc_defs_pkg::*;
module multicore_interconnect_top #(
    parameter integer MEMORY_LINE_COUNT       = 256,
    parameter integer MEMORY_RESPONSE_LATENCY = 2
) (
    input  logic                         clk,
    input  logic                         rst,

    input  logic                         cache0_req_valid,
    output logic                         cache0_req_ready,
    input  mc_bus_txn_t                  cache0_req_txn,
    input  logic [MC_ADDR_WIDTH-1:0]     cache0_req_line_addr,
    input  logic [MC_LINE_WIDTH-1:0]     cache0_req_wdata,
    output logic                         cache0_rsp_valid,
    output logic [MC_LINE_WIDTH-1:0]     cache0_rsp_data,
    output logic                         cache0_rsp_shared,
    output logic                         cache0_rsp_error,
    output logic                         cache0_snoop_valid,
    output mc_bus_txn_t                  cache0_snoop_txn,
    output logic [MC_ADDR_WIDTH-1:0]     cache0_snoop_line_addr,
    output logic                         cache0_snoop_requester_id,
    input  logic                         cache0_snoop_rsp_valid,
    input  logic                         cache0_snoop_rsp_present,
    input  logic                         cache0_snoop_rsp_dirty,
    input  logic                         cache0_snoop_rsp_data_valid,
    input  logic [MC_LINE_WIDTH-1:0]     cache0_snoop_rsp_data,

    input  logic                         cache1_req_valid,
    output logic                         cache1_req_ready,
    input  mc_bus_txn_t                  cache1_req_txn,
    input  logic [MC_ADDR_WIDTH-1:0]     cache1_req_line_addr,
    input  logic [MC_LINE_WIDTH-1:0]     cache1_req_wdata,
    output logic                         cache1_rsp_valid,
    output logic [MC_LINE_WIDTH-1:0]     cache1_rsp_data,
    output logic                         cache1_rsp_shared,
    output logic                         cache1_rsp_error,
    output logic                         cache1_snoop_valid,
    output mc_bus_txn_t                  cache1_snoop_txn,
    output logic [MC_ADDR_WIDTH-1:0]     cache1_snoop_line_addr,
    output logic                         cache1_snoop_requester_id,
    input  logic                         cache1_snoop_rsp_valid,
    input  logic                         cache1_snoop_rsp_present,
    input  logic                         cache1_snoop_rsp_dirty,
    input  logic                         cache1_snoop_rsp_data_valid,
    input  logic [MC_LINE_WIDTH-1:0]     cache1_snoop_rsp_data
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [1:0]                   bus_l1_req_valid;
    logic [1:0]                   bus_l1_req_ready;
    logic [1:0]                   bus_l1_rsp_valid;
    logic [1:0]                   bus_l1_rsp_shared;
    logic [1:0]                   bus_l1_rsp_error;
    logic [MC_LINE_WIDTH-1:0]     bus_l1_rsp_data_0;
    logic [MC_LINE_WIDTH-1:0]     bus_l1_rsp_data_1;

    logic [1:0]                   bus_snoop_valid;
    mc_bus_txn_t                  bus_snoop_txn;
    logic [MC_ADDR_WIDTH-1:0]     bus_snoop_line_addr;
    logic                         bus_snoop_requester_id;
    logic [1:0]                   bus_snoop_rsp_valid;
    logic [1:0]                   bus_snoop_rsp_present;
    logic [1:0]                   bus_snoop_rsp_dirty;
    logic [1:0]                   bus_snoop_rsp_data_valid;

    logic                         memory_req_valid;
    logic                         memory_req_ready;
    mc_line_mem_op_t              memory_req_op;
    logic [MC_ADDR_WIDTH-1:0]     memory_req_line_addr;
    logic [MC_LINE_WIDTH-1:0]     memory_req_wdata;
    logic                         memory_rsp_valid;
    logic [MC_LINE_WIDTH-1:0]     memory_rsp_rdata;
    logic                         memory_rsp_error;

    assign bus_l1_req_valid = {cache1_req_valid, cache0_req_valid};
    assign cache0_req_ready = bus_l1_req_ready[0];
    assign cache1_req_ready = bus_l1_req_ready[1];

    assign cache0_rsp_valid  = bus_l1_rsp_valid[0];
    assign cache1_rsp_valid  = bus_l1_rsp_valid[1];
    assign cache0_rsp_data   = bus_l1_rsp_data_0;
    assign cache1_rsp_data   = bus_l1_rsp_data_1;
    assign cache0_rsp_shared = bus_l1_rsp_shared[0];
    assign cache1_rsp_shared = bus_l1_rsp_shared[1];
    assign cache0_rsp_error  = bus_l1_rsp_error[0];
    assign cache1_rsp_error  = bus_l1_rsp_error[1];

    assign cache0_snoop_valid        = bus_snoop_valid[0];
    assign cache1_snoop_valid        = bus_snoop_valid[1];
    assign cache0_snoop_txn          = bus_snoop_txn;
    assign cache1_snoop_txn          = bus_snoop_txn;
    assign cache0_snoop_line_addr    = bus_snoop_line_addr;
    assign cache1_snoop_line_addr    = bus_snoop_line_addr;
    assign cache0_snoop_requester_id = bus_snoop_requester_id;
    assign cache1_snoop_requester_id = bus_snoop_requester_id;

    assign bus_snoop_rsp_valid = {
        cache1_snoop_rsp_valid,
        cache0_snoop_rsp_valid
    };
    assign bus_snoop_rsp_present = {
        cache1_snoop_rsp_present,
        cache0_snoop_rsp_present
    };
    assign bus_snoop_rsp_dirty = {
        cache1_snoop_rsp_dirty,
        cache0_snoop_rsp_dirty
    };
    assign bus_snoop_rsp_data_valid = {
        cache1_snoop_rsp_data_valid,
        cache0_snoop_rsp_data_valid
    };

    shared_bus bus (
        .clk(clk),
        .rst(rst),
        .l1_req_valid(bus_l1_req_valid),
        .l1_req_ready(bus_l1_req_ready),
        .l1_req_txn_0(cache0_req_txn),
        .l1_req_txn_1(cache1_req_txn),
        .l1_req_line_addr_0(cache0_req_line_addr),
        .l1_req_line_addr_1(cache1_req_line_addr),
        .l1_req_wdata_0(cache0_req_wdata),
        .l1_req_wdata_1(cache1_req_wdata),
        .l1_rsp_valid(bus_l1_rsp_valid),
        .l1_rsp_data_0(bus_l1_rsp_data_0),
        .l1_rsp_data_1(bus_l1_rsp_data_1),
        .l1_rsp_shared(bus_l1_rsp_shared),
        .l1_rsp_error(bus_l1_rsp_error),
        .snoop_valid(bus_snoop_valid),
        .snoop_txn(bus_snoop_txn),
        .snoop_line_addr(bus_snoop_line_addr),
        .snoop_requester_id(bus_snoop_requester_id),
        .snoop_rsp_valid(bus_snoop_rsp_valid),
        .snoop_rsp_present(bus_snoop_rsp_present),
        .snoop_rsp_dirty(bus_snoop_rsp_dirty),
        .snoop_rsp_data_valid(bus_snoop_rsp_data_valid),
        .snoop_rsp_data_0(cache0_snoop_rsp_data),
        .snoop_rsp_data_1(cache1_snoop_rsp_data),
        .memory_req_valid(memory_req_valid),
        .memory_req_ready(memory_req_ready),
        .memory_req_op(memory_req_op),
        .memory_req_line_addr(memory_req_line_addr),
        .memory_req_wdata(memory_req_wdata),
        .memory_rsp_valid(memory_rsp_valid),
        .memory_rsp_rdata(memory_rsp_rdata),
        .memory_rsp_error(memory_rsp_error)
    );

    shared_memory #(
        .LINE_COUNT(MEMORY_LINE_COUNT),
        .RESPONSE_LATENCY(MEMORY_RESPONSE_LATENCY)
    ) memory (
        .clk(clk),
        .rst(rst),
        .memory_req_valid(memory_req_valid),
        .memory_req_ready(memory_req_ready),
        .memory_req_op(memory_req_op),
        .memory_req_line_addr(memory_req_line_addr),
        .memory_req_wdata(memory_req_wdata),
        .memory_rsp_valid(memory_rsp_valid),
        .memory_rsp_rdata(memory_rsp_rdata),
        .memory_rsp_error(memory_rsp_error)
    );
endmodule
