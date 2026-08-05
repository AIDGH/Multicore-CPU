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

    function automatic [31:0] ITYPE(input [5:0] opcode, input [4:0] rs, input [4:0] rt, input [15:0] imm);
        ITYPE = {opcode, rs, rt, imm};
    endfunction

    function automatic [31:0] ATYPE(input [5:0] opcode, input [4:0] rs, input [4:0] rt, input [4:0] rd, input [5:0] funct);
        ATYPE = {opcode, rs, rt, rd, 5'b0, funct};
    endfunction

    logic [31:0] instructions [0:15];

    assign core0_instr_in = instructions[core0_instr_addr[3:0]];
    assign core1_instr_in = instructions[core1_instr_addr[3:0]];

    initial begin
        $dumpfile("build/dual_core_top/waves.vcd");
        $dumpvars(0, tb_dual_core_top);

        instructions[0] = ITYPE(6'b001000, 5'd0, 5'd1, 16'h0010); // تنظیم آدرس قفل
            instructions[1] = ITYPE(6'b001000, 5'd0, 5'd5, 16'h0020); // تنظیم آدرس کانتر

            instructions[2] = ITYPE(6'b101011, 5'd1, 5'd0, 16'd0);    // sw R0, 0(R1)
            instructions[3] = ITYPE(6'b101011, 5'd5, 5'd0, 16'd0);    // sw R0, 0(R5)

            instructions[4] = ATYPE(6'b010111, 5'd1, 5'd0, 5'd2, 6'b000010); // lr.w R2, (R1)
            instructions[5] = ITYPE(6'b000101, 5'd2, 5'd0, 16'hFFFE);        // bne R2, R0, -2
            instructions[6] = ITYPE(6'b001000, 5'd0, 5'd3, 16'd1);           // addi R3, R0, 1
            instructions[7] = ATYPE(6'b010111, 5'd1, 5'd3, 5'd3, 6'b000011); // sc.w R3, (R1)
            instructions[8] = ITYPE(6'b000101, 5'd3, 5'd0, 16'hFFFB);        // bne R3, R0, -5
            
            instructions[9] = ITYPE(6'b100011, 5'd5, 5'd4, 16'd0);           // lw R4, 0(R5)
            instructions[10] = ITYPE(6'b001000, 5'd4, 5'd4, 16'd1);          // addi R4, R4, 1
            instructions[11] = ITYPE(6'b101011, 5'd5, 5'd4, 16'd0);          // sw R4, 0(R5)
            instructions[12] = ITYPE(6'b101011, 5'd1, 5'd0, 16'd0);          // sw R0, 0(R1)

            for (int i = 13; i < 16; i++) instructions[i] = 32'd0;

        $display("   Starting Dual-Core Spinlock Test...  ");

        #20 rst = 0;

        repeat(250) @(posedge clk);

        $display(" Integration Test Finished! Check Waveforms ");
        $finish;
    end

endmodule