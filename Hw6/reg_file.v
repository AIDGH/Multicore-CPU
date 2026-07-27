// ============================================================
//  reg_file : بانک ثبات
//  32 ثبات 32 بیتی، دو پورت خواندن، یک پورت نوشتن، $0 همیشه صفر
// ============================================================
module reg_file (
    input              clk,
    input              rst,
    input              we,            // RegWrite
    input      [4:0]   ra1, ra2,      // آدرس دو پورتِ خواندن (rs و rt)
    input      [4:0]   wa,            // آدرس پورتِ نوشتن
    input      [31:0]  wd,            // داده‌ی نوشتنی
    output     [31:0]  rd1, rd2,      // خروجی دو پورتِ خواندن
    output     [31:0]  r_out [0:31]   // همه‌ی ۳۲ ثبات (برای بیرون دادن به tb)
);
    reg [31:0] regs [0:31];
    integer i;

    // خواندنِ ترکیبی
    assign rd1 = regs[ra1];
    assign rd2 = regs[ra2];

    // بیرون دادنِ کل ثبات‌ها
    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : EXPOSE
            assign r_out[g] = regs[g];
        end
    endgenerate

    // نوشتنِ سنکرون + جلوگیری از نوشتن در $0
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;
        end else if (we && wa != 5'd0) begin
            regs[wa] <= wd;
        end
    end
endmodule
