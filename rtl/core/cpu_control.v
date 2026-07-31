module cpu_control (
    input      [5:0] opcode,
    input      [5:0] funct,
    output reg [1:0] RegDst,
    output reg       RegWrite,
    output reg       ALUSrc,
    output reg [1:0] MemtoReg,
    output reg       MemRead,
    output reg       MemWrite,
    output reg       Branch,
    output reg       Jump,
    output reg       Jal,
    output reg       JumpReg,
    output reg [1:0] ALUOp,
    output reg       is_muldiv,
    output reg       is_div,
    output reg       is_lr,
    output reg       is_sc,
    output reg       is_amoadd,
    output reg       is_cpuid
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam OP_RTYPE = 6'b000000;
    localparam OP_ADDI  = 6'b001000;
    localparam OP_SUBI  = 6'b001001;
    localparam OP_LUI   = 6'b001111;
    localparam OP_LW    = 6'b100011;
    localparam OP_SW    = 6'b101011;
    localparam OP_BEQ   = 6'b000100;
    localparam OP_J     = 6'b000010;
    localparam OP_JAL   = 6'b000011;
    
    localparam OP_CPUID = 6'b011111;
    localparam OP_AMO   = 6'b010111;

    localparam F_ADD = 6'b100000;
    localparam F_SUB = 6'b100010;
    localparam F_MUL = 6'b011000;
    localparam F_DIV = 6'b011010;
    localparam F_JR  = 6'b001000;
    
    localparam F_LR     = 6'b000010;
    localparam F_SC     = 6'b000011;
    localparam F_AMOADD = 6'b000000;

    localparam ALU_ADD = 2'b00;
    localparam ALU_SUB = 2'b01;
    localparam ALU_LUI = 2'b10;

    always @(*) begin
        RegDst=2'd0; RegWrite=1'b0; ALUSrc=1'b0; MemtoReg=2'd0;
        MemRead=1'b0; MemWrite=1'b0; Branch=1'b0; Jump=1'b0;
        Jal=1'b0; JumpReg=1'b0; ALUOp=ALU_ADD; is_muldiv=1'b0; is_div=1'b0;
        is_lr=1'b0; is_sc=1'b0; is_amoadd=1'b0; is_cpuid=1'b0;

        case (opcode)
            OP_RTYPE: begin
                RegDst = 2'd1;
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
            OP_CPUID: begin
                RegWrite=1'b1; RegDst=2'd1; is_cpuid=1'b1;
            end
            OP_AMO: begin
                RegDst = 2'd1;
                case (funct)
                    F_LR: begin 
                        RegWrite=1'b1; is_lr=1'b1; MemRead=1'b1; MemtoReg=2'd1;
                    end
                    F_SC: begin 
                        RegWrite=1'b1; is_sc=1'b1; MemWrite=1'b1;
                    end
                    F_AMOADD: begin 
                        RegWrite=1'b1; is_amoadd=1'b1; MemRead=1'b1; MemWrite=1'b1; MemtoReg=2'd1;
                    end
                    default: ;
                endcase
            end
            default: ;
        endcase
    end
endmodule