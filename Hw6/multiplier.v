// ============================================================
//  multiplier : ضرب‌کننده‌ی ترتیبی (shift-add) - بدون عملگر *
//  خروجی: (a*b)[31:0]  در ۳۲ گام
//  زمان‌بندی: یک سیکل بارگذاری + ۳۲ گام؛ سپس done یک سیکل بالا.
// ============================================================
module multiplier (
    input             clk, rst, start,
    input      [31:0] a, b,
    output     [31:0] result,
    output reg        busy,
    output reg        done
);
    reg [31:0] product, acc, mlt;
    reg [5:0]  count;

    assign result = product;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0; done <= 1'b0;
            product <= 32'b0; acc <= 32'b0; mlt <= 32'b0; count <= 6'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                acc <= a; mlt <= b; product <= 32'b0; count <= 6'd32; busy <= 1'b1;
            end else if (busy) begin
                if (mlt[0]) product <= product + acc;  // بیتِ جاری ۱ بود؟ جمع کن
                acc   <= acc << 1;
                mlt   <= mlt >> 1;
                count <= count - 6'd1;
                if (count == 6'd1) begin busy <= 1'b0; done <= 1'b1; end
            end
        end
    end
endmodule
