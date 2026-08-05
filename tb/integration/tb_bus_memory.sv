import mc_defs_pkg::*;

module tb_bus_memory;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer MEMORY_LINE_COUNT = 16;
    localparam integer MEMORY_LATENCY    = 3;

    localparam logic [MC_LINE_WIDTH-1:0] LINE_A =
        128'h01234567_89abcdef_fedcba98_76543210;
    localparam logic [MC_LINE_WIDTH-1:0] LINE_B =
        128'h11112222_33334444_aaaabbbb_ccccdddd;

    logic                         clk;
    logic                         rst;

    logic [1:0]                   l1_req_valid;
    logic [1:0]                   l1_req_ready;
    mc_bus_txn_t                  l1_req_txn_0;
    mc_bus_txn_t                  l1_req_txn_1;
    logic [MC_ADDR_WIDTH-1:0]     l1_req_line_addr_0;
    logic [MC_ADDR_WIDTH-1:0]     l1_req_line_addr_1;
    logic [MC_LINE_WIDTH-1:0]     l1_req_wdata_0;
    logic [MC_LINE_WIDTH-1:0]     l1_req_wdata_1;

    logic [1:0]                   l1_rsp_valid;
    logic [MC_LINE_WIDTH-1:0]     l1_rsp_data_0;
    logic [MC_LINE_WIDTH-1:0]     l1_rsp_data_1;
    logic [1:0]                   l1_rsp_shared;
    logic [1:0]                   l1_rsp_error;

    logic [1:0]                   snoop_valid;
    mc_bus_txn_t                  snoop_txn;
    logic [MC_ADDR_WIDTH-1:0]     snoop_line_addr;
    logic                         snoop_requester_id;
    logic [1:0]                   snoop_rsp_valid;
    logic [1:0]                   snoop_rsp_present;
    logic [1:0]                   snoop_rsp_dirty;
    logic [1:0]                   snoop_rsp_data_valid;
    logic [MC_LINE_WIDTH-1:0]     snoop_rsp_data_0;
    logic [MC_LINE_WIDTH-1:0]     snoop_rsp_data_1;

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
    integer memory_accept_count;
    integer response_count_0;
    integer response_count_1;

    shared_bus bus (
        .clk(clk),
        .rst(rst),
        .l1_req_valid(l1_req_valid),
        .l1_req_ready(l1_req_ready),
        .l1_req_txn_0(l1_req_txn_0),
        .l1_req_txn_1(l1_req_txn_1),
        .l1_req_line_addr_0(l1_req_line_addr_0),
        .l1_req_line_addr_1(l1_req_line_addr_1),
        .l1_req_wdata_0(l1_req_wdata_0),
        .l1_req_wdata_1(l1_req_wdata_1),
        .l1_rsp_valid(l1_rsp_valid),
        .l1_rsp_data_0(l1_rsp_data_0),
        .l1_rsp_data_1(l1_rsp_data_1),
        .l1_rsp_shared(l1_rsp_shared),
        .l1_rsp_error(l1_rsp_error),
        .snoop_valid(snoop_valid),
        .snoop_txn(snoop_txn),
        .snoop_line_addr(snoop_line_addr),
        .snoop_requester_id(snoop_requester_id),
        .snoop_rsp_valid(snoop_rsp_valid),
        .snoop_rsp_present(snoop_rsp_present),
        .snoop_rsp_dirty(snoop_rsp_dirty),
        .snoop_rsp_data_valid(snoop_rsp_data_valid),
        .snoop_rsp_data_0(snoop_rsp_data_0),
        .snoop_rsp_data_1(snoop_rsp_data_1),
        .memory_req_valid(memory_req_valid),
        .memory_req_ready(memory_req_ready),
        .memory_req_op(memory_req_op),
        .memory_req_line_addr(memory_req_line_addr),
        .memory_req_wdata(memory_req_wdata),
        .memory_rsp_valid(memory_rsp_valid),
        .memory_rsp_rdata(memory_rsp_rdata),
        .memory_rsp_error(memory_rsp_error)
    );

    shared_memory #(
        .LINE_COUNT(MEMORY_LINE_COUNT),
        .RESPONSE_LATENCY(MEMORY_LATENCY)
    ) memory (
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

    task automatic check_owner;
        input integer expected_owner;
        begin
            if (bus.owner_id !== (expected_owner == 1)) begin
                error_count = error_count + 1;
                $display(
                    "ERROR: bus ownership changed: expected=%0d actual=%0b",
                    expected_owner, bus.owner_id
                );
            end
        end
    endtask

    task automatic configure_request;
        input integer requester;
        input mc_bus_txn_t transaction;
        input logic [MC_ADDR_WIDTH-1:0] line_address;
        input logic [MC_LINE_WIDTH-1:0] write_data;
        begin
            if (requester == 0) begin
                l1_req_txn_0       = transaction;
                l1_req_line_addr_0 = line_address;
                l1_req_wdata_0     = write_data;
                l1_req_valid[0]    = 1'b1;
            end else begin
                l1_req_txn_1       = transaction;
                l1_req_line_addr_1 = line_address;
                l1_req_wdata_1     = write_data;
                l1_req_valid[1]    = 1'b1;
            end
        end
    endtask

    task automatic run_transaction;
        input integer expected_owner;
        input mc_bus_txn_t expected_txn;
        input logic [MC_ADDR_WIDTH-1:0] expected_line_address;
        input logic [MC_LINE_WIDTH-1:0] expected_write_data;
        input logic [1:0] requests_after_capture;
        input logic peer_present;
        input logic [MC_LINE_WIDTH-1:0] expected_response_data;
        input logic expected_response_error;

        integer delay_index;
        integer memory_accept_before;
        integer response_0_before;
        integer response_1_before;
        integer memory_accept_cycle;
        integer owner_response_cycle;
        logic requires_snoop;
        logic [1:0] expected_owner_mask;
        logic [1:0] expected_snoop_mask;
        logic [1:0] expected_shared_mask;
        logic [1:0] expected_error_mask;
        mc_line_mem_op_t expected_memory_op;
        begin
            requires_snoop = (expected_txn != MC_BUS_WRITEBACK);
            expected_owner_mask =
                (expected_owner == 0) ? 2'b01 : 2'b10;
            expected_snoop_mask =
                (expected_owner == 0) ? 2'b10 : 2'b01;
            expected_shared_mask =
                (requires_snoop && peer_present)
                ? expected_owner_mask : 2'b00;
            expected_error_mask =
                expected_response_error ? expected_owner_mask : 2'b00;
            expected_memory_op = mc_line_mem_op_t'(
                (expected_txn == MC_BUS_WRITEBACK)
                ? MC_LINE_WRITE : MC_LINE_READ
            );

            memory_accept_before = memory_accept_count;
            response_0_before    = response_count_0;
            response_1_before    = response_count_1;

            while (l1_req_ready[expected_owner] !== 1'b1) begin
                @(negedge clk);
                check_condition(
                    l1_req_ready[1 - expected_owner] !== 1'b1,
                    "round-robin arbiter selected the wrong requester"
                );
            end

            check_condition(l1_req_ready == expected_owner_mask,
                            "bus request acceptance was not one-hot");

            @(posedge clk);
            #1;
            check_owner(expected_owner);

            if (requires_snoop) begin
                check_condition(snoop_valid == expected_snoop_mask,
                                "clean snoop was not routed only to the nonowner");
                check_condition(snoop_txn == expected_txn,
                                "snoop transaction did not match the captured request");
                check_condition(snoop_line_addr == expected_line_address,
                                "snoop line address did not match the captured request");
                check_condition(
                    snoop_requester_id == (expected_owner == 1),
                    "snoop requester identity did not match the owner"
                );
                check_condition(!memory_req_valid,
                                "bus accessed memory before snoop acknowledgement");
            end else begin
                check_condition(snoop_valid == 2'b00,
                                "write-back incorrectly snooped the peer");
                check_condition(memory_req_valid,
                                "write-back did not issue a direct memory request");
            end

            @(negedge clk);
            l1_req_valid = requests_after_capture;

            if (requires_snoop) begin
                for (delay_index = 0; delay_index < 2;
                     delay_index = delay_index + 1) begin
                    @(posedge clk);
                    #1;
                    check_owner(expected_owner);
                    check_condition(snoop_valid == expected_snoop_mask,
                                    "snoop changed before clean acknowledgement");
                    check_condition(!memory_req_valid,
                                    "memory request preceded clean snoop acknowledgement");
                    check_condition(l1_rsp_valid == 2'b00,
                                    "owner response preceded memory completion");
                end

                @(negedge clk);
                snoop_rsp_valid      = expected_snoop_mask;
                snoop_rsp_present    =
                    peer_present ? expected_snoop_mask : 2'b00;
                snoop_rsp_dirty      = 2'b00;
                snoop_rsp_data_valid = 2'b00;

                @(posedge clk);
                #1;
                check_owner(expected_owner);
                check_condition(memory_req_valid,
                                "bus did not issue memory request after clean snoop");

                @(negedge clk);
                snoop_rsp_valid      = 2'b00;
                snoop_rsp_present    = 2'b00;
                snoop_rsp_dirty      = 2'b00;
                snoop_rsp_data_valid = 2'b00;
            end

            check_condition(memory_req_valid,
                            "bus-to-memory request was not asserted");
            check_condition(memory_req_op == expected_memory_op,
                            "bus-to-memory operation was incorrect");
            check_condition(memory_req_line_addr == expected_line_address,
                            "bus-to-memory line address was incorrect");
            check_condition(memory_req_wdata == expected_write_data,
                            "bus-to-memory write line was incorrect");

            while (!(memory_req_valid && memory_req_ready)) begin
                @(negedge clk);
                check_owner(expected_owner);
                check_condition(l1_rsp_valid == 2'b00,
                                "response appeared before memory acceptance");
            end

            @(posedge clk);
            #1;
            memory_accept_cycle = cycle_count;
            check_owner(expected_owner);
            check_condition(!memory_req_valid,
                            "bus repeated memory request after acceptance");

            while (l1_rsp_valid == 2'b00) begin
                @(posedge clk);
                #1;
                if (l1_rsp_valid == 2'b00) begin
                    check_owner(expected_owner);
                    check_condition(!memory_req_valid,
                                    "bus issued duplicate memory transaction");
                end
            end

            owner_response_cycle = cycle_count;
            check_condition(
                owner_response_cycle - memory_accept_cycle >= MEMORY_LATENCY,
                "bus response did not preserve memory completion latency"
            );
            check_condition(l1_rsp_valid == expected_owner_mask,
                            "final response was not routed only to the owner");
            check_condition(l1_rsp_shared == expected_shared_mask,
                            "peer-present indication was routed incorrectly");
            check_condition(l1_rsp_error == expected_error_mask,
                            "memory error was not propagated correctly");
            check_owner(expected_owner);

            if (expected_owner == 0) begin
                check_condition(l1_rsp_data_0 == expected_response_data,
                                "requester 0 received incorrect line data");
                check_condition(
                    l1_rsp_data_1 == {MC_LINE_WIDTH{1'b0}},
                    "nonowner requester 1 received response data"
                );
            end else begin
                check_condition(l1_rsp_data_1 == expected_response_data,
                                "requester 1 received incorrect line data");
                check_condition(
                    l1_rsp_data_0 == {MC_LINE_WIDTH{1'b0}},
                    "nonowner requester 0 received response data"
                );
            end

            @(posedge clk);
            #1;
            check_condition(l1_rsp_valid == 2'b00,
                            "bus final response lasted more than one cycle");
            check_condition(memory_accept_count == memory_accept_before + 1,
                            "memory transaction was not accepted exactly once");

            if (expected_owner == 0) begin
                check_condition(response_count_0 == response_0_before + 1,
                                "requester 0 did not receive exactly one response");
                check_condition(response_count_1 == response_1_before,
                                "nonowner requester 1 received a response");
            end else begin
                check_condition(response_count_1 == response_1_before + 1,
                                "requester 1 did not receive exactly one response");
                check_condition(response_count_0 == response_0_before,
                                "nonowner requester 0 received a response");
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;

            if (memory_req_valid && memory_req_ready)
                memory_accept_count <= memory_accept_count + 1;

            if (l1_rsp_valid[0])
                response_count_0 <= response_count_0 + 1;

            if (l1_rsp_valid[1])
                response_count_1 <= response_count_1 + 1;
        end
    end

    always @(negedge clk) begin
        if (!rst) begin
            check_condition(
                (bus.arb_grant == 2'b00) ||
                (bus.arb_grant == 2'b01) ||
                (bus.arb_grant == 2'b10),
                "integrated arbiter grant was not one-hot-or-zero"
            );
            check_condition(
                (l1_rsp_valid == 2'b00) ||
                (l1_rsp_valid == 2'b01) ||
                (l1_rsp_valid == 2'b10),
                "integrated bus response was not one-hot-or-zero"
            );
        end
    end

    initial begin
        #500000;
        $display("ERROR: timeout waiting for bus-memory integration regression");
        $display("FAIL: tb_bus_memory");
        $fatal(1, "tb_bus_memory timed out");
    end

    initial begin
        clk                  = 1'b0;
        rst                  = 1'b1;
        error_count          = 0;
        cycle_count          = 0;
        memory_accept_count  = 0;
        response_count_0     = 0;
        response_count_1     = 0;
        l1_req_valid         = 2'b00;
        l1_req_txn_0         = MC_BUS_RD;
        l1_req_txn_1         = MC_BUS_RD;
        l1_req_line_addr_0   = {MC_ADDR_WIDTH{1'b0}};
        l1_req_line_addr_1   = {MC_ADDR_WIDTH{1'b0}};
        l1_req_wdata_0       = {MC_LINE_WIDTH{1'b0}};
        l1_req_wdata_1       = {MC_LINE_WIDTH{1'b0}};
        snoop_rsp_valid      = 2'b00;
        snoop_rsp_present    = 2'b00;
        snoop_rsp_dirty      = 2'b00;
        snoop_rsp_data_valid = 2'b00;
        snoop_rsp_data_0     = {MC_LINE_WIDTH{1'b0}};
        snoop_rsp_data_1     = {MC_LINE_WIDTH{1'b0}};

        repeat (3) @(posedge clk);
        #1;
        check_condition(l1_req_ready == 2'b00,
                        "bus accepted a request during reset");
        check_condition(l1_rsp_valid == 2'b00,
                        "bus produced a response during reset");
        check_condition(snoop_valid == 2'b00,
                        "bus produced a snoop during reset");
        check_condition(!memory_req_valid,
                        "bus produced a memory request during reset");
        check_condition(!memory_req_ready,
                        "memory asserted ready during reset");
        check_condition(!memory_rsp_valid,
                        "memory produced a response during reset");

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;
        check_condition(memory_req_ready,
                        "integrated memory was not ready after reset");
        check_condition(l1_rsp_valid == 2'b00,
                        "integrated path produced an idle response");

        // Requester 0 writes a complete line through an explicit write-back.
        @(negedge clk);
        configure_request(0, MC_BUS_WRITEBACK, 32'h0000_0010, LINE_A);
        run_transaction(
            0, MC_BUS_WRITEBACK, 32'h0000_0010, LINE_A,
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b0
        );

        // Requester 1 reads the line stored by requester 0.
        @(negedge clk);
        configure_request(
            1, MC_BUS_RD, 32'h0000_0010, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            1, MC_BUS_RD, 32'h0000_0010,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b1, LINE_A, 1'b0
        );

        // Requester 1 writes another full line.
        @(negedge clk);
        configure_request(1, MC_BUS_WRITEBACK, 32'h0000_0020, LINE_B);
        run_transaction(
            1, MC_BUS_WRITEBACK, 32'h0000_0020, LINE_B,
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b0
        );

        // Requester 0 reads requester 1's stored line.
        @(negedge clk);
        configure_request(
            0, MC_BUS_RD, 32'h0000_0020, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            0, MC_BUS_RD, 32'h0000_0020,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, LINE_B, 1'b0
        );

        // Simultaneous requests use round-robin priority; requester 1 is next.
        @(negedge clk);
        configure_request(
            0, MC_BUS_RD, 32'h0000_0020, {MC_LINE_WIDTH{1'b0}}
        );
        configure_request(
            1, MC_BUS_RD, 32'h0000_0010, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            1, MC_BUS_RD, 32'h0000_0010,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, LINE_A, 1'b0
        );

        // Aligned line 16 is outside the configured 16-line memory.
        @(negedge clk);
        configure_request(
            0, MC_BUS_RD, 32'h0000_0100, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            0, MC_BUS_RD, 32'h0000_0100,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b1
        );

        @(negedge clk);
        #1;
        check_condition(memory_accept_count == 6,
                        "integrated memory accepted a duplicate transaction");
        check_condition(response_count_0 == 3,
                        "requester 0 integrated response count was incorrect");
        check_condition(response_count_1 == 3,
                        "requester 1 integrated response count was incorrect");
        check_condition(l1_rsp_valid == 2'b00,
                        "integrated bus generated a duplicate response");

        if (error_count == 0) begin
            $display("PASS: tb_bus_memory");
            $finish;
        end else begin
            $display("FAIL: tb_bus_memory");
            $fatal(1, "bus-memory integration regression failed with %0d error(s)",
                   error_count);
        end
    end
endmodule
