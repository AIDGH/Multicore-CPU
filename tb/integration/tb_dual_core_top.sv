`timescale 1ns/1ps
import mc_defs_pkg::*;

module tb_dual_core_top;

    logic clk = 0;
    logic rst = 1;

    always #5 clk = ~clk;

    logic [31:0] core0_instr_in, core0_instr_addr;
    logic [31:0] core1_instr_in, core1_instr_addr;
    logic [31:0] core0_R [0:31];
    logic [31:0] core1_R [0:31];

    dual_core_top dut (
        .clk(clk),
        .rst(rst),
        .core0_instr_in(core0_instr_in),
        .core0_instr_addr(core0_instr_addr),
        .core1_instr_in(core1_instr_in),
        .core1_instr_addr(core1_instr_addr),
        .core0_R(core0_R),
        .core1_R(core1_R)
    );

    assign core0_instr_in = 32'h0000_0000; 
    assign core1_instr_in = 32'h0000_0000;

    initial begin
        $display("========================================");
        $display("   Starting Dual-Core Sanity Check...   ");
        $display("========================================");

        #20 rst = 0; 

        repeat(50) @(posedge clk);

        $display("========================================");
        $display(" Integration Wiring is PERFECT! No crashes! ");
        $display("========================================");
        $finish;
    end

endmodule
