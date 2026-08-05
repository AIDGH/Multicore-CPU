`timescale 1ns/1ps
import mc_defs_pkg::*;

module dual_core_top #(
    parameter integer MEMORY_LINE_COUNT       = 256,
    parameter integer MEMORY_RESPONSE_LATENCY = 2
) (
    input  logic        clk,
    input  logic        rst,

    // Instruction Memory / Fetch Interfaces for Core 0 & Core 1
    input  logic [31:0] core0_instr_in,
    output logic [31:0] core0_instr_addr,

    input  logic [31:0] core1_instr_in,
    output logic [31:0] core1_instr_addr,

    // Debug Register Displays for Core 0
    output logic [31:0] core0_R [0:31],

    // Debug Register Displays for Core 1
    output logic [31:0] core1_R [0:31]
);

    // =========================================================
    // Core 0 <-> Cache 0 Wires
    // =========================================================
    logic        c0_req_valid;
    logic        c0_req_ready;
    logic [31:0] c0_req_addr;
    logic [2:0]  c0_req_op;
    logic [31:0] c0_req_wdata;
    logic        c0_rsp_valid;
    logic [31:0] c0_rsp_rdata;
    logic        c0_rsp_error;
    logic        c0_cancel_reservation;
    logic        c0_req_write_unused;

    // =========================================================
    // Core 1 <-> Cache 1 Wires
    // =========================================================
    logic        c1_req_valid;
    logic        c1_req_ready;
    logic [31:0] c1_req_addr;
    logic [2:0]  c1_req_op;
    logic [31:0] c1_req_wdata;
    logic        c1_rsp_valid;
    logic [31:0] c1_rsp_rdata;
    logic        c1_rsp_error;
    logic        c1_cancel_reservation;
    logic        c1_req_write_unused;

    // =========================================================
    // Cache 0 <-> Bus Interconnect Wires
    // =========================================================
    logic         c0_bus_req;
    logic         c0_bus_req_rdx;
    logic [31:0]  c0_bus_req_addr;
    logic [127:0] c0_bus_req_wdata;   // Added: Write-Back Data
    logic         c0_bus_gnt;
    logic         c0_bus_rsp_valid;
    logic [127:0] c0_bus_rsp_rdata;
    logic         c0_bus_rsp_shared;  // Added: Shared Response
    logic         c0_bus_rsp_error;   // Added: Error Response

    logic         c0_snoop_valid;
    mc_bus_txn_t  c0_snoop_txn;       // Added: Snoop Transaction Type
    logic [31:0]  c0_snoop_addr;
    logic         c0_snoop_rdx;
    logic         c0_snoop_shared;
    logic         c0_snoop_flush;
    logic [127:0] c0_snoop_wdata;
    logic         c0_snoop_rsp_valid; // Added: Snoop Ack

    mc_bus_txn_t  c0_bus_txn;

    // =========================================================
    // Cache 1 <-> Bus Interconnect Wires
    // =========================================================
    logic         c1_bus_req;
    logic         c1_bus_req_rdx;
    logic [31:0]  c1_bus_req_addr;
    logic [127:0] c1_bus_req_wdata;   // Added: Write-Back Data
    logic         c1_bus_gnt;
    logic         c1_bus_rsp_valid;
    logic [127:0] c1_bus_rsp_rdata;
    logic         c1_bus_rsp_shared;  // Added: Shared Response
    logic         c1_bus_rsp_error;   // Added: Error Response

    logic         c1_snoop_valid;
    mc_bus_txn_t  c1_snoop_txn;       // Added: Snoop Transaction Type
    logic [31:0]  c1_snoop_addr;
    logic         c1_snoop_rdx;
    logic         c1_snoop_shared;
    logic         c1_snoop_flush;
    logic [127:0] c1_snoop_wdata;
    logic         c1_snoop_rsp_valid; // Added: Snoop Ack

    mc_bus_txn_t  c1_bus_txn;

    // Transaction Type Mapping
    always_comb begin
        if (c0_bus_req_rdx) c0_bus_txn = MC_BUS_RDX;
        else                c0_bus_txn = MC_BUS_RD;

        if (c1_bus_req_rdx) c1_bus_txn = MC_BUS_RDX;
        else                c1_bus_txn = MC_BUS_RD;
    end

    // Active-Low Reset for Cache Modules
    wire rst_n = ~rst;

    // =========================================================
    // 1. Core 0 & Core 1 Instantiation
    // =========================================================
    cpu_core u_core0 (
        .Clk                (clk),
        .Rst                (rst),
        .core_id            (1'b0),
        .cancel_reservation (c0_cancel_reservation),
        .InstrIn            (core0_instr_in),
        .InstrAddr          (core0_instr_addr),
        .data_req_valid     (c0_req_valid),
        .data_req_ready     (c0_req_ready),
        .data_req_addr      (c0_req_addr),
        .data_req_write     (c0_req_write_unused),
        .data_req_op        (c0_req_op),
        .data_req_wdata     (c0_req_wdata),
        .data_rsp_valid     (c0_rsp_valid),
        .data_rsp_rdata     (c0_rsp_rdata),
        .data_rsp_error     (c0_rsp_error),
        .R0(core0_R[0]),   .R1(core0_R[1]),   .R2(core0_R[2]),   .R3(core0_R[3]),
        .R4(core0_R[4]),   .R5(core0_R[5]),   .R6(core0_R[6]),   .R7(core0_R[7]),
        .R8(core0_R[8]),   .R9(core0_R[9]),   .R10(core0_R[10]), .R11(core0_R[11]),
        .R12(core0_R[12]), .R13(core0_R[13]), .R14(core0_R[14]), .R15(core0_R[15]),
        .R16(core0_R[16]), .R17(core0_R[17]), .R18(core0_R[18]), .R19(core0_R[19]),
        .R20(core0_R[20]), .R21(core0_R[21]), .R22(core0_R[22]), .R23(core0_R[23]),
        .R24(core0_R[24]), .R25(core0_R[25]), .R26(core0_R[26]), .R27(core0_R[27]),
        .R28(core0_R[28]), .R29(core0_R[29]), .R30(core0_R[30]), .R31(core0_R[31])
    );

    cpu_core u_core1 (
        .Clk                (clk),
        .Rst                (rst),
        .core_id            (1'b1),
        .cancel_reservation (c1_cancel_reservation),
        .InstrIn            (core1_instr_in),
        .InstrAddr          (core1_instr_addr),
        .data_req_valid     (c1_req_valid),
        .data_req_ready     (c1_req_ready),
        .data_req_addr      (c1_req_addr),
        .data_req_write     (c1_req_write_unused),
        .data_req_op        (c1_req_op),
        .data_req_wdata     (c1_req_wdata),
        .data_rsp_valid     (c1_rsp_valid),
        .data_rsp_rdata     (c1_rsp_rdata),
        .data_rsp_error     (c1_rsp_error),
        .R0(core1_R[0]),   .R1(core1_R[1]),   .R2(core1_R[2]),   .R3(core1_R[3]),
        .R4(core1_R[4]),   .R5(core1_R[5]),   .R6(core1_R[6]),   .R7(core1_R[7]),
        .R8(core1_R[8]),   .R9(core1_R[9]),   .R10(core1_R[10]), .R11(core1_R[11]),
        .R12(core1_R[12]), .R13(core1_R[13]), .R14(core1_R[14]), .R15(core1_R[15]),
        .R16(core1_R[16]), .R17(core1_R[17]), .R18(core1_R[18]), .R19(core1_R[19]),
        .R20(core1_R[20]), .R21(core1_R[21]), .R22(core1_R[22]), .R23(core1_R[23]),
        .R24(core1_R[24]), .R25(core1_R[25]), .R26(core1_R[26]), .R27(core1_R[27]),
        .R28(core1_R[28]), .R29(core1_R[29]), .R30(core1_R[30]), .R31(core1_R[31])
    );

    // =========================================================
    // 2. L1 MESI Cache Instantiation
    // =========================================================
    l1_cache_mesi u_cache0 (
        .clk                (clk),
        .rst_n              (rst_n),
        .data_req_valid     (c0_req_valid),
        .data_req_ready     (c0_req_ready),
        .data_req_addr      (c0_req_addr),
        .data_req_op        (c0_req_op),
        .data_req_wdata     (c0_req_wdata),
        .data_rsp_valid     (c0_rsp_valid),
        .data_rsp_rdata     (c0_rsp_rdata),
        .data_rsp_error     (c0_rsp_error),
        .cancel_reservation (c0_cancel_reservation),

        .bus_req            (c0_bus_req),
        .bus_req_rdx        (c0_bus_req_rdx),
        .bus_req_addr       (c0_bus_req_addr),
        .bus_req_wdata      (c0_bus_req_wdata),   // Fixed
        .bus_gnt            (c0_bus_gnt),
        .bus_rsp_valid      (c0_bus_rsp_valid),
        .bus_rsp_rdata      (c0_bus_rsp_rdata),
        .bus_rsp_shared     (c0_bus_rsp_shared),  // Fixed
        .bus_rsp_error      (c0_bus_rsp_error),   // Fixed

        .snoop_valid        (c0_snoop_valid),
        .snoop_txn          (c0_snoop_txn),       // Fixed
        .snoop_addr         (c0_snoop_addr),
        .snoop_rdx          (c0_snoop_rdx),
        .snoop_rsp_valid    (c0_snoop_rsp_valid), // Fixed
        .snoop_shared       (c0_snoop_shared),
        .snoop_flush        (c0_snoop_flush),
        .snoop_wdata        (c0_snoop_wdata)
    );

    l1_cache_mesi u_cache1 (
        .clk                (clk),
        .rst_n              (rst_n),
        .data_req_valid     (c1_req_valid),
        .data_req_ready     (c1_req_ready),
        .data_req_addr      (c1_req_addr),
        .data_req_op        (c1_req_op),
        .data_req_wdata     (c1_req_wdata),
        .data_rsp_valid     (c1_rsp_valid),
        .data_rsp_rdata     (c1_rsp_rdata),
        .data_rsp_error     (c1_rsp_error),
        .cancel_reservation (c1_cancel_reservation),

        .bus_req            (c1_bus_req),
        .bus_req_rdx        (c1_bus_req_rdx),
        .bus_req_addr       (c1_bus_req_addr),
        .bus_req_wdata      (c1_bus_req_wdata),   // Fixed
        .bus_gnt            (c1_bus_gnt),
        .bus_rsp_valid      (c1_bus_rsp_valid),
        .bus_rsp_rdata      (c1_bus_rsp_rdata),
        .bus_rsp_shared     (c1_bus_rsp_shared),  // Fixed
        .bus_rsp_error      (c1_bus_rsp_error),   // Fixed

        .snoop_valid        (c1_snoop_valid),
        .snoop_txn          (c1_snoop_txn),       // Fixed
        .snoop_addr         (c1_snoop_addr),
        .snoop_rdx          (c1_snoop_rdx),
        .snoop_rsp_valid    (c1_snoop_rsp_valid), // Fixed
        .snoop_shared       (c1_snoop_shared),
        .snoop_flush        (c1_snoop_flush),
        .snoop_wdata        (c1_snoop_wdata)
    );

    // =========================================================
    // 3. Multicore Interconnect Top Instantiation
    // =========================================================
    multicore_interconnect_top #(
        .MEMORY_LINE_COUNT(MEMORY_LINE_COUNT),
        .MEMORY_RESPONSE_LATENCY(MEMORY_RESPONSE_LATENCY)
    ) u_interconnect (
        .clk                         (clk),
        .rst                         (rst),

        // Cache 0 Interface
        .cache0_req_valid            (c0_bus_req),
        .cache0_req_ready            (c0_bus_gnt),
        .cache0_req_txn              (c0_bus_txn),
        .cache0_req_line_addr        (c0_bus_req_addr),
        .cache0_req_wdata            (c0_bus_req_wdata),  // Fixed (was c0_snoop_wdata)
        .cache0_rsp_valid            (c0_bus_rsp_valid),
        .cache0_rsp_data             (c0_bus_rsp_rdata),
        .cache0_rsp_shared           (c0_bus_rsp_shared), // Fixed
        .cache0_rsp_error            (c0_bus_rsp_error),  // Fixed

        .cache0_snoop_valid          (c0_snoop_valid),
        .cache0_snoop_txn            (c0_snoop_txn),      // Fixed
        .cache0_snoop_line_addr      (c0_snoop_addr),
        .cache0_snoop_requester_id   (),
        .cache0_snoop_rsp_valid      (c0_snoop_rsp_valid),// Fixed (was 1'b1)
        .cache0_snoop_rsp_present    (c0_snoop_shared),
        .cache0_snoop_rsp_dirty      (c0_snoop_flush),
        .cache0_snoop_rsp_data_valid (c0_snoop_flush),
        .cache0_snoop_rsp_data       (c0_snoop_wdata),

        // Cache 1 Interface
        .cache1_req_valid            (c1_bus_req),
        .cache1_req_ready            (c1_bus_gnt),
        .cache1_req_txn              (c1_bus_txn),
        .cache1_req_line_addr        (c1_bus_req_addr),
        .cache1_req_wdata            (c1_bus_req_wdata),  // Fixed (was c1_snoop_wdata)
        .cache1_rsp_valid            (c1_bus_rsp_valid),
        .cache1_rsp_data             (c1_bus_rsp_rdata),
        .cache1_rsp_shared           (c1_bus_rsp_shared), // Fixed
        .cache1_rsp_error            (c1_bus_rsp_error),  // Fixed

        .cache1_snoop_valid          (c1_snoop_valid),
        .cache1_snoop_txn            (c1_snoop_txn),      // Fixed
        .cache1_snoop_line_addr      (c1_snoop_addr),
        .cache1_snoop_requester_id   (),
        .cache1_snoop_rsp_valid      (c1_snoop_rsp_valid),// Fixed (was 1'b1)
        .cache1_snoop_rsp_present    (c1_snoop_shared),
        .cache1_snoop_rsp_dirty      (c1_snoop_flush),
        .cache1_snoop_rsp_data_valid (c1_snoop_flush),
        .cache1_snoop_rsp_data       (c1_snoop_wdata)
    );

    // Snoop Read/Write type drive logic
    assign c0_snoop_rdx = (c0_snoop_txn == MC_BUS_RDX);
    assign c1_snoop_rdx = (c1_snoop_txn == MC_BUS_RDX);

endmodule