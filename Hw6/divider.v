// ============================================================
//  divider : تقسیم‌کننده‌ی ترتیبی (restoring) - بدون عملگر /
//  خروجی: خارج‌قسمتِ a / b (بدون علامت) در ۳۲ گام
//  زمان‌بندی همانندِ multiplier است.
// ============================================================
module divider (
    input             clk, rst, start,
    input      [31:0] a, b,
    output     [31:0] result,
    output reg        busy,
    output reg        done
);
    reg [31:0] Q, R, b_reg;
    reg [5:0]  count;

    wire [32:0] shifted   = {R, Q[31]};        // {R,Q} یک رتبه به چپ
    wire [32:0] divisor33 = {1'b0, b_reg};
    wire        ge        = (shifted >= divisor33);
    wire [32:0] sub       = shifted - divisor33;

    assign result = Q;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0; done <= 1'b0;
            Q <= 32'b0; R <= 32'b0; b_reg <= 32'b0; count <= 6'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                Q <= a; R <= 32'b0; b_reg <= b; count <= 6'd32; busy <= 1'b1;
            end else if (busy) begin
                if (ge) begin R <= sub[31:0];     Q <= {Q[30:0], 1'b1}; end  // جا شد
                else    begin R <= shifted[31:0]; Q <= {Q[30:0], 1'b0}; end  // جا نشد
                count <= count - 6'd1;
                if (count == 6'd1) begin busy <= 1'b0; done <= 1'b1; end
            end
        end
    end
endmodule
