module cpu_core (
    input              Clk,
    input              Rst,
    input              core_id,
    input              cancel_reservation,
    input      [31:0]  InstrIn,
    output     [31:0]  InstrAddr,
    output             data_req_valid,
    input              data_req_ready,
    output     [31:0]  data_req_addr,
    output             data_req_write,
    output     [2:0]   data_req_op,
    output     [31:0]  data_req_wdata,
    input              data_rsp_valid,
    input      [31:0]  data_rsp_rdata,
    input              data_rsp_error,
    output     [31:0]  R0,  R1,  R2,  R3,  R4,  R5,  R6,  R7,
    output     [31:0]  R8,  R9,  R10, R11, R12, R13, R14, R15,
    output     [31:0]  R16, R17, R18, R19, R20, R21, R22, R23,
    output     [31:0]  R24, R25, R26, R27, R28, R29, R30, R31
);
    timeunit 1ns;
    timeprecision 1ps;

    reg  [31:0] PC;
    wire [31:0] pc_plus_4 = PC + 32'd4;

    wire [5:0]  opcode = InstrIn[31:26];
    wire [4:0]  rs     = InstrIn[25:21];
    wire [4:0]  rt     = InstrIn[20:16];
    wire [4:0]  rd     = InstrIn[15:11];
    wire [5:0]  funct  = InstrIn[5:0];
    wire [15:0] imm    = InstrIn[15:0];
    wire [25:0] addr26 = InstrIn[25:0];
    wire [31:0] imm_sext = {{16{imm[15]}}, imm};

    wire [1:0] RegDst, MemtoReg, ALUOp;
    wire       RegWrite, ALUSrc, MemRead, MemWrite;
    wire       Branch, Jump, Jal, JumpReg, is_muldiv, is_div;
    wire       is_lr, is_sc, is_amoadd, is_cpuid, is_bne;

    cpu_control u_ctrl (
        .opcode(opcode), .funct(funct),
        .RegDst(RegDst), .RegWrite(RegWrite), .ALUSrc(ALUSrc),
        .MemtoReg(MemtoReg), .MemRead(MemRead), .MemWrite(MemWrite),
        .Branch(Branch), .Jump(Jump), .Jal(Jal), .JumpReg(JumpReg),
        .ALUOp(ALUOp), .is_muldiv(is_muldiv), .is_div(is_div),
        .is_lr(is_lr), .is_sc(is_sc), .is_amoadd(is_amoadd), .is_cpuid(is_cpuid), .is_bne(is_bne)
    );

    wire [31:0] md_result;
    wire        md_busy, md_done;
    wire        md_start = is_muldiv & ~md_busy & ~md_done;
    wire        md_stall = is_muldiv & ~md_done;

    localparam [1:0]
        MEM_IDLE          = 2'd0,
        MEM_WAIT_ACCEPT   = 2'd1,
        MEM_WAIT_RESPONSE = 2'd2,
        MEM_ERROR_HALT    = 2'd3;

    localparam [2:0]
        MC_MEM_LOAD   = 3'd0,
        MC_MEM_STORE  = 3'd1,
        MC_MEM_LR     = 3'd2,
        MC_MEM_SC     = 3'd3,
        MC_MEM_AMOADD = 3'd4;

    reg [1:0]  mem_state;
    reg [31:0] mem_req_addr;
    reg        mem_req_write;
    reg [2:0]  mem_req_op_reg;
    reg [31:0] mem_req_wdata;
    reg        mem_req_is_load;
    reg        mem_req_is_sc;
    reg [4:0]  mem_load_dest;

    reg [31:0] reserve_addr;
    reg        reserve_valid;

    wire [31:0] rs_val, rt_val;
    
    wire [31:0] alu_b = ALUSrc ? imm_sext : rt_val;
    wire [31:0] alu_y;
    wire        zero;

    cpu_alu u_alu (
        .a(rs_val), .b(alu_b), .op(ALUOp), .y(alu_y), .zero(zero)
    );

    wire [31:0] mem_target_addr = (is_lr | is_sc | is_amoadd) ? rs_val : alu_y;
    wire sc_success = reserve_valid & (reserve_addr == rs_val);
    wire sc_fail_local = is_sc & ~sc_success;

    wire memory_instruction = (MemRead | MemWrite) & ~sc_fail_local;
    wire memory_wait = (mem_state != MEM_IDLE) |
                       ((mem_state == MEM_IDLE) & memory_instruction);
    wire memory_response_received =
        (mem_state == MEM_WAIT_RESPONSE) & data_rsp_valid;
    wire memory_response_complete =
        memory_response_received & ~data_rsp_error;
    wire load_response_success =
        memory_response_complete & mem_req_is_load;
    wire sc_response_success = 
        memory_response_complete & mem_req_is_sc;

    wire final_sc_success = sc_response_success & (data_rsp_rdata == 32'd0);

    wire [31:0] regs_o [0:31];
    wire [4:0]  normal_write_reg = (RegDst == 2'd1) ? rd :
                                   (RegDst == 2'd2) ? 5'd31 : rt;
    wire [4:0]  write_reg = (load_response_success | sc_response_success) ? mem_load_dest
                                                  : normal_write_reg;
    
    wire [31:0] normal_write_data;
    wire [31:0] write_data = is_cpuid ? {31'b0, core_id} :
                             (is_sc && sc_fail_local && mem_state == MEM_IDLE) ? 32'd1 :
                             sc_response_success ? (final_sc_success ? 32'd0 : 32'd1) :
                             load_response_success ? data_rsp_rdata
                                                   : normal_write_data;

    wire normal_reg_we = (mem_state == MEM_IDLE) &
                         ~memory_instruction &
                         RegWrite &
                         ~md_stall;
                         
    wire reg_we = normal_reg_we | load_response_success | sc_response_success;

    cpu_reg_file u_rf (
        .clk(Clk), .rst(Rst), .we(reg_we),
        .ra1(rs), .ra2(rt), .wa(write_reg), .wd(write_data),
        .rd1(rs_val), .rd2(rt_val), .r_out(regs_o)
    );

    assign data_req_valid = ~Rst &
                            (((mem_state == MEM_IDLE) & memory_instruction) |
                             (mem_state == MEM_WAIT_ACCEPT));
    assign data_req_addr  = (mem_state == MEM_IDLE) ? mem_target_addr
                                                    : mem_req_addr;
    assign data_req_write = (mem_state == MEM_IDLE) ? MemWrite
                                                    : mem_req_write;
    assign data_req_op    = (mem_state == MEM_IDLE) ? (is_lr ? MC_MEM_LR : is_sc ? MC_MEM_SC : is_amoadd ? MC_MEM_AMOADD : MemRead ? MC_MEM_LOAD : MC_MEM_STORE)
                                                    : mem_req_op_reg;
    assign data_req_wdata = (mem_state == MEM_IDLE) ? rt_val
                                                    : mem_req_wdata;

    cpu_mul_div u_md (
        .clk(Clk), .rst(Rst), .start(md_start), .is_div(is_div),
        .a(rs_val), .b(rt_val),
        .result(md_result), .busy(md_busy), .done(md_done)
    );

    wire [31:0] compute_result = is_muldiv ? md_result : alu_y;

    assign normal_write_data = (MemtoReg == 2'd2) ? pc_plus_4
                                                   : compute_result;

    assign InstrAddr = PC >> 2;

    wire branch_taken = Branch & (is_bne ? ~zero : zero);
    wire [31:0] branch_target = pc_plus_4 + (imm_sext << 2);
    wire [31:0] jump_target   = {PC[31:28], addr26, 2'b00};
    wire [31:0] next_pc = JumpReg      ? rs_val        :
                          Jump         ? jump_target   :
                          branch_taken ? branch_target :
                                         pc_plus_4;

    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            mem_state       <= MEM_IDLE;
            mem_req_addr    <= 32'b0;
            mem_req_write   <= 1'b0;
            mem_req_wdata   <= 32'b0;
            mem_req_op_reg  <= 3'b0;
            mem_req_is_load <= 1'b0;
            mem_req_is_sc   <= 1'b0;
            mem_load_dest   <= 5'b0;
        end else begin
            case (mem_state)
                MEM_IDLE: begin
                    if (memory_instruction) begin
                        mem_req_addr    <= mem_target_addr;
                        mem_req_write   <= MemWrite;
                        mem_req_wdata   <= rt_val;
                        mem_req_op_reg  <= is_lr ? MC_MEM_LR : is_sc ? MC_MEM_SC : is_amoadd ? MC_MEM_AMOADD : MemRead ? MC_MEM_LOAD : MC_MEM_STORE;
                        mem_req_is_load <= MemRead;
                        mem_req_is_sc   <= is_sc;
                        mem_load_dest   <= (is_lr | is_sc | is_amoadd) ? rd : rt;

                        if (data_req_ready)
                            mem_state <= MEM_WAIT_RESPONSE;
                        else
                            mem_state <= MEM_WAIT_ACCEPT;
                    end
                end

                MEM_WAIT_ACCEPT: begin
                    if (data_req_ready)
                        mem_state <= MEM_WAIT_RESPONSE;
                end

                MEM_WAIT_RESPONSE: begin
                    if (data_rsp_valid) begin
                        if (data_rsp_error)
                            mem_state <= MEM_ERROR_HALT;
                        else
                            mem_state <= MEM_IDLE;
                    end
                end

                MEM_ERROR_HALT: mem_state <= MEM_ERROR_HALT;

                default: mem_state <= MEM_IDLE;
            endcase
        end
    end

    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            reserve_valid <= 1'b0;
            reserve_addr <= 32'b0;
        end else if (cancel_reservation) begin
            reserve_valid <= 1'b0;
        end else if ((mem_state == MEM_IDLE) && memory_instruction && !is_sc) begin
            // Any intervening local memory operation may discard the LR reservation.
            reserve_valid <= 1'b0;
        end else if (load_response_success && mem_req_op_reg == MC_MEM_LR) begin
            reserve_valid <= 1'b1;
            reserve_addr <= mem_req_addr;
        end else if (sc_response_success || (is_sc && sc_fail_local && mem_state == MEM_IDLE)) begin
            reserve_valid <= 1'b0;
        end
    end

    always @(posedge Clk or posedge Rst) begin
        if (Rst)
            PC <= 32'b0;
        else if (memory_response_complete)
            PC <= pc_plus_4;
        else if (!md_stall && !memory_wait)
            PC <= next_pc;
    end

    assign R0=regs_o[0];   assign R1=regs_o[1];   assign R2=regs_o[2];   assign R3=regs_o[3];
    assign R4=regs_o[4];   assign R5=regs_o[5];   assign R6=regs_o[6];   assign R7=regs_o[7];
    assign R8=regs_o[8];   assign R9=regs_o[9];   assign R10=regs_o[10]; assign R11=regs_o[11];
    assign R12=regs_o[12]; assign R13=regs_o[13]; assign R14=regs_o[14]; assign R15=regs_o[15];
    assign R16=regs_o[16]; assign R17=regs_o[17]; assign R18=regs_o[18]; assign R19=regs_o[19];
    assign R20=regs_o[20]; assign R21=regs_o[21]; assign R22=regs_o[22]; assign R23=regs_o[23];
    assign R24=regs_o[24]; assign R25=regs_o[25]; assign R26=regs_o[26]; assign R27=regs_o[27];
    assign R28=regs_o[28]; assign R29=regs_o[29]; assign R30=regs_o[30]; assign R31=regs_o[31];
endmodule