import mc_defs_pkg::*;

module tb_shared_memory;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer TEST_LINE_COUNT = 8;
    localparam integer TEST_LATENCY    = 3;

    localparam logic [MC_LINE_WIDTH-1:0] DATA_A =
        128'h00112233_44556677_8899aabb_ccddeeff;
    localparam logic [MC_LINE_WIDTH-1:0] DATA_ZERO_LINE =
        128'h10203040_50607080_90a0b0c0_d0e0f000;
    localparam logic [MC_LINE_WIDTH-1:0] DATA_OLD =
        128'h11112222_33334444_55556666_77778888;
    localparam logic [MC_LINE_WIDTH-1:0] DATA_NEW =
        128'haaaabbbb_ccccdddd_eeeeffff_00001111;
    localparam logic [MC_LINE_WIDTH-1:0] DATA_BAD =
        128'hdeaddead_beefbeef_cafecafe_01234567;

    logic                         clk;
    logic                         rst;
    logic                         memory_req_valid;
    logic                         memory_req_ready;
    mc_line_mem_op_t              memory_req_op;
    logic [MC_ADDR_WIDTH-1:0]     memory_req_line_addr;
    logic [MC_LINE_WIDTH-1:0]     memory_req_wdata;
    logic                         memory_rsp_valid;
    logic [MC_LINE_WIDTH-1:0]     memory_rsp_rdata;
    logic                         memory_rsp_error;

    integer error_count;
    integer cycle_count;
    integer acceptance_count;
    integer response_count;

    shared_memory #(
        .LINE_COUNT(TEST_LINE_COUNT),
        .RESPONSE_LATENCY(TEST_LATENCY)
    ) dut (
        .clk(clk),
        .rst(rst),
        .memory_req_valid(memory_req_valid),
        .memory_req_ready(memory_req_ready),
        .memory_req_op(memory_req_op),
        .memory_req_line_addr(memory_req_line_addr),
        .memory_req_wdata(memory_req_wdata),
        .memory_rsp_valid(memory_rsp_valid),
        .memory_rsp_rdata(memory_rsp_rdata),
        .memory_rsp_error(memory_rsp_error)
    );

    always begin
        #5 clk = ~clk;
    end

    task automatic check_condition;
        input logic condition;
        input string message;
        begin
            if (condition !== 1'b1) begin
                error_count = error_count + 1;
                $display("ERROR: %s", message);
            end
        end
    endtask

    task automatic start_request;
        input mc_line_mem_op_t operation;
        input logic [MC_ADDR_WIDTH-1:0] line_address;
        input logic [MC_LINE_WIDTH-1:0] write_data;
        output integer accepted_cycle;
        begin
            @(negedge clk);
            memory_req_op        = operation;
            memory_req_line_addr = line_address;
            memory_req_wdata     = write_data;
            memory_req_valid     = 1'b1;

            while (memory_req_ready !== 1'b1)
                @(negedge clk);

            @(posedge clk);
            #1;
            accepted_cycle = cycle_count;
            check_condition(!memory_req_ready,
                            "memory remained ready after accepting a request");
        end
    endtask

    task automatic finish_request;
        input integer accepted_cycle;
        input logic expected_error;
        input logic [MC_LINE_WIDTH-1:0] expected_data;
        input logic check_read_data;
        integer completed_cycle;
        begin
            while (memory_rsp_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                if (memory_rsp_valid !== 1'b1)
                    check_condition(!memory_req_ready,
                                    "memory asserted ready while a request was pending");
            end

            completed_cycle = cycle_count;
            check_condition(
                completed_cycle - accepted_cycle == TEST_LATENCY,
                "memory response did not match the configured latency"
            );
            check_condition(memory_rsp_error == expected_error,
                            "memory response error indication was incorrect");

            if (check_read_data)
                check_condition(memory_rsp_rdata == expected_data,
                                "memory returned incorrect 128-bit line data");
            else
                check_condition(
                    memory_rsp_rdata == {MC_LINE_WIDTH{1'b0}},
                    "write or error response returned unexpected data"
                );

            @(posedge clk);
            #1;
            check_condition(!memory_rsp_valid,
                            "memory response_valid lasted more than one cycle");
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;

            if (memory_req_valid && memory_req_ready)
                acceptance_count <= acceptance_count + 1;

            if (memory_rsp_valid)
                response_count <= response_count + 1;
        end
    end

    initial begin
        #500000;
        $display("ERROR: timeout waiting for shared-memory regression");
        $display("FAIL: tb_shared_memory");
        $fatal(1, "tb_shared_memory timed out");
    end

    initial begin
        integer accepted_cycle;
        integer acceptance_before;
        integer response_before;

        clk                  = 1'b0;
        rst                  = 1'b1;
        memory_req_valid     = 1'b0;
        memory_req_op        = MC_LINE_READ;
        memory_req_line_addr = {MC_ADDR_WIDTH{1'b0}};
        memory_req_wdata     = {MC_LINE_WIDTH{1'b0}};
        error_count          = 0;
        cycle_count          = 0;
        acceptance_count     = 0;
        response_count       = 0;

        repeat (3) @(posedge clk);
        #1;
        check_condition(!memory_req_ready,
                        "memory asserted ready during reset");
        check_condition(!memory_rsp_valid,
                        "memory asserted response_valid during reset");

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;
        check_condition(memory_req_ready,
                        "memory was not ready after reset");
        check_condition(!memory_rsp_valid,
                        "memory produced a response without a request");

        // Hold a valid write through completion and beyond.
        acceptance_before = acceptance_count;
        response_before   = response_count;
        start_request(MC_LINE_WRITE, 32'h0000_0010, DATA_A,
                      accepted_cycle);
        check_condition(acceptance_count == acceptance_before + 1,
                        "aligned write was not accepted exactly once");

        while (memory_rsp_valid !== 1'b1) begin
            @(posedge clk);
            #1;
            if (memory_rsp_valid !== 1'b1)
                check_condition(!memory_req_ready,
                                "held-valid write did not apply busy backpressure");
        end

        check_condition(cycle_count - accepted_cycle == TEST_LATENCY,
                        "held-valid write completed at the wrong latency");
        check_condition(!memory_rsp_error,
                        "aligned write completed with an error");
        check_condition(
            memory_rsp_rdata == {MC_LINE_WIDTH{1'b0}},
            "write completion returned unexpected read data"
        );
        check_condition(!memory_req_ready,
                        "held request became ready for duplicate acceptance");

        repeat (3) begin
            @(posedge clk);
            #1;
            check_condition(!memory_req_ready,
                            "held-valid request was rearmed without withdrawal");
            check_condition(!memory_rsp_valid,
                            "held-valid request generated a duplicate response");
            check_condition(acceptance_count == acceptance_before + 1,
                            "held-valid request was accepted more than once");
        end

        check_condition(response_count == response_before + 1,
                        "held-valid write did not produce exactly one response");

        @(negedge clk);
        memory_req_valid = 1'b0;
        @(posedge clk);
        #1;
        check_condition(memory_req_ready,
                        "memory did not rearm after request withdrawal");

        // Read-after-write while mutating external fields after capture.
        acceptance_before = acceptance_count;
        response_before   = response_count;
        start_request(MC_LINE_READ, 32'h0000_0010,
                      {MC_LINE_WIDTH{1'b0}}, accepted_cycle);

        @(negedge clk);
        memory_req_valid     = 1'b0;
        memory_req_op        = MC_LINE_WRITE;
        memory_req_line_addr = 32'h0000_0030;
        memory_req_wdata     = DATA_BAD;
        check_condition(!memory_req_ready,
                        "memory did not backpressure while read was pending");

        finish_request(accepted_cycle, 1'b0, DATA_A, 1'b1);
        check_condition(acceptance_count == acceptance_before + 1,
                        "captured read was accepted more than once");
        check_condition(response_count == response_before + 1,
                        "captured read did not complete exactly once");

        // Establish known contents at line zero.
        start_request(MC_LINE_WRITE, 32'h0000_0000, DATA_ZERO_LINE,
                      accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b0,
                       {MC_LINE_WIDTH{1'b0}}, 1'b0);

        // Out-of-range aligned write must error and not alias line zero.
        start_request(MC_LINE_WRITE, 32'h0000_0080, DATA_BAD,
                      accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b1,
                       {MC_LINE_WIDTH{1'b0}}, 1'b0);

        start_request(MC_LINE_READ, 32'h0000_0000,
                      {MC_LINE_WIDTH{1'b0}}, accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b0, DATA_ZERO_LINE, 1'b1);

        // Unaligned write must error and leave the corresponding valid line.
        start_request(MC_LINE_WRITE, 32'h0000_0014, DATA_BAD,
                      accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b1,
                       {MC_LINE_WIDTH{1'b0}}, 1'b0);

        start_request(MC_LINE_READ, 32'h0000_0010,
                      {MC_LINE_WIDTH{1'b0}}, accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b0, DATA_A, 1'b1);

        // Prepare line two, then cancel a replacement write with reset.
        start_request(MC_LINE_WRITE, 32'h0000_0020, DATA_OLD,
                      accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b0,
                       {MC_LINE_WIDTH{1'b0}}, 1'b0);

        response_before = response_count;
        start_request(MC_LINE_WRITE, 32'h0000_0020, DATA_NEW,
                      accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;

        @(posedge clk);
        #1;
        check_condition(!memory_rsp_valid,
                        "pending replacement write completed too early");

        @(negedge clk);
        rst = 1'b1;
        #1;
        check_condition(!memory_rsp_valid,
                        "reset completed a cancelled pending write");
        check_condition(!memory_req_ready,
                        "memory asserted ready while reset was active");

        repeat (2) begin
            @(posedge clk);
            #1;
            check_condition(!memory_rsp_valid,
                            "cancelled request produced a response during reset");
        end

        check_condition(response_count == response_before,
                        "cancelled request produced a completion response");

        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        #1;
        check_condition(memory_req_ready,
                        "memory did not return to idle after reset");

        start_request(MC_LINE_READ, 32'h0000_0020,
                      {MC_LINE_WIDTH{1'b0}}, accepted_cycle);
        @(negedge clk);
        memory_req_valid = 1'b0;
        finish_request(accepted_cycle, 1'b0, DATA_OLD, 1'b1);

        check_condition(acceptance_count == 10,
                        "total memory acceptance count was incorrect");
        check_condition(response_count == 9,
                        "total memory response count was incorrect");

        if (error_count == 0) begin
            $display("PASS: tb_shared_memory");
            $finish;
        end else begin
            $display("FAIL: tb_shared_memory");
            $fatal(1, "shared-memory regression failed with %0d error(s)",
                   error_count);
        end
    end
endmodule
