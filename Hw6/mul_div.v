// ============================================================
//  mul_div : بسته‌بندیِ ضرب/تقسیم
//  هر دو واحدِ ترتیبی را نگه می‌دارد و بر اساسِ is_div سوئیچ می‌کند.
//  چون در طولِ عملیات PC فریز است، is_div ثابت می‌ماند.
// ============================================================
module mul_div (
    input             clk, rst, start, is_div,
    input      [31:0] a, b,
    output     [31:0] result,
    output            busy,
    output            done
);
    wire        mul_busy, mul_done, div_busy, div_done;
    wire [31:0] mul_res,  div_res;

    multiplier u_mul (
        .clk(clk), .rst(rst), .start(start & ~is_div),
        .a(a), .b(b), .result(mul_res), .busy(mul_busy), .done(mul_done)
    );
    divider u_div (
        .clk(clk), .rst(rst), .start(start &  is_div),
        .a(a), .b(b), .result(div_res), .busy(div_busy), .done(div_done)
    );

    assign result = is_div ? div_res  : mul_res;
    assign busy   = is_div ? div_busy : mul_busy;
    assign done   = is_div ? div_done : mul_done;
endmodule
