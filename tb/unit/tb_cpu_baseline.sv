module tb_cpu_baseline;

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
                        6'b100000: write2reg(inst_rd, val_rs + val_rt);
                        6'b100010: write2reg(inst_rd, val_rs - val_rt);
                        6'b011000: write2reg(inst_rd, val_rs * val_rt);
                        6'b011010: write2reg(inst_rd, val_rs / val_rt);
                        6'b001000: ipc = val_rs >> 2;
                        default:   $display("Unknown R-type funct %b", inst_reg[5:0]);
                    endcase
                end

                6'b001000: write2reg(inst_rt, val_rs + inst_imm_sext);
                6'b001001: write2reg(inst_rt, val_rs - inst_imm_sext);
                6'b001111: write2reg(inst_rt, {inst_imm, 16'b0});

                6'b100011: begin
                    data_addr = val_rs + inst_imm_sext;
                    write2reg(inst_rt, data_mem[(data_addr>>2)&511]);
                end

                6'b101011: begin
                    data_addr = val_rs + inst_imm_sext;
                    data_mem[(data_addr>>2)&511] = val_rt;
                end

                6'b000100: begin
                    if (val_rs == val_rt) ipc = ipc + inst_imm_sext;
                end

                6'b000010: ipc = inst_reg[25:0];

                6'b000011: begin
                    write2reg(5'd31, ipc << 2);
                    ipc = inst_reg[25:0];
                end

                default: $display("Unknown opcode %b", inst_reg[31:26]);
            endcase
        end
    endtask

    wire m_data_req_valid;
    wire m_data_req_ready;
    wire m_data_req_write;
    wire [31:0] m_instr_addr;
    wire [31:0] m_data_req_addr;
    wire [31:0] m_data_req_wdata;
    reg [31:0] m_instr_in;
    reg m_data_rsp_valid;
    reg [31:0] m_data_rsp_rdata;
    wire m_data_rsp_error;

    always @(m_instr_addr) begin
        m_instr_in = instructions[m_instr_addr];
    end

    reg [31:0] output_store[10];

    assign m_data_req_ready = 1'b1;
    assign m_data_rsp_error = 1'b0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            m_data_rsp_valid <= 1'b0;
            m_data_rsp_rdata <= 32'b0;
        end else begin
            m_data_rsp_valid <= 1'b0;

            if (m_data_req_valid && m_data_req_ready) begin
                m_data_rsp_valid <= 1'b1;

                if (m_data_req_write) begin
                    m_data_rsp_rdata <= 32'b0;
                    case (m_data_req_addr)
                        32'h0001_0064: output_store[0] <= m_data_req_wdata;
                        32'h0001_0068: output_store[1] <= m_data_req_wdata;
                        32'h0001_006c: output_store[2] <= m_data_req_wdata;
                        32'h0001_0070: output_store[3] <= m_data_req_wdata;
                        32'h0001_0074: output_store[4] <= m_data_req_wdata;
                        32'h0001_0078: output_store[5] <= m_data_req_wdata;
                        32'h0001_007c: output_store[6] <= m_data_req_wdata;
                        32'h0001_0080: output_store[7] <= m_data_req_wdata;
                        32'h0001_0084: output_store[8] <= m_data_req_wdata;
                        32'h0001_0088: output_store[9] <= m_data_req_wdata;
                        default:
                            $display("WARNING: Invalid address to write : %x",
                                     m_data_req_addr);
                    endcase
                end else begin
                    case (m_data_req_addr)
                        32'h0001_0000: m_data_rsp_rdata <= 32'd10;
                        32'h0001_0004: m_data_rsp_rdata <= 32'd11;

                        32'h0001_0064: m_data_rsp_rdata <= output_store[0];
                        32'h0001_0068: m_data_rsp_rdata <= output_store[1];
                        32'h0001_006c: m_data_rsp_rdata <= output_store[2];
                        32'h0001_0070: m_data_rsp_rdata <= output_store[3];
                        32'h0001_0074: m_data_rsp_rdata <= output_store[4];
                        32'h0001_0078: m_data_rsp_rdata <= output_store[5];
                        32'h0001_007c: m_data_rsp_rdata <= output_store[6];
                        32'h0001_0080: m_data_rsp_rdata <= output_store[7];
                        32'h0001_0084: m_data_rsp_rdata <= output_store[8];
                        32'h0001_0088: m_data_rsp_rdata <= output_store[9];

                        default: begin
                            $display("WARNING: Invalid address to read : %x",
                                     m_data_req_addr);
                            m_data_rsp_rdata <= 32'b0;
                        end
                    endcase
                end
            end
        end
    end

    cpu_core dut (
        .Clk(clk),
        .Rst(rst),
        .InstrIn(m_instr_in),
        .InstrAddr(m_instr_addr),
        .data_req_valid(m_data_req_valid),
        .data_req_ready(m_data_req_ready),
        .data_req_addr(m_data_req_addr),
        .data_req_write(m_data_req_write),
        .data_req_wdata(m_data_req_wdata),
        .data_rsp_valid(m_data_rsp_valid),
        .data_rsp_rdata(m_data_rsp_rdata),
        .data_rsp_error(m_data_rsp_error),

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
        #1000000;
        $display("ERROR: timeout waiting for CPU baseline regression to complete");
        $display("FAIL: tb_cpu_baseline");
        $fatal(1, "tb_cpu_baseline timed out");
    end

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            instructions[i] = 32'b0;
            data_mem[i] = 32'b0;
        end

        for (i = 0; i < 32; i = i + 1) ireg[i] = 32'b0;

        ipc       = 0;
        fail_flag = 0;

        data_mem[0] = 10;
        data_mem[1] = 11;

        instructions[0]  = ITYPE(6'b001111, 5'd0, 5'd26, 16'd1);
        instructions[1]  = ITYPE(6'b100011, 5'd26, 5'd1, 16'd0);
        instructions[2]  = JTYPE(6'b000011, 26'd14);
        instructions[3]  = RTYPE(5'd2, 5'd0, 5'd20, 5'd0, 6'b100000);
        instructions[4]  = ITYPE(6'b100011, 5'd26, 5'd1, 16'd4);
        instructions[5]  = JTYPE(6'b000011, 26'd14);
        instructions[6]  = RTYPE(5'd2, 5'd0, 5'd21, 5'd0, 6'b100000);
        instructions[7]  = RTYPE(5'd20, 5'd21, 5'd22, 5'd0, 6'b011000);
        instructions[8]  = RTYPE(5'd22, 5'd0, 5'd1, 5'd0, 6'b100000);
        instructions[9]  = JTYPE(6'b000011, 26'd28);
        instructions[10] = JTYPE(6'b000010, 26'd41);

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

        last_instr = 42;
        rst = 1;

        #8 rst = 0;

        for (i = 0; ipc < last_instr && !fail_flag; i = i + 1) begin
            exec_internal();

            #2;
            while (m_instr_addr !== ipc) #2;

            for (j = 1; j < 32; j = j + 1) begin
                if (R[j] !== ireg[j]) begin
                    fail_flag = 1;
                    $display(
                        "ERROR: register %0d mismatch at step %0d: expected=%08x actual=%08x",
                        j, i, ireg[j], R[j]
                    );
                end
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
            if (output_store[0] !== 2) begin
                $display("ERROR: output_store[0] expected 2, got %0d", output_store[0]);
                fail_flag = 1;
            end
            if (output_store[1] !== 2) begin
                $display("ERROR: output_store[1] expected 2, got %0d", output_store[1]);
                fail_flag = 1;
            end
            if (output_store[2] !== 0) begin
                $display("ERROR: output_store[2] expected 0, got %0d", output_store[2]);
                fail_flag = 1;
            end
            if (output_store[3] !== 1) begin
                $display("ERROR: output_store[3] expected 1, got %0d", output_store[3]);
                fail_flag = 1;
            end
            if (output_store[4] !== 0) begin
                $display("ERROR: output_store[4] expected 0, got %0d", output_store[4]);
                fail_flag = 1;
            end
            if (output_store[5] !== 2) begin
                $display("ERROR: output_store[5] expected 2, got %0d", output_store[5]);
                fail_flag = 1;
            end
            if (output_store[6] !== 0) begin
                $display("ERROR: output_store[6] expected 0, got %0d", output_store[6]);
                fail_flag = 1;
            end
            if (output_store[7] !== 2) begin
                $display("ERROR: output_store[7] expected 2, got %0d", output_store[7]);
                fail_flag = 1;
            end
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

        if (!fail_flag) begin
            $display("PASS: tb_cpu_baseline");
            $finish;
        end else begin
            $display("FAIL: tb_cpu_baseline");
            $fatal(1, "CPU baseline regression failed");
        end
    end

endmodule
