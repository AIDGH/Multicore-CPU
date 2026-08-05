import mc_defs_pkg::*;

module tb_shared_bus;
    timeunit 1ns;
    timeprecision 1ps;

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
    integer memory_accept_count;
    integer response_count_0;
    integer response_count_1;

    shared_bus dut (
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
            if (dut.owner_id !== (expected_owner == 1)) begin
                error_count = error_count + 1;
                $display(
                    "ERROR: transaction owner changed: expected=%0d actual=%0b",
                    expected_owner, dut.owner_id
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

    task automatic service_transaction;
        input integer expected_owner;
        input mc_bus_txn_t expected_txn;
        input logic [MC_ADDR_WIDTH-1:0] expected_line_address;
        input logic [MC_LINE_WIDTH-1:0] expected_write_data;
        input logic [1:0] requests_after_capture;
        input integer snoop_delay;
        input logic peer_present;
        input logic peer_dirty;
        input integer memory_accept_delay;
        input integer memory_response_delay;
        input logic [MC_LINE_WIDTH-1:0] expected_memory_data;
        input logic expected_memory_error;

        integer delay_index;
        integer memory_accept_before;
        integer response_0_before;
        integer response_1_before;
        logic requires_snoop;
        logic [1:0] expected_ready_mask;
        logic [1:0] expected_snoop_mask;
        logic [1:0] expected_response_mask;
        logic [1:0] expected_shared_mask;
        logic [1:0] expected_error_mask;
        mc_line_mem_op_t expected_memory_op;
        logic [MC_ADDR_WIDTH-1:0] held_memory_address;
        logic [MC_LINE_WIDTH-1:0] held_memory_write_data;
        logic [MC_LINE_WIDTH-1:0] dirty_peer_data;
        logic [MC_LINE_WIDTH-1:0] expected_response_data;
        logic [MC_LINE_WIDTH-1:0] expected_memory_write_data;
        begin
            requires_snoop = (expected_txn != MC_BUS_WRITEBACK);
            expected_ready_mask = (expected_owner == 0) ? 2'b01 : 2'b10;
            expected_snoop_mask = (expected_owner == 0) ? 2'b10 : 2'b01;
            expected_response_mask = expected_ready_mask;
            expected_shared_mask =
                (requires_snoop && peer_present)
                ? expected_response_mask : 2'b00;
            expected_error_mask =
                expected_memory_error ? expected_response_mask : 2'b00;
            expected_memory_op = mc_line_mem_op_t'(
                ((expected_txn == MC_BUS_WRITEBACK) || peer_dirty)
                ? MC_LINE_WRITE : MC_LINE_READ
            );

            dirty_peer_data = (expected_owner == 0)
                ? 128'he100_e101_e102_e103_e104_e105_e106_e107
                : 128'hd100_d101_d102_d103_d104_d105_d106_d107;
            expected_response_data =
                peer_dirty ? dirty_peer_data : expected_memory_data;
            expected_memory_write_data =
                peer_dirty ? dirty_peer_data : expected_write_data;

            memory_accept_before = memory_accept_count;
            response_0_before    = response_count_0;
            response_1_before    = response_count_1;

            while (l1_req_ready[expected_owner] !== 1'b1) begin
                @(negedge clk);
                check_condition(
                    l1_req_ready[1 - expected_owner] !== 1'b1,
                    "arbiter selected the wrong requester"
                );
            end

            check_condition(l1_req_ready == expected_ready_mask,
                            "request acceptance was not one-hot");

            @(posedge clk);
            #1;
            check_owner(expected_owner);
            check_condition(l1_req_ready == 2'b00,
                            "request remained ready after capture");
            check_condition(l1_rsp_valid == 2'b00,
                            "owner response appeared before completion");

            if (requires_snoop) begin
                check_condition(snoop_valid == expected_snoop_mask,
                                "snoop was not sent only to the nonowner");
                check_condition(snoop_txn == expected_txn,
                                "captured snoop transaction type was incorrect");
                check_condition(snoop_line_addr == expected_line_address,
                                "captured snoop line address was incorrect");
                check_condition(
                    snoop_requester_id == (expected_owner == 1),
                    "snoop requester identity was incorrect"
                );
                check_condition(!memory_req_valid,
                                "downstream request started before snoop completion");
            end else begin
                check_condition(snoop_valid == 2'b00,
                                "write-back incorrectly snooped the peer");
                check_condition(memory_req_valid,
                                "write-back did not issue a direct memory request");
            end

            @(negedge clk);
            l1_req_valid = requests_after_capture;

            if (requires_snoop) begin
                for (delay_index = 0;
                     delay_index < snoop_delay;
                     delay_index = delay_index + 1) begin
                    @(posedge clk);
                    #1;
                    check_owner(expected_owner);
                    check_condition(snoop_valid == expected_snoop_mask,
                                    "snoop request changed before acknowledgement");
                    check_condition(snoop_txn == expected_txn,
                                    "snoop transaction changed before acknowledgement");
                    check_condition(snoop_line_addr == expected_line_address,
                                    "snoop address changed before acknowledgement");
                    check_condition(!memory_req_valid,
                                    "memory request preceded snoop acknowledgement");
                    check_condition(l1_rsp_valid == 2'b00,
                                    "response appeared before snoop acknowledgement");
                end

                @(negedge clk);
                snoop_rsp_valid      = expected_snoop_mask;
                snoop_rsp_present    = peer_present
                                     ? expected_snoop_mask : 2'b00;
                snoop_rsp_dirty      = peer_dirty
                                     ? expected_snoop_mask : 2'b00;
                snoop_rsp_data_valid = 2'b00;
                snoop_rsp_data_0     =
                    128'hd100_d101_d102_d103_d104_d105_d106_d107;
                snoop_rsp_data_1     =
                    128'he100_e101_e102_e103_e104_e105_e106_e107;

                check_condition(!memory_req_valid,
                                "memory request was active before snoop response");

                if (peer_dirty) begin
                    repeat (2) begin
                        @(posedge clk);
                        #1;
                        check_owner(expected_owner);
                        check_condition(snoop_valid == expected_snoop_mask,
                                        "dirty snoop was not held while data was invalid");
                        check_condition(snoop_txn == expected_txn,
                                        "dirty snoop transaction changed while waiting for data");
                        check_condition(snoop_line_addr == expected_line_address,
                                        "dirty snoop address changed while waiting for data");
                        check_condition(!memory_req_valid,
                                        "dirty line was written before data-valid");
                        check_condition(l1_rsp_valid == 2'b00,
                                        "response appeared before dirty data-valid");
                    end

                    @(negedge clk);
                    snoop_rsp_data_valid = expected_snoop_mask;
                end

                @(posedge clk);
                #1;
                check_owner(expected_owner);
                check_condition(snoop_valid == 2'b00,
                                "snoop remained active after complete acknowledgement");
                check_condition(memory_req_valid,
                                "memory request did not follow snoop completion");

                @(negedge clk);
                snoop_rsp_valid      = 2'b00;
                snoop_rsp_present    = 2'b00;
                snoop_rsp_dirty      = 2'b00;
                snoop_rsp_data_valid = 2'b00;
            end

            check_condition(memory_req_valid,
                            "downstream memory request was not asserted");
            check_condition(memory_req_op == expected_memory_op,
                            "downstream operation type was incorrect");
            check_condition(memory_req_line_addr == expected_line_address,
                            "downstream line address was incorrect");
            check_condition(memory_req_wdata == expected_memory_write_data,
                            "downstream write data was incorrect");
            check_condition(l1_rsp_valid == 2'b00,
                            "owner response appeared before memory completion");

            held_memory_address    = memory_req_line_addr;
            held_memory_write_data = memory_req_wdata;

            for (delay_index = 0;
                 delay_index < memory_accept_delay;
                 delay_index = delay_index + 1) begin
                @(posedge clk);
                #1;
                check_owner(expected_owner);
                check_condition(memory_req_valid,
                                "memory request_valid dropped before acceptance");
                check_condition(memory_req_op == expected_memory_op,
                                "memory operation changed before acceptance");
                check_condition(memory_req_line_addr == held_memory_address,
                                "memory address changed before acceptance");
                check_condition(memory_req_wdata == held_memory_write_data,
                                "memory write data changed before acceptance");
                check_condition(l1_rsp_valid == 2'b00,
                                "response appeared before memory acceptance");
            end

            @(negedge clk);
            memory_req_ready = 1'b1;

            @(posedge clk);
            #1;
            check_owner(expected_owner);
            check_condition(!memory_req_valid,
                            "memory request remained valid after acceptance");

            @(negedge clk);
            memory_req_ready = 1'b0;

            for (delay_index = 0;
                 delay_index < memory_response_delay;
                 delay_index = delay_index + 1) begin
                @(posedge clk);
                #1;
                check_owner(expected_owner);
                check_condition(!memory_req_valid,
                                "memory request was reissued while awaiting response");
                check_condition(l1_rsp_valid == 2'b00,
                                "owner response appeared before memory completion");
            end

            @(negedge clk);
            memory_rsp_rdata = expected_memory_data;
            memory_rsp_error = expected_memory_error;
            memory_rsp_valid = 1'b1;

            @(posedge clk);
            #1;
            check_owner(expected_owner);
            check_condition(l1_rsp_valid == expected_response_mask,
                            "final response was not routed only to the owner");
            check_condition(l1_rsp_shared == expected_shared_mask,
                            "final shared-line indication was incorrect");
            check_condition(l1_rsp_error == expected_error_mask,
                            "final response error indication was incorrect");

            if (expected_owner == 0) begin
                check_condition(l1_rsp_data_0 == expected_response_data,
                                "response data did not reach requester 0");
                check_condition(l1_rsp_data_1 == {MC_LINE_WIDTH{1'b0}},
                                "response data was exposed to nonowner 1");
            end else begin
                check_condition(l1_rsp_data_1 == expected_response_data,
                                "response data did not reach requester 1");
                check_condition(l1_rsp_data_0 == {MC_LINE_WIDTH{1'b0}},
                                "response data was exposed to nonowner 0");
            end

            @(negedge clk);
            memory_rsp_valid = 1'b0;
            memory_rsp_error = 1'b0;

            @(posedge clk);
            #1;
            check_condition(l1_rsp_valid == 2'b00,
                            "final response lasted more than one cycle");
            check_condition(memory_accept_count == memory_accept_before + 1,
                            "downstream request acceptance count was incorrect");

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

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            memory_accept_count <= 0;
            response_count_0    <= 0;
            response_count_1    <= 0;
        end else begin
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
                (dut.arb_grant == 2'b00) ||
                (dut.arb_grant == 2'b01) ||
                (dut.arb_grant == 2'b10),
                "arbiter grant was not one-hot-or-zero"
            );
            check_condition(
                (l1_rsp_valid == 2'b00) ||
                (l1_rsp_valid == 2'b01) ||
                (l1_rsp_valid == 2'b10),
                "bus response-valid was not one-hot-or-zero"
            );
        end
    end

    initial begin
        #500000;
        $display("ERROR: timeout waiting for shared-bus regression");
        $display("FAIL: tb_shared_bus");
        $fatal(1, "tb_shared_bus timed out");
    end

    initial begin
        clk                      = 1'b0;
        rst                      = 1'b1;
        error_count              = 0;
        l1_req_valid             = 2'b00;
        l1_req_txn_0             = MC_BUS_RD;
        l1_req_txn_1             = MC_BUS_RD;
        l1_req_line_addr_0       = {MC_ADDR_WIDTH{1'b0}};
        l1_req_line_addr_1       = {MC_ADDR_WIDTH{1'b0}};
        l1_req_wdata_0           = {MC_LINE_WIDTH{1'b0}};
        l1_req_wdata_1           = {MC_LINE_WIDTH{1'b0}};
        snoop_rsp_valid          = 2'b00;
        snoop_rsp_present        = 2'b00;
        snoop_rsp_dirty          = 2'b00;
        snoop_rsp_data_valid     = 2'b00;
        snoop_rsp_data_0         = {MC_LINE_WIDTH{1'b0}};
        snoop_rsp_data_1         = {MC_LINE_WIDTH{1'b0}};
        memory_req_ready         = 1'b0;
        memory_rsp_valid         = 1'b0;
        memory_rsp_rdata         = {MC_LINE_WIDTH{1'b0}};
        memory_rsp_error         = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        check_condition(l1_req_ready == 2'b00,
                        "request was accepted during reset");
        check_condition(l1_rsp_valid == 2'b00,
                        "response was asserted during reset");
        check_condition(snoop_valid == 2'b00,
                        "snoop was asserted during reset");
        check_condition(!memory_req_valid,
                        "memory request was asserted during reset");
        check_condition(dut.arb_grant == 2'b00,
                        "arbiter grant was active during reset");

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;
        check_condition(l1_req_ready == 2'b00,
                        "idle bus exposed request readiness without a request");
        check_condition(l1_rsp_valid == 2'b00,
                        "idle bus exposed a response");
        check_condition(snoop_valid == 2'b00,
                        "idle bus exposed a snoop");
        check_condition(!memory_req_valid,
                        "idle bus exposed a memory request");

        // Requester 0 BusRd: delayed snoop and memory, peer reports shared.
        @(negedge clk);
        configure_request(
            0,
            MC_BUS_RD,
            32'h0000_1000,
            128'h00000000_00000000_00000000_00000000
        );
        service_transaction(
            0,
            MC_BUS_RD,
            32'h0000_1000,
            128'h00000000_00000000_00000000_00000000,
            2'b00,
            3,
            1'b1,
            1'b0,
            3,
            4,
            128'h00112233_44556677_8899aabb_ccddeeff,
            1'b0
        );

        // Requester 1 BusRdX: peer acknowledgement precedes a line read.
        @(negedge clk);
        configure_request(
            1,
            MC_BUS_RDX,
            32'h0000_2000,
            128'h00000000_00000000_00000000_00000000
        );
        service_transaction(
            1,
            MC_BUS_RDX,
            32'h0000_2000,
            128'h00000000_00000000_00000000_00000000,
            2'b00,
            2,
            1'b0,
            1'b0,
            2,
            3,
            128'h10213243_54657687_98a9bacb_dcedfe0f,
            1'b0
        );

        // Explicit write-back forwards the owner's complete line.
        @(negedge clk);
        configure_request(
            0,
            MC_BUS_WRITEBACK,
            32'h0000_3000,
            128'hfeed0000_feed1111_feed2222_feed3333
        );
        service_transaction(
            0,
            MC_BUS_WRITEBACK,
            32'h0000_3000,
            128'hfeed0000_feed1111_feed2222_feed3333,
            2'b00,
            1,
            1'b0,
            1'b0,
            2,
            2,
            128'h00000000_00000000_00000000_00000000,
            1'b0
        );

        // Dirty peer data is flushed to memory and forwarded to the requester.
        @(negedge clk);
        configure_request(
            1,
            MC_BUS_RD,
            32'h0000_4000,
            128'h00000000_00000000_00000000_00000000
        );
        service_transaction(
            1,
            MC_BUS_RD,
            32'h0000_4000,
            128'h00000000_00000000_00000000_00000000,
            2'b00,
            2,
            1'b1,
            1'b1,
            0,
            0,
            128'h00000000_00000000_00000000_00000000,
            1'b0
        );

        // Both requesters remain active across completions: 0, then 1, then 0.
        @(negedge clk);
        configure_request(
            0,
            MC_BUS_RD,
            32'h0000_5000,
            128'h00000000_00000000_00000000_00000000
        );
        configure_request(
            1,
            MC_BUS_RD,
            32'h0000_6000,
            128'h00000000_00000000_00000000_00000000
        );

        service_transaction(
            0, MC_BUS_RD, 32'h0000_5000,
            128'h00000000_00000000_00000000_00000000,
            2'b11, 1, 1'b0, 1'b0, 1, 1,
            128'h50005000_50005000_50005000_50005000, 1'b0
        );
        service_transaction(
            1, MC_BUS_RD, 32'h0000_6000,
            128'h00000000_00000000_00000000_00000000,
            2'b11, 1, 1'b0, 1'b0, 1, 1,
            128'h60006000_60006000_60006000_60006000, 1'b0
        );
        service_transaction(
            0, MC_BUS_RD, 32'h0000_5000,
            128'h00000000_00000000_00000000_00000000,
            2'b00, 1, 1'b0, 1'b0, 1, 1,
            128'h50505050_50505050_50505050_50505050, 1'b0
        );

        @(negedge clk);
        #1;
        check_condition(dut.arb_grant == 2'b00,
                        "arbiter retained ownership after all requests completed");
        check_condition(l1_rsp_valid == 2'b00,
                        "bus generated a duplicate final response");
        check_condition(memory_accept_count == 7,
                        "unexpected total downstream acceptance count");
        check_condition(response_count_0 == 4,
                        "requester 0 response count was incorrect");
        check_condition(response_count_1 == 3,
                        "requester 1 response count was incorrect");

        if (error_count == 0) begin
            $display("PASS: tb_shared_bus");
            $finish;
        end else begin
            $display("FAIL: tb_shared_bus");
            $fatal(1, "shared-bus regression failed with %0d error(s)",
                   error_count);
        end
    end
endmodule
