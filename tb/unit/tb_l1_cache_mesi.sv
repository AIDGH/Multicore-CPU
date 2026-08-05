`timescale 1ns/1ps
import mc_defs_pkg::*;

module tb_l1_cache_mesi;
    localparam logic [2:0] OP_LOAD   = 3'd0;
    localparam logic [2:0] OP_STORE  = 3'd1;
    localparam logic [2:0] OP_LR     = 3'd2;
    localparam logic [2:0] OP_SC     = 3'd3;
    localparam logic [2:0] OP_AMOADD = 3'd4;

    localparam logic [1:0] STATE_I = 2'b00;
    localparam logic [1:0] STATE_S = 2'b01;
    localparam logic [1:0] STATE_E = 2'b10;
    localparam logic [1:0] STATE_M = 2'b11;

    logic clk;
    logic rst_n;

    logic         data_req_valid;
    logic         data_req_ready;
    logic [31:0]  data_req_addr;
    logic [2:0]   data_req_op;
    logic [31:0]  data_req_wdata;
    logic         data_rsp_valid;
    logic [31:0]  data_rsp_rdata;
    logic         data_rsp_error;
    logic         cancel_reservation;

    logic         bus_req;
    mc_bus_txn_t  bus_req_txn;
    logic [31:0]  bus_req_addr;
    logic [127:0] bus_req_wdata;
    logic         bus_gnt;
    logic         bus_rsp_valid;
    logic [127:0] bus_rsp_rdata;
    logic         bus_rsp_shared;
    logic         bus_rsp_error;

    logic         snoop_valid;
    mc_bus_txn_t  snoop_txn;
    logic [31:0]  snoop_addr;
    logic         snoop_rsp_valid;
    logic         snoop_shared;
    logic         snoop_flush;
    logic [127:0] snoop_wdata;

    logic [127:0] memory [0:255];
    logic         next_read_shared;

    typedef enum logic [1:0] {
        BM_IDLE,
        BM_WAIT,
        BM_RESPOND
    } bus_model_state_t;

    bus_model_state_t bus_model_state;
    mc_bus_txn_t      accepted_txn;
    logic [31:0]      accepted_addr;
    logic [127:0]     accepted_wdata;
    logic             accepted_shared;
    integer           wait_count;

    integer error_count;
    integer request_count;
    integer read_count;
    integer rdx_count;
    integer writeback_count;
    logic [31:0]  last_writeback_addr;
    logic [127:0] last_writeback_data;

    l1_cache_mesi dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_req_valid(data_req_valid),
        .data_req_ready(data_req_ready),
        .data_req_addr(data_req_addr),
        .data_req_op(data_req_op),
        .data_req_wdata(data_req_wdata),
        .data_rsp_valid(data_rsp_valid),
        .data_rsp_rdata(data_rsp_rdata),
        .data_rsp_error(data_rsp_error),
        .cancel_reservation(cancel_reservation),
        .bus_req(bus_req),
        .bus_req_txn(bus_req_txn),
        .bus_req_addr(bus_req_addr),
        .bus_req_wdata(bus_req_wdata),
        .bus_gnt(bus_gnt),
        .bus_rsp_valid(bus_rsp_valid),
        .bus_rsp_rdata(bus_rsp_rdata),
        .bus_rsp_shared(bus_rsp_shared),
        .bus_rsp_error(bus_rsp_error),
        .snoop_valid(snoop_valid),
        .snoop_txn(snoop_txn),
        .snoop_addr(snoop_addr),
        .snoop_rsp_valid(snoop_rsp_valid),
        .snoop_shared(snoop_shared),
        .snoop_flush(snoop_flush),
        .snoop_wdata(snoop_wdata)
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] line_word(
        input logic [127:0] line,
        input logic [1:0] word_index
    );
        case (word_index)
            2'd0: line_word = line[31:0];
            2'd1: line_word = line[63:32];
            2'd2: line_word = line[95:64];
            default: line_word = line[127:96];
        endcase
    endfunction

    task automatic check_condition(
        input logic condition,
        input string message
    );
        begin
            if (!condition) begin
                error_count = error_count + 1;
                $display("ERROR: %s", message);
            end
        end
    endtask

    task automatic issue_request(
        input logic [2:0] op,
        input logic [31:0] address,
        input logic [31:0] write_data,
        output logic [31:0] response_data
    );
        integer timeout;
        begin
            timeout = 0;
            while (!data_req_ready && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check_condition(timeout < 100, "cache did not become ready");

            @(negedge clk);
            data_req_valid = 1'b1;
            data_req_op = op;
            data_req_addr = address;
            data_req_wdata = write_data;

            @(posedge clk);
            @(negedge clk);
            data_req_valid = 1'b0;

            timeout = 0;
            while (!data_rsp_valid && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            check_condition(timeout < 200, "cache response timed out");
            check_condition(!data_rsp_error, "cache returned an unexpected error");
            response_data = data_rsp_rdata;

            @(negedge clk);
        end
    endtask

    task automatic drive_snoop(
        input mc_bus_txn_t txn,
        input logic [31:0] address
    );
        begin
            @(negedge clk);
            snoop_valid = 1'b1;
            snoop_txn = txn;
            snoop_addr = address;
            #1;
            check_condition(snoop_rsp_valid, "snoop acknowledgement was not asserted");
            @(posedge clk);
            @(negedge clk);
            snoop_valid = 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_model_state <= BM_IDLE;
            bus_gnt <= 1'b0;
            bus_rsp_valid <= 1'b0;
            bus_rsp_rdata <= '0;
            bus_rsp_shared <= 1'b0;
            bus_rsp_error <= 1'b0;
            accepted_txn <= MC_BUS_RD;
            accepted_addr <= '0;
            accepted_wdata <= '0;
            accepted_shared <= 1'b0;
            wait_count <= 0;
            request_count <= 0;
            read_count <= 0;
            rdx_count <= 0;
            writeback_count <= 0;
            last_writeback_addr <= '0;
            last_writeback_data <= '0;
        end else begin
            bus_gnt <= 1'b0;
            bus_rsp_valid <= 1'b0;
            bus_rsp_error <= 1'b0;

            case (bus_model_state)
                BM_IDLE: begin
                    if (bus_req) begin
                        accepted_txn <= bus_req_txn;
                        accepted_addr <= {bus_req_addr[31:4], 4'b0000};
                        accepted_wdata <= bus_req_wdata;
                        accepted_shared <= next_read_shared;
                        request_count <= request_count + 1;

                        if (bus_req_txn == MC_BUS_RD)
                            read_count <= read_count + 1;
                        else if (bus_req_txn == MC_BUS_RDX)
                            rdx_count <= rdx_count + 1;
                        else begin
                            writeback_count <= writeback_count + 1;
                            last_writeback_addr <= {bus_req_addr[31:4], 4'b0000};
                            last_writeback_data <= bus_req_wdata;
                        end

                        bus_gnt <= 1'b1;
                        wait_count <= 2;
                        bus_model_state <= BM_WAIT;
                    end
                end

                BM_WAIT: begin
                    if (wait_count != 0) begin
                        wait_count <= wait_count - 1;
                    end else begin
                        bus_rsp_shared <= accepted_shared;

                        if (accepted_txn == MC_BUS_WRITEBACK) begin
                            memory[accepted_addr[11:4]] <= accepted_wdata;
                            bus_rsp_rdata <= '0;
                        end else begin
                            bus_rsp_rdata <= memory[accepted_addr[11:4]];
                        end

                        bus_rsp_valid <= 1'b1;
                        bus_model_state <= BM_RESPOND;
                    end
                end

                BM_RESPOND: begin
                    bus_rsp_shared <= 1'b0;
                    bus_model_state <= BM_IDLE;
                end

                default: bus_model_state <= BM_IDLE;
            endcase
        end
    end

    initial begin
        #200000;
        $display("ERROR: timeout waiting for MESI cache regression");
        $display("FAIL: tb_l1_cache_mesi");
        $fatal(1, "tb_l1_cache_mesi timed out");
    end

    initial begin : run_test
        logic [31:0] response_data;
        integer i;

        clk = 1'b0;
        rst_n = 1'b0;
        data_req_valid = 1'b0;
        data_req_addr = '0;
        data_req_op = OP_LOAD;
        data_req_wdata = '0;
        snoop_valid = 1'b0;
        snoop_txn = MC_BUS_RD;
        snoop_addr = '0;
        next_read_shared = 1'b0;
        error_count = 0;

        for (i = 0; i < 256; i = i + 1)
            memory[i] = '0;

        memory[8'h04] = {
            32'h4444_4444,
            32'h3333_3333,
            32'h0000_0014,
            32'h0000_000A
        };
        memory[8'h14] = {
            32'hDDDD_DDDD,
            32'hCCCC_CCCC,
            32'hBBBB_BBBB,
            32'hAAAA_AAAA
        };
        memory[8'h08] = {
            32'h0000_0009,
            32'h0000_0005,
            32'h0000_0002,
            32'h0000_0001
        };
        memory[8'h0C] = {
            32'h0000_0004,
            32'h0000_0003,
            32'h0000_0002,
            32'h0000_0001
        };
        memory[8'h0D] = {
            32'hDDDD_0004,
            32'hDDDD_0003,
            32'hDDDD_0002,
            32'h1111_2222
        };

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        issue_request(OP_LOAD, 32'h0000_0044, 32'd0, response_data);
        check_condition(response_data == 32'h0000_0014,
                        "read miss returned the wrong word");
        check_condition(dut.state_array[4] == STATE_E,
                        "clean private read miss did not enter E");
        check_condition(read_count == 1,
                        "read miss did not issue exactly one BusRd");

        issue_request(OP_AMOADD, 32'h0000_0044, 32'd7, response_data);
        check_condition(response_data == 32'h0000_0014,
                        "AMOADD hit did not return the previous value");
        check_condition(line_word(dut.data_array[4], 2'd1) == 32'h0000_001B,
                        "AMOADD hit did not store old+operand");
        check_condition(dut.state_array[4] == STATE_M,
                        "AMOADD hit did not leave the line in M");
        check_condition(request_count == 1,
                        "AMOADD hit unexpectedly used the bus");

        issue_request(OP_LOAD, 32'h0000_0140, 32'd0, response_data);
        check_condition(response_data == 32'hAAAA_AAAA,
                        "conflicting read miss returned the wrong word");
        check_condition(writeback_count == 1,
                        "dirty eviction did not issue one write-back");
        check_condition(last_writeback_addr == 32'h0000_0040,
                        "dirty eviction used the wrong victim address");
        check_condition(line_word(last_writeback_data, 2'd1) == 32'h0000_001B,
                        "dirty write-back lost the AMOADD result");
        check_condition(line_word(memory[8'h04], 2'd1) == 32'h0000_001B,
                        "dirty victim was not written to memory");

        issue_request(OP_AMOADD, 32'h0000_0088, 32'd3, response_data);
        check_condition(response_data == 32'h0000_0005,
                        "AMOADD miss did not return the previous memory value");
        check_condition(line_word(dut.data_array[8], 2'd2) == 32'h0000_0008,
                        "AMOADD miss did not store old+operand");
        check_condition(dut.state_array[8] == STATE_M,
                        "AMOADD miss did not enter M");
        check_condition(rdx_count >= 1,
                        "AMOADD miss did not issue BusRdX");

        issue_request(OP_LOAD, 32'h0000_0088, 32'd0, response_data);
        check_condition(response_data == 32'h0000_0008,
                        "load after AMOADD did not observe the updated value");

        next_read_shared = 1'b1;
        issue_request(OP_LOAD, 32'h0000_00C0, 32'd0, response_data);
        next_read_shared = 1'b0;
        check_condition(response_data == 32'h0000_0001,
                        "shared read miss returned the wrong value");
        check_condition(dut.state_array[12] == STATE_S,
                        "shared read miss did not enter S");

        issue_request(OP_STORE, 32'h0000_00C0, 32'hDEAD_BEEF, response_data);
        check_condition(line_word(dut.data_array[12], 2'd0) == 32'hDEAD_BEEF,
                        "store upgrade did not update the cache line");
        check_condition(dut.state_array[12] == STATE_M,
                        "store upgrade did not enter M");

        // A remote BusRdX that arrives before an SC commits must make the
        // SC fail without changing the target word.
        next_read_shared = 1'b1;
        issue_request(OP_LOAD, 32'h0000_00D0, 32'd0, response_data);
        next_read_shared = 1'b0;
        check_condition(dut.state_array[13] == STATE_S,
                        "SC cancellation setup did not leave the line in S");

        fork
            begin : issue_cancelled_sc
                issue_request(OP_SC, 32'h0000_00D0, 32'hCAFE_BABE, response_data);
            end
            begin : invalidate_pending_sc
                wait (bus_req && (bus_req_txn == MC_BUS_RDX) &&
                      (bus_req_addr[31:4] == 28'h000000D));
                @(negedge clk);
                snoop_valid = 1'b1;
                snoop_txn = MC_BUS_RDX;
                snoop_addr = 32'h0000_00D0;
                #1;
                check_condition(cancel_reservation,
                                "pending SC invalidation did not cancel the reservation");
                @(posedge clk);
                @(negedge clk);
                snoop_valid = 1'b0;
            end
        join

        check_condition(response_data == 32'd1,
                        "cancelled SC did not return architectural failure (1)");
        check_condition(line_word(dut.data_array[13], 2'd0) == 32'h1111_2222,
                        "cancelled SC modified the cache line");
        check_condition(dut.state_array[13] == STATE_E,
                        "cancelled SC did not retain a clean exclusive line");

        @(negedge clk);
        snoop_valid = 1'b1;
        snoop_txn = MC_BUS_RD;
        snoop_addr = 32'h0000_0080;
        #1;
        check_condition(snoop_rsp_valid, "dirty BusRd snoop was not acknowledged");
        check_condition(snoop_shared, "dirty BusRd snoop did not report presence");
        check_condition(snoop_flush, "dirty BusRd snoop did not report dirty data");
        check_condition(line_word(snoop_wdata, 2'd2) == 32'h0000_0008,
                        "dirty BusRd snoop returned the wrong data");
        @(posedge clk);
        @(negedge clk);
        snoop_valid = 1'b0;
        check_condition(dut.state_array[8] == STATE_S,
                        "dirty BusRd snoop did not downgrade M to S");

        @(negedge clk);
        snoop_valid = 1'b1;
        snoop_txn = MC_BUS_RDX;
        snoop_addr = 32'h0000_0080;
        #1;
        check_condition(cancel_reservation,
                        "remote BusRdX did not cancel the local reservation");
        @(posedge clk);
        @(negedge clk);
        snoop_valid = 1'b0;
        check_condition(dut.state_array[8] == STATE_I,
                        "remote BusRdX did not invalidate the line");

        check_condition(dut.cnt_hits >= 2,
                        "cache hit counter did not advance");
        check_condition(dut.cnt_misses >= 4,
                        "cache miss counter did not advance");
        check_condition(dut.cnt_flushes >= 1,
                        "cache flush counter did not advance");
        check_condition(dut.cnt_invalidations >= 1,
                        "cache invalidation counter did not advance");

        if (error_count == 0) begin
            $display("PASS: tb_l1_cache_mesi");
            $finish;
        end else begin
            $display("FAIL: tb_l1_cache_mesi");
            $fatal(1, "MESI cache regression failed");
        end
    end
endmodule
