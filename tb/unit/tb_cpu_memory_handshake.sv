import mc_defs_pkg::*;

module tb_cpu_memory_handshake;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;

    logic [31:0] instructions [0:15];
    logic [31:0] instr_in;
    wire  [31:0] instr_addr;

    wire         data_req_valid;
    wire         data_req_ready;
    wire [31:0]  data_req_addr;
    wire         data_req_write;
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
    integer cycle_count;
    integer acceptance_count;
    integer response_count;
    integer store_acceptance_count;
    integer r2_change_count;
    integer r3_change_count;
    logic [31:0] previous_r2;
    logic [31:0] previous_r3;

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

    always @* begin
        instr_in = instructions[instr_addr[3:0]];

        if (data_req_write)
            l1_request_op = MC_MEM_STORE;
        else
            l1_request_op = MC_MEM_LOAD;
    end

    assign data_rsp_error =
        data_rsp_valid && (l1_response_status != MC_RESP_OK);

    cpu_core dut (
        .Clk(clk),
        .Rst(rst),
        .InstrIn(instr_in),
        .InstrAddr(instr_addr),
        .data_req_valid(data_req_valid),
        .data_req_ready(data_req_ready),
        .data_req_addr(data_req_addr),
        .data_req_write(data_req_write),
        .data_req_wdata(data_req_wdata),
        .data_rsp_valid(data_rsp_valid),
        .data_rsp_rdata(data_rsp_rdata),
        .data_rsp_error(data_rsp_error),
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

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count            <= 0;
            acceptance_count       <= 0;
            response_count         <= 0;
            store_acceptance_count <= 0;
            r2_change_count        <= 0;
            r3_change_count        <= 0;
            previous_r2            <= 32'b0;
            previous_r3            <= 32'b0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (data_req_valid && data_req_ready) begin
                acceptance_count <= acceptance_count + 1;
                if (data_req_write)
                    store_acceptance_count <= store_acceptance_count + 1;
            end

            if (data_rsp_valid)
                response_count <= response_count + 1;

            if (R[2] !== previous_r2)
                r2_change_count <= r2_change_count + 1;

            if (R[3] !== previous_r3)
                r3_change_count <= r3_change_count + 1;

            previous_r2 <= R[2];
            previous_r3 <= R[3];
        end
    end

    initial begin
        #200000;
        $display("ERROR: timeout waiting for CPU memory handshake regression");
        $display("FAIL: tb_cpu_memory_handshake");
        $fatal(1, "tb_cpu_memory_handshake timed out");
    end

    initial begin : run_test
        integer index;
        logic [31:0] held_addr;
        logic held_write;
        logic [31:0] held_wdata;
        logic [31:0] store_registers [0:31];
        logic saw_backpressure;
        logic saw_completion_wait;

        clk = 1'b0;
        rst = 1'b1;
        error_count = 0;

        l1_cfg_accept_delay     = 8'd3;
        l1_cfg_completion_delay = 8'd4;
        l1_cfg_response_data    = 32'h1122_3344;
        l1_cfg_sc_success       = 1'b0;

        for (index = 0; index < 16; index = index + 1)
            instructions[index] = 32'b0;

        instructions[0] = ITYPE(6'b001111, 5'd0, 5'd1, 16'd1);
        instructions[1] = ITYPE(6'b100011, 5'd1, 5'd2, 16'd0);
        instructions[2] = ITYPE(6'b101011, 5'd1, 5'd2, 16'd4);
        instructions[3] = ITYPE(6'b100011, 5'd1, 5'd3, 16'd8);
        instructions[4] = ITYPE(6'b001000, 5'd3, 5'd4, 16'd1);
        instructions[5] = JTYPE(6'b000010, 26'd5);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // First load: delayed acceptance and delayed completion.
        while (!(instr_addr == 32'd1 && data_req_valid))
            @(negedge clk);

        held_addr = data_req_addr;
        held_write = data_req_write;
        held_wdata = data_req_wdata;
        saw_backpressure = 1'b0;

        check_condition(held_addr == 32'h0001_0000,
                        "first load did not issue the canonical byte address");
        check_condition(!held_write, "first load was marked as a write");
        check_condition(R[2] == 32'b0,
                        "load destination changed before request acceptance");

        while (!l1_accepted) begin
            @(negedge clk);
            if (!l1_accepted) begin
                check_condition(instr_addr == 32'd1,
                                "PC advanced while load waited for acceptance");
                check_condition(data_req_valid,
                                "load request_valid dropped before acceptance");
                check_condition(data_req_addr == held_addr,
                                "load address changed before acceptance");
                check_condition(data_req_write == held_write,
                                "load write control changed before acceptance");
                check_condition(data_req_wdata == held_wdata,
                                "load write-data field changed before acceptance");
                check_condition(R[2] == 32'b0,
                                "load destination changed before response");
                if (!data_req_ready)
                    saw_backpressure = 1'b1;
            end
        end

        check_condition(saw_backpressure,
                        "first load did not observe delayed acceptance");
        check_condition(acceptance_count == 1,
                        "first load was not accepted exactly once");
        check_condition(instr_addr == 32'd1,
                        "PC advanced on request acceptance");
        check_condition(!data_req_valid,
                        "request remained valid after acceptance");

        saw_completion_wait = 1'b0;
        while (!l1_response_issued) begin
            @(negedge clk);
            if (!l1_response_issued) begin
                saw_completion_wait = 1'b1;
                check_condition(instr_addr == 32'd1,
                                "PC advanced before delayed load response");
                check_condition(!data_req_valid,
                                "load request was reissued while awaiting response");
                check_condition(R[2] == 32'b0,
                                "load destination changed before response");
            end
        end

        check_condition(saw_completion_wait,
                        "first load did not observe delayed response completion");
        check_condition(data_rsp_valid,
                        "load response_issued did not coincide with response_valid");
        check_condition(instr_addr == 32'd1,
                        "PC advanced before consuming the load response");
        check_condition(R[2] == 32'b0,
                        "load destination changed before consuming the response");

        // Configure the immediately following store before the load retires.
        l1_cfg_accept_delay     = 8'd2;
        l1_cfg_completion_delay = 8'd3;
        l1_cfg_response_data    = 32'b0;

        while (instr_addr != 32'd2)
            @(negedge clk);

        check_condition(R[2] == 32'h1122_3344,
                        "load response data was not written to its destination");
        check_condition(response_count == 1,
                        "first load did not produce exactly one response");

        for (index = 0; index < 32; index = index + 1)
            store_registers[index] = R[index];

        while (!data_req_valid)
            @(negedge clk);

        held_addr = data_req_addr;
        held_write = data_req_write;
        held_wdata = data_req_wdata;
        saw_backpressure = 1'b0;

        check_condition(held_addr == 32'h0001_0004,
                        "store did not issue the canonical byte address");
        check_condition(held_write, "store was not marked as a write");
        check_condition(held_wdata == 32'h1122_3344,
                        "store write data did not match the loaded value");

        while (!l1_accepted) begin
            @(negedge clk);
            if (!l1_accepted) begin
                check_condition(instr_addr == 32'd2,
                                "PC advanced while store waited for acceptance");
                check_condition(data_req_valid,
                                "store request_valid dropped before acceptance");
                check_condition(data_req_addr == held_addr,
                                "store address changed before acceptance");
                check_condition(data_req_write == held_write,
                                "store write control changed before acceptance");
                check_condition(data_req_wdata == held_wdata,
                                "store write data changed before acceptance");
                for (index = 0; index < 32; index = index + 1)
                    check_condition(R[index] === store_registers[index],
                                    "register changed while store awaited acceptance");
                if (!data_req_ready)
                    saw_backpressure = 1'b1;
            end
        end

        check_condition(saw_backpressure,
                        "store did not observe delayed acceptance");
        check_condition(acceptance_count == 2,
                        "store was not the second accepted request");
        check_condition(store_acceptance_count == 1,
                        "store was not accepted exactly once");
        check_condition(r2_change_count == 1,
                        "first load destination was not updated exactly once");

        saw_completion_wait = 1'b0;
        while (!l1_response_issued) begin
            @(negedge clk);
            if (!l1_response_issued) begin
                saw_completion_wait = 1'b1;
                check_condition(instr_addr == 32'd2,
                                "PC advanced before store completion");
                check_condition(!data_req_valid,
                                "store request was duplicated after acceptance");
                for (index = 0; index < 32; index = index + 1)
                    check_condition(R[index] === store_registers[index],
                                    "store caused unexpected register write-back");
            end
        end

        check_condition(saw_completion_wait,
                        "store did not observe delayed response completion");
        check_condition(instr_addr == 32'd2,
                        "PC advanced before consuming store completion");
        for (index = 0; index < 32; index = index + 1)
            check_condition(R[index] === store_registers[index],
                            "store completion changed a register");

        // Configure the immediately following second load.
        l1_cfg_accept_delay     = 8'd1;
        l1_cfg_completion_delay = 8'd2;
        l1_cfg_response_data    = 32'h5566_7788;

        while (instr_addr != 32'd3)
            @(negedge clk);

        check_condition(response_count == 2,
                        "store did not produce exactly one completion response");
        check_condition(R[3] == 32'b0,
                        "second load destination changed before its request");

        while (!data_req_valid)
            @(negedge clk);

        check_condition(data_req_addr == 32'h0001_0008,
                        "second load did not issue the canonical byte address");
        check_condition(!data_req_write, "second load was marked as a write");

        while (!l1_accepted) begin
            @(negedge clk);
            if (!l1_accepted) begin
                check_condition(instr_addr == 32'd3,
                                "PC advanced while second load awaited acceptance");
                check_condition(R[3] == 32'b0,
                                "second load destination changed before response");
            end
        end

        while (!l1_response_issued) begin
            @(negedge clk);
            if (!l1_response_issued) begin
                check_condition(instr_addr == 32'd3,
                                "PC advanced before second load response");
                check_condition(!data_req_valid,
                                "second load request was duplicated");
                check_condition(R[3] == 32'b0,
                                "second load destination changed before response");
            end
        end

        while (instr_addr != 32'd4)
            @(negedge clk);

        check_condition(R[3] == 32'h5566_7788,
                        "second load response was not written to its destination");
        check_condition(acceptance_count == 3,
                        "back-to-back memory instructions were not accepted exactly once");
        check_condition(response_count == 3,
                        "back-to-back memory instructions did not each complete once");

        // The normal ADDI following memory completion must execute normally.
        check_condition(!data_req_valid,
                        "normal instruction unexpectedly issued a memory request");

        while (instr_addr != 32'd5)
            @(negedge clk);

        check_condition(R[4] == 32'h5566_7789,
                        "normal instruction after memory completion executed incorrectly");

        @(posedge clk);
        @(negedge clk);
        check_condition(r2_change_count == 1,
                        "first load destination changed more than once");
        check_condition(r3_change_count == 1,
                        "second load destination changed more than once");
        check_condition(acceptance_count == 3,
                        "duplicate memory request was accepted");
        check_condition(response_count == 3,
                        "unexpected duplicate memory response was observed");
        check_condition(store_acceptance_count == 1,
                        "store was accepted more than once");

        if (error_count == 0) begin
            $display("PASS: tb_cpu_memory_handshake");
            $finish;
        end else begin
            $display("FAIL: tb_cpu_memory_handshake");
            $fatal(1, "CPU memory handshake regression failed with %0d error(s)",
                   error_count);
        end
    end
endmodule
