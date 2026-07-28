module tb_rr_arbiter;
    timeunit 1ns;
    timeprecision 1ps;

    logic       clk;
    logic       rst;
    logic [1:0] req;
    logic       txn_done;
    logic [1:0] grant;

    integer error_count;
    logic [1:0] grant_before_edge;
    logic       done_at_edge;

    rr_arbiter dut (
        .clk(clk),
        .rst(rst),
        .req(req),
        .txn_done(txn_done),
        .grant(grant)
    );

    always begin
        #5 clk = ~clk;
    end

    task automatic record_error;
        input string message;
        begin
            error_count = error_count + 1;
            $display("ERROR: %s", message);
        end
    endtask

    task automatic expect_grant;
        input logic [1:0] expected;
        input string check_message;
        begin
            if (grant !== expected) begin
                error_count = error_count + 1;
                $display(
                    "ERROR: %s: expected grant=%02b, actual grant=%02b",
                    check_message, expected, grant
                );
            end
        end
    endtask

    task automatic drive_cycle;
        input logic [1:0] next_req;
        input logic       next_done;
        input logic [1:0] expected_grant;
        input string      check_message;
        begin
            @(negedge clk);
            req      = next_req;
            txn_done = next_done;
            @(posedge clk);
            #1;
            expect_grant(expected_grant, check_message);
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            grant_before_edge = grant;
            done_at_edge      = txn_done;
            #1;

            if ((grant !== 2'b00) &&
                (grant !== 2'b01) &&
                (grant !== 2'b10))
                record_error("grant was not one-hot-or-zero");

            if ((grant_before_edge != 2'b00) &&
                !done_at_edge &&
                (grant !== grant_before_edge))
                record_error("ownership changed before transaction completion");
        end
    end

    initial begin
        #100000;
        $display("ERROR: timeout waiting for round-robin arbiter regression");
        $display("FAIL: tb_rr_arbiter");
        $fatal(1, "tb_rr_arbiter timed out");
    end

    initial begin
        clk         = 1'b0;
        rst         = 1'b1;
        req         = 2'b11;
        txn_done    = 1'b0;
        error_count = 0;

        #1;
        expect_grant(2'b00, "asynchronous reset did not clear the grant");

        repeat (2) begin
            @(posedge clk);
            #1;
            expect_grant(2'b00, "grant was active while reset was asserted");
        end

        @(negedge clk);
        rst      = 1'b0;
        req      = 2'b00;
        txn_done = 1'b0;

        @(posedge clk);
        #1;
        expect_grant(2'b00, "idle grant after reset");

        drive_cycle(2'b00, 1'b0, 2'b00, "no requests");
        drive_cycle(2'b01, 1'b0, 2'b01, "requester 0 only");
        drive_cycle(2'b01, 1'b0, 2'b01,
                    "requester 0 grant was not retained");
        drive_cycle(2'b00, 1'b0, 2'b01,
                    "requester 0 withdrawal changed ownership");
        drive_cycle(2'b00, 1'b1, 2'b00,
                    "requester 0 completion did not return to idle");

        drive_cycle(2'b10, 1'b0, 2'b10, "requester 1 only");
        drive_cycle(2'b10, 1'b0, 2'b10,
                    "requester 1 grant was not retained");
        drive_cycle(2'b00, 1'b1, 2'b00,
                    "requester 1 completion did not return to idle");

        // Reassert reset to verify requester 0 is the initial tie winner.
        @(negedge clk);
        rst      = 1'b1;
        req      = 2'b11;
        txn_done = 1'b0;
        #1;
        expect_grant(2'b00, "reset did not clear an idle grant");

        @(negedge clk);
        rst      = 1'b0;
        req      = 2'b00;
        txn_done = 1'b0;

        @(posedge clk);
        #1;
        expect_grant(2'b00, "grant was not idle after reset release");

        drive_cycle(2'b11, 1'b0, 2'b01,
                    "requester 0 did not win the initial tie");
        drive_cycle(2'b01, 1'b0, 2'b01,
                    "ungranted requester withdrawal changed ownership");
        drive_cycle(2'b10, 1'b0, 2'b01,
                    "owner withdrawal changed ownership before completion");
        drive_cycle(2'b11, 1'b0, 2'b01,
                    "grant changed while transaction remained active");

        // Continuous contention must alternate at every completion boundary.
        drive_cycle(2'b11, 1'b1, 2'b10,
                    "requester 1 did not win after requester 0 completed");
        drive_cycle(2'b11, 1'b0, 2'b10,
                    "requester 1 ownership was not retained");
        drive_cycle(2'b11, 1'b1, 2'b01,
                    "requester 0 did not win after requester 1 completed");
        drive_cycle(2'b11, 1'b1, 2'b10,
                    "continuous contention did not alternate to requester 1");
        drive_cycle(2'b11, 1'b1, 2'b01,
                    "continuous contention did not alternate to requester 0");

        // With no competing request, the same owner may start another transaction.
        drive_cycle(2'b01, 1'b1, 2'b01,
                    "sole requester 0 did not reacquire after completion");
        drive_cycle(2'b01, 1'b1, 2'b01,
                    "requester 0 could not perform repeated transactions");
        drive_cycle(2'b00, 1'b1, 2'b00,
                    "final completion did not clear the grant");
        drive_cycle(2'b00, 1'b0, 2'b00,
                    "grant became active without a request");

        @(negedge clk);

        if (error_count == 0) begin
            $display("PASS: tb_rr_arbiter");
            $finish;
        end else begin
            $display("FAIL: tb_rr_arbiter");
            $fatal(1, "round-robin arbiter regression failed with %0d error(s)",
                   error_count);
        end
    end
endmodule
