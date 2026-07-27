// ============================================================
//  control : واحد کنترل
//  از روی opcode و funct همه‌ی سیگنال‌های کنترلی را تولید می‌کند.
//  پیش‌فرضِ همه‌چیز NOP است؛ فقط لازم‌ها برای هر دستور روشن می‌شوند.
// ============================================================
module control (
    input      [5:0] opcode,
    input      [5:0] funct,
    output reg [1:0] RegDst,     // 0=rt , 1=rd , 2=$31
    output reg       RegWrite,
    output reg       ALUSrc,     // 0=rt , 1=imm
    output reg [1:0] MemtoReg,   // 0=نتیجه‌ی محاسبه , 1=حافظه , 2=PC+4
    output reg       MemRead,
    output reg       MemWrite,
    output reg       Branch,     // BEQ
    output reg       Jump,       // J / JAL
    output reg       Jal,        // JAL
    output reg       JumpReg,    // JR
    output reg [1:0] ALUOp,      // 00=ADD , 01=SUB , 10=LUI
    output reg       is_muldiv,  // MUL یا DIV
    output reg       is_div      // 0=MUL , 1=DIV
);
    localparam OP_RTYPE = 6'b000000;
    localparam OP_ADDI  = 6'b001000;
    localparam OP_SUBI  = 6'b001001;
    localparam OP_LUI   = 6'b001111;
    localparam OP_LW    = 6'b100011;
    localparam OP_SW    = 6'b101011;
    localparam OP_BEQ   = 6'b000100;
    localparam OP_J     = 6'b000010;
    localparam OP_JAL   = 6'b000011;

    localparam F_ADD = 6'b100000;
    localparam F_SUB = 6'b100010;
    localparam F_MUL = 6'b011000;
    localparam F_DIV = 6'b011010;
    localparam F_JR  = 6'b001000;

    localparam ALU_ADD = 2'b00;
    localparam ALU_SUB = 2'b01;
    localparam ALU_LUI = 2'b10;

    always @(*) begin
        // پیش‌فرضِ امن = NOP
        RegDst=2'd0; RegWrite=1'b0; ALUSrc=1'b0; MemtoReg=2'd0;
        MemRead=1'b0; MemWrite=1'b0; Branch=1'b0; Jump=1'b0;
        Jal=1'b0; JumpReg=1'b0; ALUOp=ALU_ADD; is_muldiv=1'b0; is_div=1'b0;

        case (opcode)
            OP_RTYPE: begin
                RegDst = 2'd1;                 // مقصد = rd
                case (funct)
                    F_ADD: begin RegWrite=1'b1; ALUOp=ALU_ADD; end
                    F_SUB: begin RegWrite=1'b1; ALUOp=ALU_SUB; end
                    F_MUL: begin RegWrite=1'b1; is_muldiv=1'b1; is_div=1'b0; end
                    F_DIV: begin RegWrite=1'b1; is_muldiv=1'b1; is_div=1'b1; end
                    F_JR : begin JumpReg=1'b1;  end
                    default: ;
                endcase
            end
            OP_ADDI: begin RegWrite=1'b1; ALUSrc=1'b1; ALUOp=ALU_ADD; end
            OP_SUBI: begin RegWrite=1'b1; ALUSrc=1'b1; ALUOp=ALU_SUB; end
            OP_LUI : begin RegWrite=1'b1; ALUSrc=1'b1; ALUOp=ALU_LUI; end
            OP_LW: begin
                RegWrite=1'b1; ALUSrc=1'b1; ALUOp=ALU_ADD;
                MemRead=1'b1;  MemtoReg=2'd1;
            end
            OP_SW: begin
                ALUSrc=1'b1; ALUOp=ALU_ADD; MemWrite=1'b1;
            end
            OP_BEQ: begin
                ALUSrc=1'b0; ALUOp=ALU_SUB; Branch=1'b1;
            end
            OP_J:   begin Jump=1'b1; end
            OP_JAL: begin
                Jump=1'b1; Jal=1'b1;
                RegWrite=1'b1; RegDst=2'd2;
                MemtoReg=2'd2;
            end
            default: ;
        endcase
    end
endmodule
