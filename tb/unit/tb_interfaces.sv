import mc_defs_pkg::*;

module tb_interfaces;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;

    logic issue_valid;
    logic issue_ready;
    logic [MC_ADDR_WIDTH-1:0] issue_address;
    mc_mem_op_t issue_op;
    logic [MC_WORD_WIDTH-1:0] issue_write_data;

    logic core_request_valid;
    logic core_request_ready;
    logic [MC_ADDR_WIDTH-1:0] core_request_address;
    mc_mem_op_t core_request_op;
    logic [MC_WORD_WIDTH-1:0] core_request_write_data;

    logic core_response_valid;
    logic [MC_WORD_WIDTH-1:0] core_response_read_data;
    mc_resp_status_t core_response_status;

    logic core_outstanding;
    logic core_completed;
    logic [MC_WORD_WIDTH-1:0] core_completed_read_data;
    mc_resp_status_t core_completed_status;

    logic [7:0] l1_cfg_accept_delay;
    logic [7:0] l1_cfg_completion_delay;
    logic [MC_WORD_WIDTH-1:0] l1_cfg_response_data;
    logic l1_cfg_sc_success;
    logic l1_accepted;
    logic l1_response_issued;

    logic [7:0] memory_cfg_accept_delay;
    logic [7:0] memory_cfg_completion_delay;
    logic [MC_LINE_WIDTH-1:0] memory_cfg_read_data;
    logic memory_request_valid;
    logic memory_request_ready;
    mc_line_mem_op_t memory_request_op;
    logic [MC_ADDR_WIDTH-1:0] memory_request_line_address;
    logic [MC_LINE_WIDTH-1:0] memory_request_write_data;
    logic memory_response_valid;
    logic [MC_LINE_WIDTH-1:0] memory_response_read_data;
    logic memory_accepted;
    logic memory_response_issued;

    integer error_count;
    integer cycle_count;
    integer core_accept_count;
    integer core_response_count;
    integer memory_accept_count;
    integer memory_response_count;

    mock_core core (
        .clk(clk),
        .rst(rst),
        .issue_valid(issue_valid),
        .issue_ready(issue_ready),
        .issue_address(issue_address),
        .issue_op(issue_op),
        .issue_write_data(issue_write_data),
        .request_valid(core_request_valid),
        .request_ready(core_request_ready),
        .request_address(core_request_address),
        .request_op(core_request_op),
        .request_write_data(core_request_write_data),
        .response_valid(core_response_valid),
        .response_read_data(core_response_read_data),
        .response_status(core_response_status),
        .outstanding(core_outstanding),
        .completed(core_completed),
        .completed_read_data(core_completed_read_data),
        .completed_status(core_completed_status)
    );

    mock_l1 l1 (
        .clk(clk),
        .rst(rst),
        .cfg_accept_delay(l1_cfg_accept_delay),
        .cfg_completion_delay(l1_cfg_completion_delay),
        .cfg_response_data(l1_cfg_response_data),
        .cfg_sc_success(l1_cfg_sc_success),
        .request_valid(core_request_valid),
        .request_ready(core_request_ready),
        .request_address(core_request_address),
        .request_op(core_request_op),
        .request_write_data(core_request_write_data),
        .response_valid(core_response_valid),
        .response_read_data(core_response_read_data),
        .response_status(core_response_status),
        .accepted(l1_accepted),
        .response_issued(l1_response_issued)
    );

    mock_memory memory (
        .clk(clk),
        .rst(rst),
        .cfg_accept_delay(memory_cfg_accept_delay),
        .cfg_completion_delay(memory_cfg_completion_delay),
        .cfg_read_data(memory_cfg_read_data),
        .request_valid(memory_request_valid),
        .request_ready(memory_request_ready),
        .request_op(memory_request_op),
        .request_line_address(memory_request_line_address),
        .request_write_data(memory_request_write_data),
        .response_valid(memory_response_valid),
        .response_read_data(memory_response_read_data),
        .accepted(memory_accepted),
        .response_issued(memory_response_issued)
    );

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

    task automatic issue_core_request;
        input logic [MC_ADDR_WIDTH-1:0] address;
        input mc_mem_op_t operation;
        input logic [MC_WORD_WIDTH-1:0] write_data;
        begin
            @(negedge clk);
            check_condition(issue_ready, "mock core was not ready for a new request");
            issue_address    = address;
            issue_op         = operation;
            issue_write_data = write_data;
            issue_valid      = 1'b1;
            @(negedge clk);
            issue_valid      = 1'b0;
        end
    endtask

    always begin
        #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (rst) begin
            cycle_count           <= 0;
            core_accept_count     <= 0;
            core_response_count   <= 0;
            memory_accept_count   <= 0;
            memory_response_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (core_request_valid && core_request_ready)
                core_accept_count <= core_accept_count + 1;

            if (core_response_valid)
                core_response_count <= core_response_count + 1;

            if (memory_request_valid && memory_request_ready)
                memory_accept_count <= memory_accept_count + 1;

            if (memory_response_valid)
                memory_response_count <= memory_response_count + 1;
        end
    end

    initial begin
        #100000;
        $display("ERROR: timeout waiting for interface regression to complete");
        $display("FAIL: tb_interfaces");
        $fatal(1, "tb_interfaces timed out");
    end

    initial begin : run_test
        logic [MC_ADDR_WIDTH-1:0] held_address;
        mc_mem_op_t held_op;
        logic [MC_WORD_WIDTH-1:0] held_write_data;
        logic [MC_ADDR_WIDTH-1:0] held_memory_address;
        mc_line_mem_op_t held_memory_op;
        logic [MC_LINE_WIDTH-1:0] held_memory_write_data;
        integer accept_count_before;
        integer response_count_before;
        integer accept_cycle;
        integer response_cycle;
        integer memory_issue_cycle;
        integer memory_accept_cycle;
        integer memory_response_cycle;
        logic saw_core_backpressure;
        logic saw_memory_backpressure;

        clk = 1'b0;
        rst = 1'b1;
        error_count = 0;

        issue_valid      = 1'b0;
        issue_address    = '0;
        issue_op         = MC_MEM_LOAD;
        issue_write_data = '0;

        l1_cfg_accept_delay     = 8'd0;
        l1_cfg_completion_delay = 8'd0;
        l1_cfg_response_data    = '0;
        l1_cfg_sc_success       = 1'b0;

        memory_cfg_accept_delay     = 8'd0;
        memory_cfg_completion_delay = 8'd0;
        memory_cfg_read_data        = '0;
        memory_request_valid        = 1'b0;
        memory_request_op           = MC_LINE_READ;
        memory_request_line_address = '0;
        memory_request_write_data   = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        check_condition(!core_outstanding, "core reported an outstanding request after reset");
        check_condition(core_accept_count == 0, "request was accepted during reset");
        check_condition(core_response_count == 0, "response was generated during reset");

        // Delayed load: stable fields, one acceptance, one delayed response.
        l1_cfg_accept_delay     = 8'd3;
        l1_cfg_completion_delay = 8'd4;
        l1_cfg_response_data    = 32'h1234_abcd;
        l1_cfg_sc_success       = 1'b0;
        accept_count_before     = core_accept_count;
        response_count_before   = core_response_count;

        issue_core_request(32'h0000_1020, MC_MEM_LOAD, 32'h0000_0000);

        wait (core_request_valid);
        held_address       = core_request_address;
        held_op            = core_request_op;
        held_write_data    = core_request_write_data;
        saw_core_backpressure = 1'b0;

        while (!l1_accepted) begin
            @(negedge clk);
            if (!l1_accepted) begin
                check_condition(core_request_valid,
                                "request_valid dropped before request acceptance");
                check_condition(core_request_address == held_address,
                                "request address changed while request_ready was low");
                check_condition(core_request_op == held_op,
                                "request operation changed while request_ready was low");
                check_condition(core_request_write_data == held_write_data,
                                "request write data changed while request_ready was low");
                if (!core_request_ready)
                    saw_core_backpressure = 1'b1;
            end
        end

        accept_cycle = cycle_count;
        check_condition(saw_core_backpressure,
                        "load request did not observe configured L1 backpressure");
        check_condition(core_accept_count == accept_count_before + 1,
                        "load request was not accepted exactly once");
        check_condition(core_outstanding,
                        "core cleared outstanding state before load response");

        // Attempting to issue another request while waiting must be rejected.
        @(negedge clk);
        issue_address    = 32'h0000_2040;
        issue_op         = MC_MEM_STORE;
        issue_write_data = 32'hdead_beef;
        issue_valid      = 1'b1;
        check_condition(!issue_ready,
                        "mock core accepted a second request while one was outstanding");
        @(negedge clk);
        issue_valid = 1'b0;

        while (!core_completed)
            @(negedge clk);

        response_cycle = cycle_count;
        check_condition(response_cycle - accept_cycle >= 4,
                        "load response did not observe configured completion delay");
        check_condition(core_completed_read_data == 32'h1234_abcd,
                        "load response data did not reach the mock core");
        check_condition(core_completed_status == MC_RESP_OK,
                        "load returned an unexpected response status");
        check_condition(core_accept_count == accept_count_before + 1,
                        "a second request was accepted while load was outstanding");
        check_condition(core_response_count == response_count_before + 1,
                        "load did not generate exactly one response");

        @(negedge clk);

        // Store completion must not create duplicate acceptance or responses.
        l1_cfg_accept_delay     = 8'd1;
        l1_cfg_completion_delay = 8'd2;
        l1_cfg_response_data    = 32'h0000_0000;
        accept_count_before     = core_accept_count;
        response_count_before   = core_response_count;

        issue_core_request(32'h0000_3030, MC_MEM_STORE, 32'hcafe_f00d);

        while (!l1_accepted)
            @(negedge clk);

        while (!core_completed)
            @(negedge clk);

        check_condition(core_completed_status == MC_RESP_OK,
                        "store returned an unexpected response status");
        check_condition(core_accept_count == accept_count_before + 1,
                        "store request was not accepted exactly once");
        check_condition(core_response_count == response_count_before + 1,
                        "store did not generate exactly one response");

        repeat (3) @(posedge clk);
        @(negedge clk);
        check_condition(core_accept_count == accept_count_before + 1,
                        "store request was accepted more than once");
        check_condition(core_response_count == response_count_before + 1,
                        "store generated more than one response");

        // SC success status must propagate back to the issuing core.
        l1_cfg_accept_delay     = 8'd2;
        l1_cfg_completion_delay = 8'd3;
        l1_cfg_response_data    = 32'h0000_0000;
        l1_cfg_sc_success       = 1'b1;
        accept_count_before     = core_accept_count;
        response_count_before   = core_response_count;

        issue_core_request(32'h0000_4044, MC_MEM_SC, 32'h55aa_aa55);

        while (!core_completed)
            @(negedge clk);

        check_condition(core_completed_status == MC_RESP_SC_SUCCESS,
                        "successful sc.w status did not reach the mock core");
        check_condition(core_accept_count == accept_count_before + 1,
                        "sc.w request was not accepted exactly once");
        check_condition(core_response_count == response_count_before + 1,
                        "sc.w did not generate exactly one response");

        @(negedge clk);

        // Delayed shared-memory acceptance and completion.
        memory_cfg_accept_delay     = 8'd3;
        memory_cfg_completion_delay = 8'd5;
        memory_cfg_read_data        = 128'h00112233_44556677_8899aabb_ccddeeff;
        memory_request_op           = MC_LINE_READ;
        memory_request_line_address = 32'h0000_5080;
        memory_request_write_data   = '0;
        held_memory_address         = memory_request_line_address;
        held_memory_op              = memory_request_op;
        held_memory_write_data      = memory_request_write_data;
        saw_memory_backpressure     = 1'b0;
        memory_issue_cycle          = cycle_count;
        memory_request_valid        = 1'b1;

        while (!memory_accepted) begin
            @(negedge clk);
            if (!memory_accepted) begin
                check_condition(memory_request_valid,
                                "memory request_valid dropped before acceptance");
                check_condition(memory_request_line_address == held_memory_address,
                                "memory line address changed before acceptance");
                check_condition(memory_request_op == held_memory_op,
                                "memory operation changed before acceptance");
                check_condition(memory_request_write_data == held_memory_write_data,
                                "memory write data changed before acceptance");
                if (!memory_request_ready)
                    saw_memory_backpressure = 1'b1;
            end
        end

        memory_accept_cycle   = cycle_count;
        memory_request_valid  = 1'b0;

        check_condition(saw_memory_backpressure,
                        "memory request did not observe configured acceptance delay");
        check_condition(memory_accept_cycle - memory_issue_cycle >= 3,
                        "memory request was accepted earlier than configured");
        check_condition(memory_accept_count == 1,
                        "memory request was not accepted exactly once");
        check_condition(held_memory_address[3:0] == 4'b0000,
                        "memory test did not use an aligned line address");

        while (!memory_response_issued)
            @(negedge clk);

        memory_response_cycle = cycle_count;
        check_condition(memory_response_cycle - memory_accept_cycle >= 5,
                        "memory response did not observe configured completion delay");
        check_condition(memory_response_valid,
                        "memory response_issued did not coincide with response_valid");
        check_condition(
            memory_response_read_data ==
                128'h00112233_44556677_8899aabb_ccddeeff,
            "deterministic memory line data was incorrect"
        );

        @(posedge clk);
        @(negedge clk);
        check_condition(memory_accept_count == 1,
                        "memory request was accepted more than once");
        check_condition(memory_response_count == 1,
                        "memory did not generate exactly one response");

        if (error_count == 0) begin
            $display("PASS: tb_interfaces");
            $finish;
        end else begin
            $display("FAIL: tb_interfaces");
            $fatal(1, "interface regression failed with %0d error(s)", error_count);
        end
    end
endmodule
