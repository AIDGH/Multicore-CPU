module tb;

    reg clk, rst, Jen;
    reg [31:0] instructions[512];
    reg [31:0] data_mem[512];

    wire InstDone;

    wire [31:0] R[32];
    assign R[0] = 0;

    reg [31:0] ireg[32];
    reg [31:0] inst_reg;
    reg [4:0] inst_rs, inst_rt, inst_rd;
    reg [15:0] inst_imm;
    reg [31:0] inst_imm_sext;
    reg [31:0] val_rs, val_rt;
    reg [31:0] data_addr;
    reg [ 8:0] ipc;

    integer i, j;
    integer fail_flag;
    integer last_instr;

    function [31:0] RTYPE;
        input [4:0] rs, rt, rd, shamt;
        input [5:0] funct;
        begin
            RTYPE = {6'b000000, rs, rt, rd, shamt, funct};
        end
    endfunction

    function [31:0] ITYPE;
        input [5:0] opcode;
        input [4:0] rs, rt;
        input [15:0] imm;
        begin
            ITYPE = {opcode, rs, rt, imm};
        end
    endfunction

    function [31:0] JTYPE;
        input [5:0] opcode;
        input [25:0] addr;
        begin
            JTYPE = {opcode, addr};
        end
    endfunction

    task write2reg;
        input [4:0] reg_dest;
        input [31:0] val;
        begin
            if (reg_dest != 0) ireg[reg_dest] = val;
        end
    endtask

    task exec_internal;
        begin
            inst_reg = instructions[ipc];
            ipc = ipc + 1;

            inst_rs = inst_reg[25:21];
            inst_rt = inst_reg[20:16];
            inst_rd = inst_reg[15:11];
            inst_imm = inst_reg[15:0];
            inst_imm_sext = {{16{inst_imm[15]}}, inst_imm};

            val_rs = ireg[inst_rs];
            val_rt = ireg[inst_rt];

            case (inst_reg[31:26])

                6'b000000: begin
                    case (inst_reg[5:0])
                        6'b100000: write2reg(inst_rd, val_rs + val_rt);  // ADD
                        6'b100010: write2reg(inst_rd, val_rs - val_rt);  // SUB
                        6'b011000: write2reg(inst_rd, val_rs * val_rt);  // MUL
                        6'b011010: write2reg(inst_rd, val_rs / val_rt);  // DIV
                        6'b001000: ipc = val_rs >> 2;  // JR
                        default:   $display("Unknown R-type funct %b", inst_reg[5:0]);
                    endcase
                end

                6'b001000: write2reg(inst_rt, val_rs + inst_imm_sext);  // ADDI
                6'b001001: write2reg(inst_rt, val_rs - inst_imm_sext);  // SUBI
                6'b001111: write2reg(inst_rt, {inst_imm, 16'b0});  // LUI

                6'b100011: begin  // LW
                    data_addr = val_rs + inst_imm_sext;
                    write2reg(inst_rt, data_mem[(data_addr>>2)&511]);
                end

                6'b101011: begin  // SW
                    data_addr = val_rs + inst_imm_sext;
                    data_mem[(data_addr>>2)&511] = val_rt;
                end

                6'b000100: begin  // BEQ
                    if (val_rs == val_rt) ipc = ipc + inst_imm_sext;
                end

                6'b000010: ipc = inst_reg[25:0];  // J

                6'b000011: begin  // JAL
                    write2reg(5'd31, ipc << 2);
                    ipc = inst_reg[25:0];
                end

                default: $display("Unknown opcode %b", inst_reg[31:26]);

            endcase
        end
    endtask

    wire mm_data_write, mm_data_read, mm_instr_read;
    wire [31:0] mm_instr_addr, mm_data_addr;
    wire [127:0] mm_data_out;
    reg [127:0] mm_instr_in, mm_data_in;
    reg mm_instr_done, mm_data_done;

    task rand_wait;
        reg [9:0] wait_time;
        begin
            wait_time = $random;
            #2;
            #(wait_time * 2);
        end
    endtask

    task fatal(input string msg);
        begin
            $display("FATAL : ", msg);
            $finish(0);
        end
    endtask

    always @(posedge clk)
        if (mm_instr_read) begin
            if (mm_instr_addr[3:0] !== 0)
                fatal("unaligned instr mm request.\n    hint: instrmm_addr[3:0] == 0");
            mm_instr_done <= 0;
            rand_wait();
            mm_instr_done <= 1;
            mm_instr_in <= {
                instructions[(mm_instr_addr>>2)+3],
                instructions[(mm_instr_addr>>2)+2],
                instructions[(mm_instr_addr>>2)+1],
                instructions[(mm_instr_addr>>2)+0]
            };
            #2;
        end
    reg [31:0] output_store[10];
    always @(posedge clk)
        if (mm_data_read) begin
            if (mm_data_addr[3:0] !== 0)
                fatal("unaligned data mm request.\n    hint: datamm_addr[3:0] == 0");
            mm_data_done <= 0;
            rand_wait();
            mm_data_done <= 1;
            case (mm_data_addr)
                'h00010000: mm_data_in <= {32'd0, 32'd0, 32'd11, 32'd10};

                'h00010060:
                mm_data_in <= {output_store[2], output_store[1], output_store[0], 32'd0};
                'h00010070:
                mm_data_in <= {output_store[6], output_store[5], output_store[4], output_store[3]};
                'h00010080:
                mm_data_in <= {32'd0, output_store[9], output_store[8], output_store[7]};

                default: begin
                    $display("WARNING: Invalid address to read : %x", mm_data_addr);
                    mm_data_in = 0;
                end
            endcase
            #2;
        end
    reg [31:0] tmp;
    always @(posedge clk)
        if (mm_data_write) begin
            if (mm_data_addr[3:0] !== 0)
                fatal("unaligned data mm request.\n    hint: datamm_addr[3:0] == 0");
            mm_data_done <= 0;
            rand_wait();
            mm_data_done <= 1;
            case (mm_data_addr)
                'h00010060: {output_store[2], output_store[1], output_store[0], tmp} <= mm_data_out;
                'h00010070:
                {output_store[6], output_store[5], output_store[4], output_store[3]} <= mm_data_out;
                'h00010080: {tmp, output_store[9], output_store[8], output_store[7]} <= mm_data_out;
                default: begin
                    $display("WARNING: Invalid address to write : %x", mm_data_addr);
                end
            endcase
            #2;
        end


    wire [31:0] mm_pc;
    main _main (
        .Clk(clk),
        .Rst(rst),
`ifndef LOGISIM
        .InstrMM_DataIn(mm_instr_in),
`else
        .InstrMM_DataIn0(mm_instr_in[63:0]),
        .InstrMM_DataIn1(mm_instr_in[127:64]),
`endif
        .PC(mm_pc),
        .InstrMM_Addr(mm_instr_addr),
        .InstrMM_Read(mm_instr_read),
        .InstrMM_Done(mm_instr_done),
`ifndef LOGISIM
        .DataMM_DataIn(mm_data_in),
        .DataMM_DataOut(mm_data_out),
`else
        .DataMM_DataIn0(mm_data_in[63:0]),
        .DataMM_DataIn1(mm_data_in[127:64]),
        .DataMM_DataOut0(mm_data_out[63:0]),
        .DataMM_DataOut1(mm_data_out[127:64]),
`endif
        .DataMM_Read(mm_data_read),
        .DataMM_Write(mm_data_write),
        .DataMM_Addr(mm_data_addr),
        .DataMM_Done(mm_data_done),

        .R0 (R[0]),
        .R1 (R[1]),
        .R2 (R[2]),
        .R3 (R[3]),
        .R4 (R[4]),
        .R5 (R[5]),
        .R6 (R[6]),
        .R7 (R[7]),
        .R8 (R[8]),
        .R9 (R[9]),
        .R10(R[10]),
        .R11(R[11]),
        .R12(R[12]),
        .R13(R[13]),
        .R14(R[14]),
        .R15(R[15]),
        .R16(R[16]),
        .R17(R[17]),
        .R18(R[18]),
        .R19(R[19]),
        .R20(R[20]),
        .R21(R[21]),
        .R22(R[22]),
        .R23(R[23]),
        .R24(R[24]),
        .R25(R[25]),
        .R26(R[26]),
        .R27(R[27]),
        .R28(R[28]),
        .R29(R[29]),
        .R30(R[30]),
        .R31(R[31])
    );

    initial begin
        clk = 0;
        forever #1 clk = ~clk;
    end

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            instructions[i] = 32'b0;
            data_mem[i] = 32'b0;
        end

        for (i = 0; i < 32; i = i + 1) ireg[i] = 32'b0;

        ipc              = 0;
        fail_flag        = 0;

        data_mem[0]      = 10;
        data_mem[1]      = 11;

        instructions[0]  = ITYPE(6'b001111, 5'd0, 5'd26, 16'd1);  // LUI $26,1
        instructions[1]  = ITYPE(6'b100011, 5'd26, 5'd1, 16'd0);  // LW $1,0($26)
        instructions[2]  = JTYPE(6'b000011, 26'd14);  // JAL fib
        instructions[3]  = RTYPE(5'd2, 5'd0, 5'd20, 5'd0, 6'b100000);  // ADD $20,$2,$0
        instructions[4]  = ITYPE(6'b100011, 5'd26, 5'd1, 16'd4);  // LW $1,4($26)
        instructions[5]  = JTYPE(6'b000011, 26'd14);  // JAL fib
        instructions[6]  = RTYPE(5'd2, 5'd0, 5'd21, 5'd0, 6'b100000);  // ADD $21,$2,$0
        instructions[7]  = RTYPE(5'd20, 5'd21, 5'd22, 5'd0, 6'b011000);  // MUL
        instructions[8]  = RTYPE(5'd22, 5'd0, 5'd1, 5'd0, 6'b100000);  // ADD $1,$22,$0
        instructions[9]  = JTYPE(6'b000011, 26'd28);  // JAL to_base3
        instructions[10] = JTYPE(6'b000010, 26'd41);  // J finish

        instructions[14] = ITYPE(6'b000100, 5'd1, 5'd0, 16'd11);
        instructions[15] = ITYPE(6'b001000, 5'd0, 5'd3, 16'd0);
        instructions[16] = ITYPE(6'b001000, 5'd0, 5'd4, 16'd1);
        instructions[17] = ITYPE(6'b001000, 5'd0, 5'd5, 16'd1);
        instructions[18] = ITYPE(6'b000100, 5'd5, 5'd1, 16'd5);
        instructions[19] = RTYPE(5'd3, 5'd4, 5'd6, 5'd0, 6'b100000);
        instructions[20] = RTYPE(5'd4, 5'd0, 5'd3, 5'd0, 6'b100000);
        instructions[21] = RTYPE(5'd6, 5'd0, 5'd4, 5'd0, 6'b100000);
        instructions[22] = ITYPE(6'b001000, 5'd5, 5'd5, 16'd1);
        instructions[23] = JTYPE(6'b000010, 26'd18);
        instructions[24] = RTYPE(5'd4, 5'd0, 5'd2, 5'd0, 6'b100000);
        instructions[25] = RTYPE(5'd31, 5'd0, 5'd0, 5'd0, 6'b001000);
        instructions[26] = ITYPE(6'b001000, 5'd0, 5'd2, 16'd0);
        instructions[27] = RTYPE(5'd31, 5'd0, 5'd0, 5'd0, 6'b001000);

        instructions[28] = ITYPE(6'b001000, 5'd26, 5'd10, 16'd100);
        instructions[29] = ITYPE(6'b001000, 5'd0, 5'd11, 16'd3);
        instructions[30] = ITYPE(6'b000100, 5'd1, 5'd0, 16'd9);
        instructions[31] = RTYPE(5'd1, 5'd11, 5'd12, 5'd0, 6'b011010);
        instructions[32] = RTYPE(5'd12, 5'd11, 5'd13, 5'd0, 6'b011000);
        instructions[33] = RTYPE(5'd1, 5'd13, 5'd14, 5'd0, 6'b100010);
        instructions[34] = ITYPE(6'b101011, 5'd10, 5'd14, 16'd0);
        instructions[35] = ITYPE(6'b001000, 5'd10, 5'd10, 16'd4);
        instructions[36] = RTYPE(5'd12, 5'd0, 5'd1, 5'd0, 6'b100000);
        instructions[37] = JTYPE(6'b000010, 26'd30);
        instructions[40] = RTYPE(5'd31, 5'd0, 5'd0, 5'd0, 6'b001000);

        instructions[41] = ITYPE(6'b001000, 5'd0, 5'd30, 16'd123);

        last_instr       = 42;

        rst              = 1;

        #8 rst = 0;

        for (i = 0; ipc < last_instr && !fail_flag; i = i + 1) begin
            exec_internal();

            #2;
            while (mm_pc !== ipc) #2;

            for (j = 1; j < 32; j = j + 1) begin
                if (R[j] !== ireg[j]) fail_flag = 1;
            end

            if (fail_flag) begin
                $display("FAILED at step %0d", i);
                $display("Expected:");
                $display("R20=%d R21=%d R22=%d R23=%d R24=%d R30=%d R31=%d", ireg[20], ireg[21],
                         ireg[22], ireg[23], ireg[24], ireg[30], ireg[31]);

                $display("Reality:");
                $display("R20=%d R21=%d R22=%d R23=%d R24=%d R30=%d R31=%d", R[20], R[21], R[22],
                         R[23], R[24], R[30], R[31]);
            end
        end

        if (!fail_flag) begin
            if (output_store[0] !== 2) fail_flag = 1;
            if (output_store[1] !== 2) fail_flag = 1;
            if (output_store[2] !== 0) fail_flag = 1;
            if (output_store[3] !== 1) fail_flag = 1;
            if (output_store[4] !== 0) fail_flag = 1;
            if (output_store[5] !== 2) fail_flag = 1;
            if (output_store[6] !== 0) fail_flag = 1;
            if (output_store[7] !== 2) fail_flag = 1;
        end

        $display("fib(10) = exp: %0d  real: %0d", ireg[20], R[20]);
        $display("fib(11) = exp: %0d  real: %0d", ireg[21], R[21]);
        $display("product = exp: %0d  real: %0d", ireg[22], R[22]);
        $display("base3 digits LSD first:");
        $display("%0d %0d %0d %0d %0d %0d %0d %0d", output_store[0], output_store[1],
                 output_store[2], output_store[3], output_store[4], output_store[5],
                 output_store[6], output_store[7]);
        $display("base3 = 20201022");

        if (!fail_flag) begin
            $display("ACCEPTED");
        end else begin
            $display("FAILED");
        end
        $display(i, " / ", 208);

        $finish;
    end

endmodule
