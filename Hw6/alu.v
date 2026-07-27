// ============================================================
//  alu : واحد حساب و منطق
//  جمع، تفریق، و LUI. خروجیِ zero برای BEQ.
//  (ضرب و تقسیم اینجا نیست؛ در ماژولِ ترتیبیِ mul_div انجام می‌شود)
// ============================================================
module alu (
    input      [31:0] a,
    input      [31:0] b,
    input      [1:0]  op,        // 00=ADD , 01=SUB , 10=LUI
    output reg [31:0] y,
    output            zero
);
    always @(*) begin
        case (op)
            2'b00: y = a + b;
            2'b01: y = a - b;
            2'b10: y = {b[15:0], 16'b0};   // LUI
            default: y = a + b;
        endcase
    end
    assign zero = (y == 32'b0);
endmodule
