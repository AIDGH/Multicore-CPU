// ============================================================
//  cpu_alu : arithmetic and logic unit
//  Add, subtract, and LUI. The zero output is used by BEQ.
//  Multiplication and division are handled by cpu_mul_div.
// ============================================================
module cpu_alu (
    input      [31:0] a,
    input      [31:0] b,
    input      [1:0]  op,
    output reg [31:0] y,
    output            zero
);
    always @(*) begin
        case (op)
            2'b00: y = a + b;
            2'b01: y = a - b;
            2'b10: y = {b[15:0], 16'b0};
            default: y = a + b;
        endcase
    end

    assign zero = (y == 32'b0);
endmodule
