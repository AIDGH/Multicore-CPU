import mc_defs_pkg::*;

module tb_cpu_atomic_unit;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic core_id;
    logic cancel_reservation;

    logic [31:0] instructions [0:15];
    logic [31:0] instr_in;
    wire  [31:0] instr_addr;

    wire         data_req_valid;
    wire         data_req_ready;
    wire [31:0]  data_req_addr;
    wire         data_req_write;
    wire [2:0]   data_req_op;
    wire [31:0]  data_req_wdata;
    wire         data_rsp_valid;
    wire [31:0]  data_rsp_rdata;
    wire         data_rsp_error;

    mc_mem_op_t        l1_request_op;
    mc_resp_status_t   l1_response_status;
    logic [7:0]        l1_cfg_accept_delay;
    logic [7:0]        l1_cfg_completion_delay;
    logic [31:0]       l1_cfg_response_data;
    logic              l1_cfg_sc_success;
    logic              l1_accepted;
    logic              l1_response_issued;

    wire [31:0] R [0:31];

    integer error_count;

    function automatic [31:0] ITYPE;
        input [5:0] opcode;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            ITYPE = {opcode, rs, rt, imm};
        end
    endfunction

    function automatic [31:0] JTYPE;
        input [5:0] opcode;
        input [25:0] address;
        begin
            JTYPE = {opcode, address};
        end
    endfunction

    function automatic [31:0] ATYPE;
        input [5:0] opcode;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [5:0] funct;
        begin
            ATYPE = {opcode, rs, rt, rd, 5'b0, funct};
        end
    endfunction

    task automatic check_condition;
        input logic condition;
        input string message;
        begin
            if (!condition) begin
                error_count = error_count + 1;
                $display("ERROR: %s", message);
            end
        end
    endtask

    assign instr_in = instructions[instr_addr[3:0]];

    assign l1_request_op = mc_mem_op_t'(data_req_op);

    assign data_rsp_error = data_rsp_valid &&
                            (l1_response_status != MC_RESP_OK) &&
                            (l1_response_status != MC_RESP_SC_SUCCESS) &&
                            (l1_response_status != MC_RESP_SC_FAILURE);

    cpu_core dut (
        .Clk(clk),
        .Rst(rst),
        .core_id(core_id),
        .cancel_reservation(cancel_reservation),
        .InstrIn(instr_in),
        .InstrAddr(instr_addr),
        .data_req_valid(data_req_valid),
        .data_req_ready(data_req_ready),
        .data_req_addr(data_req_addr),
        .data_req_write(data_req_write),
        .data_req_op(data_req_op),
        .data_req_wdata(data_req_wdata),
        .data_rsp_valid(data_rsp_valid),
        .data_rsp_rdata(data_rsp_rdata),
        .data_rsp_error(data_rsp_error),
        .R0 (R[0]), .R1 (R[1]), .R2 (R[2]), .R3 (R[3]),
        .R4 (R[4]), .R5 (R[5]), .R6 (R[6]), .R7 (R[7]),
        .R8 (R[8]), .R9 (R[9]), .R10(R[10]), .R11(R[11]),
        .R12(R[12]), .R13(R[13]), .R14(R[14]), .R15(R[15]),
        .R16(R[16]), .R17(R[17]), .R18(R[18]), .R19(R[19]),
        .R20(R[20]), .R21(R[21]), .R22(R[22]), .R23(R[23]),
        .R24(R[24]), .R25(R[25]), .R26(R[26]), .R27(R[27]),
        .R28(R[28]), .R29(R[29]), .R30(R[30]), .R31(R[31])
    );

    mock_l1 l1 (
        .clk(clk),
        .rst(rst),
        .cfg_accept_delay(l1_cfg_accept_delay),
        .cfg_completion_delay(l1_cfg_completion_delay),
        .cfg_response_data(l1_cfg_response_data),
        .cfg_sc_success(l1_cfg_sc_success),
        .request_valid(data_req_valid),
        .request_ready(data_req_ready),
        .request_address(data_req_addr),
        .request_op(l1_request_op),
        .request_write_data(data_req_wdata),
        .response_valid(data_rsp_valid),
        .response_read_data(data_rsp_rdata),
        .response_status(l1_response_status),
        .accepted(l1_accepted),
        .response_issued(l1_response_issued)
    );

    always begin
        #5 clk = ~clk;
    end

    initial begin
        #200000;
        $display("ERROR: timeout waiting for CPU atomic regression");
        $display("FAIL: tb_cpu_atomic_unit");
        $fatal(1, "tb_cpu_atomic_unit timed out");
    end

    initial begin : run_test
        integer index;

        clk = 1'b0;
        rst = 1'b1;
        core_id = 1'b1;
        cancel_reservation = 1'b0;
        error_count = 0;

        l1_cfg_accept_delay     = 8'd1;
        l1_cfg_completion_delay = 8'd2;
        l1_cfg_response_data    = 32'h0000_0000;
        l1_cfg_sc_success       = 1'b1;

        for (index = 0; index < 16; index = index + 1)
            instructions[index] = 32'b0;

        instructions[0] = {6'b011111, 5'd0, 5'd0, 5'd1, 11'd0};
        instructions[1] = ITYPE(6'b001000, 5'd0, 5'd2, 16'h0100);
        instructions[2] = ITYPE(6'b001000, 5'd0, 5'd5, 16'h1234);
        instructions[3] = ATYPE(6'b010111, 5'd2, 5'd0, 5'd3, 6'b000010);
        instructions[4] = ATYPE(6'b010111, 5'd2, 5'd5, 5'd4, 6'b000011);
        instructions[5] = ITYPE(6'b001000, 5'd0, 5'd7, 16'h0001);
        instructions[6] = ATYPE(6'b010111, 5'd2, 5'd7, 5'd6, 6'b000000);
        instructions[7] = ATYPE(6'b010111, 5'd2, 5'd0, 5'd8, 6'b000010);
        instructions[8] = ITYPE(6'b001000, 5'd0, 5'd0, 16'd0);
        instructions[9] = ATYPE(6'b010111, 5'd2, 5'd5, 5'd9, 6'b000011);
        instructions[10]= JTYPE(6'b000010, 26'd11);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (instr_addr != 32'd1) @(negedge clk);
        check_condition(R[1] == 32'd1, "CPUID failed");

        while (instr_addr != 32'd3) @(negedge clk);

        while (!data_req_valid) @(negedge clk);
        check_condition(data_req_op == 3'd2, "LR.W operation code incorrect");
        l1_cfg_response_data = 32'hAAAA_BBBB;

        while (instr_addr != 32'd4) @(negedge clk);
        check_condition(R[3] == 32'hAAAA_BBBB, "LR.W failed to load data");

        while (!data_req_valid) @(negedge clk);
        check_condition(data_req_op == 3'd3, "SC.W operation code incorrect");

        while (instr_addr != 32'd5) @(negedge clk);
        check_condition(R[4] == 32'd0, "SC.W did not return success (0)");

        while (instr_addr != 32'd6) @(negedge clk);

        while (!data_req_valid) @(negedge clk);
        check_condition(data_req_op == 3'd4, "AMOADD.W operation code incorrect");
        l1_cfg_response_data = 32'hCCCC_DDDD;

        while (instr_addr != 32'd7) @(negedge clk);
        check_condition(R[6] == 32'hCCCC_DDDD, "AMOADD.W failed to load previous data");

        while (!data_req_valid) @(negedge clk);
        l1_cfg_response_data = 32'h1111_2222;

        while (instr_addr != 32'd8) @(negedge clk);

        cancel_reservation = 1'b1;
        @(negedge clk);
        cancel_reservation = 1'b0;

        while (instr_addr != 32'd9) @(negedge clk);

        while (instr_addr != 32'd10) @(negedge clk);

        check_condition(R[9] == 32'd1, "SC.W did not return failure (1) after cancel_reservation");

        if (error_count == 0) begin
            $display("PASS: tb_cpu_atomic_unit");
            $finish;
        end else begin
            $display("FAIL: tb_cpu_atomic_unit");
            $fatal(1, "CPU atomic regression failed");
        end
    end
endmodule