// ============================================================
//  cpu_reg_file : 32 x 32-bit register file
//  Two combinational reads, one clocked write, and register 0
//  protected from writes.
// ============================================================
module cpu_reg_file (
    input              clk,
    input              rst,
    input              we,
    input      [4:0]   ra1, ra2,
    input      [4:0]   wa,
    input      [31:0]  wd,
    output     [31:0]  rd1, rd2,
    output     [31:0]  r_out [0:31]
);
    timeunit 1ns;
    timeprecision 1ps;

    reg [31:0] regs [0:31];
    integer i;

    assign rd1 = regs[ra1];
    assign rd2 = regs[ra2];

    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : EXPOSE
            assign r_out[g] = regs[g];
        end
    endgenerate

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;
        end else if (we && wa != 5'd0) begin
            regs[wa] <= wd;
        end
    end
endmodule
