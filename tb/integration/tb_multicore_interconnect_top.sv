import mc_defs_pkg::*;

module tb_multicore_interconnect_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer MEMORY_LINE_COUNT = 16;
    localparam integer MEMORY_LATENCY    = 3;

    localparam logic [MC_LINE_WIDTH-1:0] LINE_A =
        128'h00112233_44556677_8899aabb_ccddeeff;
    localparam logic [MC_LINE_WIDTH-1:0] LINE_B =
        128'h10213243_54657687_98a9bacb_dcedfe0f;
    localparam logic [MC_LINE_WIDTH-1:0] LINE_OLD =
        128'h11112222_33334444_55556666_77778888;
    localparam logic [MC_LINE_WIDTH-1:0] LINE_NEW =
        128'haaaabbbb_ccccdddd_eeeeffff_00001111;

    logic                         clk;
    logic                         rst;

    logic                         cache0_req_valid;
    logic                         cache0_req_ready;
    mc_bus_txn_t                  cache0_req_txn;
    logic [MC_ADDR_WIDTH-1:0]     cache0_req_line_addr;
    logic [MC_LINE_WIDTH-1:0]     cache0_req_wdata;
    logic                         cache0_rsp_valid;
    logic [MC_LINE_WIDTH-1:0]     cache0_rsp_data;
    logic                         cache0_rsp_shared;
    logic                         cache0_rsp_error;
    logic                         cache0_snoop_valid;
    mc_bus_txn_t                  cache0_snoop_txn;
    logic [MC_ADDR_WIDTH-1:0]     cache0_snoop_line_addr;
    logic                         cache0_snoop_requester_id;
    logic                         cache0_snoop_rsp_valid;
    logic                         cache0_snoop_rsp_present;
    logic                         cache0_snoop_rsp_dirty;
    logic                         cache0_snoop_rsp_data_valid;
    logic [MC_LINE_WIDTH-1:0]     cache0_snoop_rsp_data;

    logic                         cache1_req_valid;
    logic                         cache1_req_ready;
    mc_bus_txn_t                  cache1_req_txn;
    logic [MC_ADDR_WIDTH-1:0]     cache1_req_line_addr;
    logic [MC_LINE_WIDTH-1:0]     cache1_req_wdata;
    logic                         cache1_rsp_valid;
    logic [MC_LINE_WIDTH-1:0]     cache1_rsp_data;
    logic                         cache1_rsp_shared;
    logic                         cache1_rsp_error;
    logic                         cache1_snoop_valid;
    mc_bus_txn_t                  cache1_snoop_txn;
    logic [MC_ADDR_WIDTH-1:0]     cache1_snoop_line_addr;
    logic                         cache1_snoop_requester_id;
    logic                         cache1_snoop_rsp_valid;
    logic                         cache1_snoop_rsp_present;
    logic                         cache1_snoop_rsp_dirty;
    logic                         cache1_snoop_rsp_data_valid;
    logic [MC_LINE_WIDTH-1:0]     cache1_snoop_rsp_data;

    wire [1:0] request_ready_view = {
        cache1_req_ready, cache0_req_ready
    };
    wire [1:0] response_valid_view = {
        cache1_rsp_valid, cache0_rsp_valid
    };
    wire [1:0] response_shared_view = {
        cache1_rsp_shared, cache0_rsp_shared
    };
    wire [1:0] response_error_view = {
        cache1_rsp_error, cache0_rsp_error
    };
    wire [1:0] snoop_valid_view = {
        cache1_snoop_valid, cache0_snoop_valid
    };

    integer error_count;
    integer cycle_count;
    integer memory_accept_count;
    integer response_count_0;
    integer response_count_1;

    multicore_interconnect_top #(
        .MEMORY_LINE_COUNT(MEMORY_LINE_COUNT),
        .MEMORY_RESPONSE_LATENCY(MEMORY_LATENCY)
    ) dut (
        .clk(clk),
        .rst(rst),
        .cache0_req_valid(cache0_req_valid),
        .cache0_req_ready(cache0_req_ready),
        .cache0_req_txn(cache0_req_txn),
        .cache0_req_line_addr(cache0_req_line_addr),
        .cache0_req_wdata(cache0_req_wdata),
        .cache0_rsp_valid(cache0_rsp_valid),
        .cache0_rsp_data(cache0_rsp_data),
        .cache0_rsp_shared(cache0_rsp_shared),
        .cache0_rsp_error(cache0_rsp_error),
        .cache0_snoop_valid(cache0_snoop_valid),
        .cache0_snoop_txn(cache0_snoop_txn),
        .cache0_snoop_line_addr(cache0_snoop_line_addr),
        .cache0_snoop_requester_id(cache0_snoop_requester_id),
        .cache0_snoop_rsp_valid(cache0_snoop_rsp_valid),
        .cache0_snoop_rsp_present(cache0_snoop_rsp_present),
        .cache0_snoop_rsp_dirty(cache0_snoop_rsp_dirty),
        .cache0_snoop_rsp_data_valid(cache0_snoop_rsp_data_valid),
        .cache0_snoop_rsp_data(cache0_snoop_rsp_data),
        .cache1_req_valid(cache1_req_valid),
        .cache1_req_ready(cache1_req_ready),
        .cache1_req_txn(cache1_req_txn),
        .cache1_req_line_addr(cache1_req_line_addr),
        .cache1_req_wdata(cache1_req_wdata),
        .cache1_rsp_valid(cache1_rsp_valid),
        .cache1_rsp_data(cache1_rsp_data),
        .cache1_rsp_shared(cache1_rsp_shared),
        .cache1_rsp_error(cache1_rsp_error),
        .cache1_snoop_valid(cache1_snoop_valid),
        .cache1_snoop_txn(cache1_snoop_txn),
        .cache1_snoop_line_addr(cache1_snoop_line_addr),
        .cache1_snoop_requester_id(cache1_snoop_requester_id),
        .cache1_snoop_rsp_valid(cache1_snoop_rsp_valid),
        .cache1_snoop_rsp_present(cache1_snoop_rsp_present),
        .cache1_snoop_rsp_dirty(cache1_snoop_rsp_dirty),
        .cache1_snoop_rsp_data_valid(cache1_snoop_rsp_data_valid),
        .cache1_snoop_rsp_data(cache1_snoop_rsp_data)
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
            if (dut.bus.owner_id !== (expected_owner == 1)) begin
                error_count = error_count + 1;
                $display(
                    "ERROR: interconnect owner changed: expected=%0d actual=%0b",
                    expected_owner, dut.bus.owner_id
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
                cache0_req_txn       = transaction;
                cache0_req_line_addr = line_address;
                cache0_req_wdata     = write_data;
                cache0_req_valid     = 1'b1;
            end else begin
                cache1_req_txn       = transaction;
                cache1_req_line_addr = line_address;
                cache1_req_wdata     = write_data;
                cache1_req_valid     = 1'b1;
            end
        end
    endtask

    task automatic drive_request_mask;
        input logic [1:0] request_mask;
        begin
            cache0_req_valid = request_mask[0];
            cache1_req_valid = request_mask[1];
        end
    endtask

    task automatic drive_clean_snoop_response;
        input integer owner;
        input logic peer_present;
        begin
            cache0_snoop_rsp_valid   = 1'b0;
            cache1_snoop_rsp_valid   = 1'b0;
            cache0_snoop_rsp_present = 1'b0;
            cache1_snoop_rsp_present = 1'b0;
            cache0_snoop_rsp_dirty   = 1'b0;
            cache1_snoop_rsp_dirty   = 1'b0;

            if (owner == 0) begin
                cache1_snoop_rsp_valid   = 1'b1;
                cache1_snoop_rsp_present = peer_present;
            end else begin
                cache0_snoop_rsp_valid   = 1'b1;
                cache0_snoop_rsp_present = peer_present;
            end
        end
    endtask

    task automatic clear_snoop_responses;
        begin
            cache0_snoop_rsp_valid      = 1'b0;
            cache1_snoop_rsp_valid      = 1'b0;
            cache0_snoop_rsp_present    = 1'b0;
            cache1_snoop_rsp_present    = 1'b0;
            cache0_snoop_rsp_dirty      = 1'b0;
            cache1_snoop_rsp_dirty      = 1'b0;
            cache0_snoop_rsp_data_valid = 1'b0;
            cache1_snoop_rsp_data_valid = 1'b0;
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
        logic [1:0] expected_owner_mask;
        logic [1:0] expected_snoop_mask;
        logic [1:0] expected_shared_mask;
        logic [1:0] expected_error_mask;
        mc_line_mem_op_t expected_memory_op;
        begin
            expected_owner_mask =
                (expected_owner == 0) ? 2'b01 : 2'b10;
            expected_snoop_mask =
                (expected_owner == 0) ? 2'b10 : 2'b01;
            expected_shared_mask =
                peer_present ? expected_owner_mask : 2'b00;
            expected_error_mask =
                expected_response_error ? expected_owner_mask : 2'b00;

            if (expected_txn == MC_BUS_WRITEBACK)
                expected_memory_op = MC_LINE_WRITE;
            else
                expected_memory_op = MC_LINE_READ;

            memory_accept_before = memory_accept_count;
            response_0_before    = response_count_0;
            response_1_before    = response_count_1;

            while (request_ready_view[expected_owner] !== 1'b1) begin
                @(negedge clk);
                check_condition(
                    request_ready_view[1 - expected_owner] !== 1'b1,
                    "top-level arbiter selected the wrong endpoint"
                );
            end

            check_condition(request_ready_view == expected_owner_mask,
                            "top-level request acceptance was not one-hot");

            @(posedge clk);
            #1;
            check_owner(expected_owner);
            check_condition(snoop_valid_view == expected_snoop_mask,
                            "top-level snoop was not routed only to the nonowner");

            if (expected_owner == 0) begin
                check_condition(cache1_snoop_txn == expected_txn,
                                "cache 1 snoop transaction was incorrect");
                check_condition(
                    cache1_snoop_line_addr == expected_line_address,
                    "cache 1 snoop line address was incorrect"
                );
                check_condition(!cache1_snoop_requester_id,
                                "cache 1 snoop requester ID was incorrect");
            end else begin
                check_condition(cache0_snoop_txn == expected_txn,
                                "cache 0 snoop transaction was incorrect");
                check_condition(
                    cache0_snoop_line_addr == expected_line_address,
                    "cache 0 snoop line address was incorrect"
                );
                check_condition(cache0_snoop_requester_id,
                                "cache 0 snoop requester ID was incorrect");
            end

            check_condition(!dut.memory_req_valid,
                            "top-level memory request preceded snoop completion");
            check_condition(response_valid_view == 2'b00,
                            "top-level response appeared before completion");

            @(negedge clk);
            drive_request_mask(requests_after_capture);

            for (delay_index = 0; delay_index < 2;
                 delay_index = delay_index + 1) begin
                @(posedge clk);
                #1;
                check_owner(expected_owner);
                check_condition(snoop_valid_view == expected_snoop_mask,
                                "snoop changed before delayed acknowledgement");
                check_condition(!dut.memory_req_valid,
                                "memory request preceded delayed snoop acknowledgement");
                check_condition(response_valid_view == 2'b00,
                                "owner response preceded memory completion");
            end

            @(negedge clk);
            drive_clean_snoop_response(expected_owner, peer_present);

            @(posedge clk);
            #1;
            check_owner(expected_owner);
            check_condition(dut.memory_req_valid,
                            "top-level did not issue internal memory request");
            check_condition(dut.memory_req_op == expected_memory_op,
                            "internal memory operation was incorrect");
            check_condition(
                dut.memory_req_line_addr == expected_line_address,
                "internal memory line address was incorrect"
            );
            check_condition(dut.memory_req_wdata == expected_write_data,
                            "internal memory write data was incorrect");

            @(negedge clk);
            clear_snoop_responses();

            while (!(dut.memory_req_valid && dut.memory_req_ready)) begin
                @(negedge clk);
                check_owner(expected_owner);
                check_condition(response_valid_view == 2'b00,
                                "response appeared before memory acceptance");
            end

            @(posedge clk);
            #1;
            memory_accept_cycle = cycle_count;
            check_owner(expected_owner);
            check_condition(!dut.memory_req_valid,
                            "top-level repeated an accepted memory request");

            while (response_valid_view == 2'b00) begin
                @(posedge clk);
                #1;
                if (response_valid_view == 2'b00) begin
                    check_owner(expected_owner);
                    check_condition(!dut.memory_req_valid,
                                    "top-level issued a duplicate memory request");
                end
            end

            owner_response_cycle = cycle_count;
            check_condition(
                owner_response_cycle - memory_accept_cycle >= MEMORY_LATENCY,
                "top-level response did not preserve memory latency"
            );
            check_condition(response_valid_view == expected_owner_mask,
                            "top-level response was not owner-only");
            check_condition(response_shared_view == expected_shared_mask,
                            "top-level shared indication was incorrect");
            check_condition(response_error_view == expected_error_mask,
                            "top-level memory error propagation was incorrect");
            check_owner(expected_owner);

            if (expected_owner == 0) begin
                check_condition(cache0_rsp_data == expected_response_data,
                                "cache 0 received incorrect response data");
                check_condition(
                    cache1_rsp_data == {MC_LINE_WIDTH{1'b0}},
                    "nonowner cache 1 received response data"
                );
            end else begin
                check_condition(cache1_rsp_data == expected_response_data,
                                "cache 1 received incorrect response data");
                check_condition(
                    cache0_rsp_data == {MC_LINE_WIDTH{1'b0}},
                    "nonowner cache 0 received response data"
                );
            end

            @(posedge clk);
            #1;
            check_condition(response_valid_view == 2'b00,
                            "top-level owner response lasted more than one cycle");
            check_condition(memory_accept_count == memory_accept_before + 1,
                            "top-level memory operation was not accepted once");

            if (expected_owner == 0) begin
                check_condition(response_count_0 == response_0_before + 1,
                                "cache 0 did not receive exactly one response");
                check_condition(response_count_1 == response_1_before,
                                "nonowner cache 1 received a response");
            end else begin
                check_condition(response_count_1 == response_1_before + 1,
                                "cache 1 did not receive exactly one response");
                check_condition(response_count_0 == response_0_before,
                                "nonowner cache 0 received a response");
            end
        end
    endtask

    task automatic cancel_pending_write_with_reset;
        input integer owner;
        input logic [MC_ADDR_WIDTH-1:0] line_address;
        input logic [MC_LINE_WIDTH-1:0] write_data;
        integer memory_accept_before;
        integer response_0_before;
        integer response_1_before;
        logic [1:0] expected_snoop_mask;
        begin
            expected_snoop_mask = (owner == 0) ? 2'b10 : 2'b01;
            memory_accept_before = memory_accept_count;
            response_0_before    = response_count_0;
            response_1_before    = response_count_1;

            while (request_ready_view[owner] !== 1'b1)
                @(negedge clk);

            @(posedge clk);
            #1;
            check_owner(owner);
            check_condition(snoop_valid_view == expected_snoop_mask,
                            "cancelled write snoop routing was incorrect");

            @(negedge clk);
            drive_request_mask(2'b00);

            repeat (2) begin
                @(posedge clk);
                #1;
                check_owner(owner);
                check_condition(!dut.memory_req_valid,
                                "cancelled write reached memory before snoop ack");
            end

            @(negedge clk);
            drive_clean_snoop_response(owner, 1'b0);

            @(posedge clk);
            #1;
            check_owner(owner);
            check_condition(dut.memory_req_valid,
                            "cancelled write did not reach internal memory");
            check_condition(dut.memory_req_op == MC_LINE_WRITE,
                            "cancelled transaction was not a line write");
            check_condition(dut.memory_req_line_addr == line_address,
                            "cancelled write address was captured incorrectly");
            check_condition(dut.memory_req_wdata == write_data,
                            "cancelled write data was captured incorrectly");

            @(negedge clk);
            clear_snoop_responses();

            while (!(dut.memory_req_valid && dut.memory_req_ready))
                @(negedge clk);

            @(posedge clk);
            #1;
            check_condition(memory_accept_count == memory_accept_before + 1,
                            "pending write was not accepted by internal memory");
            check_owner(owner);
            check_condition(response_valid_view == 2'b00,
                            "pending write completed before reset");

            @(negedge clk);
            rst = 1'b1;
            #1;
            check_condition(response_valid_view == 2'b00,
                            "reset produced an owner response");
            check_condition(snoop_valid_view == 2'b00,
                            "reset left a snoop active");
            check_condition(!dut.memory_req_valid,
                            "reset left an internal memory request active");
            check_condition(!dut.memory_rsp_valid,
                            "reset completed the cancelled internal request");
            check_condition(!dut.memory_req_ready,
                            "internal memory asserted ready during reset");

            repeat (2) begin
                @(posedge clk);
                #1;
                check_condition(response_valid_view == 2'b00,
                                "cancelled write produced a response during reset");
                check_condition(!dut.memory_rsp_valid,
                                "cancelled memory write completed during reset");
            end

            check_condition(response_count_0 == response_0_before,
                            "reset cancellation generated a cache 0 response");
            check_condition(response_count_1 == response_1_before,
                            "reset cancellation generated a cache 1 response");

            @(negedge clk);
            rst = 1'b0;
            @(posedge clk);
            #1;
            check_condition(dut.memory_req_ready,
                            "internal memory did not recover after reset");
            check_condition(response_valid_view == 2'b00,
                            "top-level produced a response after reset recovery");
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;

            if (dut.memory_req_valid && dut.memory_req_ready)
                memory_accept_count <= memory_accept_count + 1;

            if (cache0_rsp_valid)
                response_count_0 <= response_count_0 + 1;

            if (cache1_rsp_valid)
                response_count_1 <= response_count_1 + 1;
        end
    end

    always @(negedge clk) begin
        if (!rst) begin
            check_condition(
                (dut.bus.arb_grant == 2'b00) ||
                (dut.bus.arb_grant == 2'b01) ||
                (dut.bus.arb_grant == 2'b10),
                "top-level arbiter grant was not one-hot-or-zero"
            );
            check_condition(
                (response_valid_view == 2'b00) ||
                (response_valid_view == 2'b01) ||
                (response_valid_view == 2'b10),
                "top-level response-valid was not one-hot-or-zero"
            );
        end
    end

    initial begin
        #750000;
        $display("ERROR: timeout waiting for multicore interconnect regression");
        $display("FAIL: tb_multicore_interconnect_top");
        $fatal(1, "tb_multicore_interconnect_top timed out");
    end

    initial begin
        clk                          = 1'b0;
        rst                          = 1'b1;
        error_count                  = 0;
        cycle_count                  = 0;
        memory_accept_count          = 0;
        response_count_0             = 0;
        response_count_1             = 0;
        cache0_req_valid             = 1'b0;
        cache0_req_txn               = MC_BUS_RD;
        cache0_req_line_addr         = {MC_ADDR_WIDTH{1'b0}};
        cache0_req_wdata             = {MC_LINE_WIDTH{1'b0}};
        cache0_snoop_rsp_valid       = 1'b0;
        cache0_snoop_rsp_present     = 1'b0;
        cache0_snoop_rsp_dirty       = 1'b0;
        cache0_snoop_rsp_data_valid  = 1'b0;
        cache0_snoop_rsp_data        = {MC_LINE_WIDTH{1'b0}};
        cache1_req_valid             = 1'b0;
        cache1_req_txn               = MC_BUS_RD;
        cache1_req_line_addr         = {MC_ADDR_WIDTH{1'b0}};
        cache1_req_wdata             = {MC_LINE_WIDTH{1'b0}};
        cache1_snoop_rsp_valid       = 1'b0;
        cache1_snoop_rsp_present     = 1'b0;
        cache1_snoop_rsp_dirty       = 1'b0;
        cache1_snoop_rsp_data_valid  = 1'b0;
        cache1_snoop_rsp_data        = {MC_LINE_WIDTH{1'b0}};

        repeat (3) @(posedge clk);
        #1;
        check_condition(request_ready_view == 2'b00,
                        "top-level accepted a request during reset");
        check_condition(response_valid_view == 2'b00,
                        "top-level generated a response during reset");
        check_condition(snoop_valid_view == 2'b00,
                        "top-level generated a snoop during reset");
        check_condition(!dut.memory_req_valid,
                        "top-level generated a memory request during reset");
        check_condition(!dut.memory_req_ready,
                        "internal memory asserted ready during reset");

        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        #1;
        check_condition(response_valid_view == 2'b00,
                        "top-level generated an idle response");
        check_condition(snoop_valid_view == 2'b00,
                        "top-level generated an idle snoop");
        check_condition(dut.memory_req_ready,
                        "internal memory was not ready after reset");

        // Cache 0 writes line A; cache 1 subsequently reads the complete line.
        @(negedge clk);
        configure_request(0, MC_BUS_WRITEBACK, 32'h0000_0010, LINE_A);
        run_transaction(
            0, MC_BUS_WRITEBACK, 32'h0000_0010, LINE_A,
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b0
        );

        @(negedge clk);
        configure_request(
            1, MC_BUS_RD, 32'h0000_0010, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            1, MC_BUS_RD, 32'h0000_0010,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b1, LINE_A, 1'b0
        );

        // Cache 1 writes line B; cache 0 subsequently reads it.
        @(negedge clk);
        configure_request(1, MC_BUS_WRITEBACK, 32'h0000_0020, LINE_B);
        run_transaction(
            1, MC_BUS_WRITEBACK, 32'h0000_0020, LINE_B,
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b0
        );

        @(negedge clk);
        configure_request(
            0, MC_BUS_RD, 32'h0000_0020, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            0, MC_BUS_RD, 32'h0000_0020,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, LINE_B, 1'b0
        );

        // Both endpoints remain active: requester 1 wins, then requester 0.
        @(negedge clk);
        configure_request(
            0, MC_BUS_RD, 32'h0000_0020, {MC_LINE_WIDTH{1'b0}}
        );
        configure_request(
            1, MC_BUS_RDX, 32'h0000_0010, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            1, MC_BUS_RDX, 32'h0000_0010,
            {MC_LINE_WIDTH{1'b0}},
            2'b11, 1'b0, LINE_A, 1'b0
        );
        run_transaction(
            0, MC_BUS_RD, 32'h0000_0020,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, LINE_B, 1'b0
        );

        // Memory bounds error must propagate only to cache 1.
        @(negedge clk);
        configure_request(
            1, MC_BUS_RD, 32'h0000_0100, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            1, MC_BUS_RD, 32'h0000_0100,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b1
        );

        // Establish persistent data before cancelling a replacement write.
        @(negedge clk);
        configure_request(0, MC_BUS_WRITEBACK, 32'h0000_0030, LINE_OLD);
        run_transaction(
            0, MC_BUS_WRITEBACK, 32'h0000_0030, LINE_OLD,
            2'b00, 1'b0, {MC_LINE_WIDTH{1'b0}}, 1'b0
        );

        @(negedge clk);
        configure_request(1, MC_BUS_WRITEBACK, 32'h0000_0030, LINE_NEW);
        cancel_pending_write_with_reset(1, 32'h0000_0030, LINE_NEW);

        // Traffic after reset must succeed and observe the unmodified old line.
        @(negedge clk);
        configure_request(
            0, MC_BUS_RD, 32'h0000_0030, {MC_LINE_WIDTH{1'b0}}
        );
        run_transaction(
            0, MC_BUS_RD, 32'h0000_0030,
            {MC_LINE_WIDTH{1'b0}},
            2'b00, 1'b0, LINE_OLD, 1'b0
        );

        @(negedge clk);
        #1;
        check_condition(memory_accept_count == 10,
                        "top-level internal memory acceptance count was incorrect");
        check_condition(response_count_0 == 5,
                        "cache 0 total response count was incorrect");
        check_condition(response_count_1 == 4,
                        "cache 1 total response count was incorrect");
        check_condition(response_valid_view == 2'b00,
                        "top-level generated a duplicate final response");

        if (error_count == 0) begin
            $display("PASS: tb_multicore_interconnect_top");
            $finish;
        end else begin
            $display("FAIL: tb_multicore_interconnect_top");
            $fatal(
                1,
                "multicore interconnect regression failed with %0d error(s)",
                error_count
            );
        end
    end
endmodule
