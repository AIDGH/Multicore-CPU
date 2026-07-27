// ============================================================
//  main : پردازنده‌ی تک‌چرخه‌ی 32 بیتی (الهام‌گرفته از MIPS)
//  معماری کامپیوتر - تمرین 5
//
//  این فایل فقط مسیرِ داده و اتصالات است؛ زیرماژول‌ها در فایل‌های جدا:
//    reg_file.v , alu.v , control.v , multiplier.v , divider.v , mul_div.v
//
//  نکات کلیدی:
//   - PC داخلی بایتی است؛ برای حافظه دو بیتِ پایین را می‌اندازیم (>>2).
//   - ضرب/تقسیم ترتیبی است و با سیگنالِ stall، PC را فریز می‌کند.
// ============================================================
module main (
    input              Clk,
    input              Rst,
    input      [31:0]  InstrIn,
    output     [31:0]  InstrAddr,
    input      [31:0]  DataIn,
    output     [31:0]  DataOut,
    output             DataWrite,
    output     [31:0]  DataAddr,
    output     [31:0]  R0,  R1,  R2,  R3,  R4,  R5,  R6,  R7,
    output     [31:0]  R8,  R9,  R10, R11, R12, R13, R14, R15,
    output     [31:0]  R16, R17, R18, R19, R20, R21, R22, R23,
    output     [31:0]  R24, R25, R26, R27, R28, R29, R30, R31
);
    // ---------- شمارنده‌ی برنامه ----------
    reg  [31:0] PC;
    wire [31:0] pc_plus_4 = PC + 32'd4;

    // ---------- میدان‌های دستور ----------
    wire [5:0]  opcode = InstrIn[31:26];
    wire [4:0]  rs     = InstrIn[25:21];
    wire [4:0]  rt     = InstrIn[20:16];
    wire [4:0]  rd     = InstrIn[15:11];
    wire [5:0]  funct  = InstrIn[5:0];
    wire [15:0] imm    = InstrIn[15:0];
    wire [25:0] addr26 = InstrIn[25:0];
    wire [31:0] imm_sext = {{16{imm[15]}}, imm};   // تعمیمِ علامت

    // ---------- سیگنال‌های کنترلی ----------
    wire [1:0] RegDst, MemtoReg, ALUOp;
    wire       RegWrite, ALUSrc, MemRead, MemWrite;
    wire       Branch, Jump, Jal, JumpReg, is_muldiv, is_div;

    control u_ctrl (
        .opcode(opcode), .funct(funct),
        .RegDst(RegDst), .RegWrite(RegWrite), .ALUSrc(ALUSrc),
        .MemtoReg(MemtoReg), .MemRead(MemRead), .MemWrite(MemWrite),
        .Branch(Branch), .Jump(Jump), .Jal(Jal), .JumpReg(JumpReg),
        .ALUOp(ALUOp), .is_muldiv(is_muldiv), .is_div(is_div)
    );

    // ---------- واحد ضرب/تقسیم + سیگنالِ stall ----------
    wire [31:0] md_result;
    wire        md_busy, md_done;
    wire        md_start = is_muldiv & ~md_busy & ~md_done;  // فقط وقتی بیکار است شروع کن
    wire        stall    = is_muldiv & ~md_done;             // تا آماده نشده، فریز

    // ---------- بانک ثبات ----------
    wire [31:0] rs_val, rt_val;
    wire [31:0] regs_o [0:31];
    wire [4:0]  write_reg = (RegDst == 2'd1) ? rd :          // R-type
                            (RegDst == 2'd2) ? 5'd31 : rt;    // JAL / I-type
    wire [31:0] write_data;
    wire        reg_we = RegWrite & ~stall;                  // موقع stall ننویس

    reg_file u_rf (
        .clk(Clk), .rst(Rst), .we(reg_we),
        .ra1(rs), .ra2(rt), .wa(write_reg), .wd(write_data),
        .rd1(rs_val), .rd2(rt_val), .r_out(regs_o)
    );

    // ---------- ALU ----------
    wire [31:0] alu_b = ALUSrc ? imm_sext : rt_val;          // انتخابِ عملوند دوم
    wire [31:0] alu_y;
    wire        zero;
    alu u_alu (.a(rs_val), .b(alu_b), .op(ALUOp), .y(alu_y), .zero(zero));

    // ---------- واحد ضرب/تقسیم ----------
    mul_div u_md (
        .clk(Clk), .rst(Rst), .start(md_start), .is_div(is_div),
        .a(rs_val), .b(rt_val),
        .result(md_result), .busy(md_busy), .done(md_done)
    );

    // ---------- نتیجه‌ی محاسبه: ALU یا ضرب/تقسیم ----------
    wire [31:0] compute_result = is_muldiv ? md_result : alu_y;

    // ---------- داده‌ی نوشتنی در ثبات (MemtoReg) ----------
    assign write_data = (MemtoReg == 2'd1) ? DataIn        :  // LW
                        (MemtoReg == 2'd2) ? pc_plus_4     :  // JAL
                                             compute_result;  // ALU/MUL/DIV

    // ---------- ارتباط با حافظه‌ی داده ----------
    assign DataOut   = rt_val;                               // برای SW
    assign DataWrite = MemWrite & ~stall;
    assign DataAddr  = (MemRead | MemWrite) ? {2'b00, alu_y[31:2]}  // >>2 : آدرسِ کلمه‌ای
                                            : 32'h0000_4000;         // وقتی حافظه‌ای نیست (تمیز ماندنِ لاگ)

    // ---------- آدرسِ دستور ----------
    assign InstrAddr = PC >> 2;                              // >>2 : آدرسِ کلمه‌ای

    // ---------- PC بعدی ----------
    wire [31:0] branch_target = pc_plus_4 + (imm_sext << 2); // BEQ : شیفتِ ۲ روی imm
    wire [31:0] jump_target   = {PC[31:28], addr26, 2'b00};  // J / JAL
    wire [31:0] next_pc = JumpReg         ? rs_val        :  // JR
                          Jump            ? jump_target   :  // J / JAL
                          (Branch & zero) ? branch_target :  // BEQ گرفته‌شده
                                            pc_plus_4;        // عادی

    always @(posedge Clk or posedge Rst) begin
        if (Rst)          PC <= 32'b0;
        else if (!stall)  PC <= next_pc;                     // موقع ضرب/تقسیم ثابت می‌ماند
    end

    // ---------- بیرون دادنِ ثبات‌ها ----------
    assign R0=regs_o[0];   assign R1=regs_o[1];   assign R2=regs_o[2];   assign R3=regs_o[3];
    assign R4=regs_o[4];   assign R5=regs_o[5];   assign R6=regs_o[6];   assign R7=regs_o[7];
    assign R8=regs_o[8];   assign R9=regs_o[9];   assign R10=regs_o[10]; assign R11=regs_o[11];
    assign R12=regs_o[12]; assign R13=regs_o[13]; assign R14=regs_o[14]; assign R15=regs_o[15];
    assign R16=regs_o[16]; assign R17=regs_o[17]; assign R18=regs_o[18]; assign R19=regs_o[19];
    assign R20=regs_o[20]; assign R21=regs_o[21]; assign R22=regs_o[22]; assign R23=regs_o[23];
    assign R24=regs_o[24]; assign R25=regs_o[25]; assign R26=regs_o[26]; assign R27=regs_o[27];
    assign R28=regs_o[28]; assign R29=regs_o[29]; assign R30=regs_o[30]; assign R31=regs_o[31];

endmodule
