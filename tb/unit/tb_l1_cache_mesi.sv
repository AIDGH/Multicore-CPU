`timescale 1ns/1ps

module tb_l1_cache_mesi;

    // ==========================================
    // Clock & Reset
    // ==========================================
    logic clk;
    logic rst_n;

    always #5 clk = ~clk; // 100MHz Clock

    // ==========================================
    // DUT Signals
    // ==========================================
    // Core Interface
    logic        data_req_valid;
    logic        data_req_ready;
    logic [31:0] data_req_addr;
    logic        data_req_write;
    logic [31:0] data_req_wdata;
    logic        data_rsp_valid;
    logic [31:0] data_rsp_rdata;
    logic        data_rsp_error;
    logic        cancel_reservation;

    // Bus Interface
    logic        bus_req;
    logic        bus_req_rdx;
    logic [31:0] bus_req_addr;
    logic        bus_gnt;
    logic        bus_rsp_valid;
    logic [127:0] bus_rsp_rdata;

    // Snoop Interface
    logic        snoop_valid;
    logic [31:0] snoop_addr;
    logic        snoop_rdx;
    logic        snoop_shared;
    logic        snoop_flush;
    logic [127:0] snoop_wdata;

    // ==========================================
    // Instantiate DUT (Device Under Test)
    // ==========================================
    l1_cache_mesi dut (
        .clk(clk),
        .rst_n(rst_n),
        .* // Auto-connect matching signal names
    );

    // ==========================================
    // Test Tasks
    // ==========================================
    // Task: CPU Reads Data
    task cpu_read(input [31:0] addr);
        @(posedge clk);
        data_req_valid <= 1'b1;
        data_req_addr  <= addr;
        data_req_write <= 1'b0;
        
        wait(data_req_ready);
        @(posedge clk);
        data_req_valid <= 1'b0;
        
        wait(data_rsp_valid);
        $display("[%0t] CPU READ  | Addr: 0x%0h | Data: 0x%0h", $time, addr, data_rsp_rdata);
    endtask

    // Task: CPU Writes Data
    task cpu_write(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        data_req_valid <= 1'b1;
        data_req_addr  <= addr;
        data_req_write <= 1'b1;
        data_req_wdata <= data;
        
        wait(data_req_ready);
        @(posedge clk);
        data_req_valid <= 1'b0;
        
        wait(data_rsp_valid);
        $display("[%0t] CPU WRITE | Addr: 0x%0h | Data: 0x%0h", $time, addr, data);
    endtask

    // Simulated Bus Arbiter/Memory Response
    initial begin
        bus_gnt = 0;
        bus_rsp_valid = 0;
        bus_rsp_rdata = '0;
        forever begin
            @(posedge clk);
            if (bus_req) begin
                // Simulate arbitration delay
                repeat(2) @(posedge clk);
                bus_gnt = 1'b1;
                $display("[%0t] BUS ARB   | Granted to Cache | Type: %s | Addr: 0x%0h", 
                         $time, bus_req_rdx ? "BusRdX" : "BusRd", bus_req_addr);
                @(posedge clk);
                bus_gnt = 0;
                
                // Simulate memory fetch delay
                repeat(5) @(posedge clk);
                bus_rsp_valid = 1'b1;
                // Dummy memory data based on address
                bus_rsp_rdata = {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA};
                @(posedge clk);
                bus_rsp_valid = 0;
            end
        end
    end

    // ==========================================
    // Main Test Sequence
    // ==========================================
    initial begin
        // Initialize Signals
        clk = 0;
        rst_n = 0;
        data_req_valid = 0;
        snoop_valid = 0;
        snoop_addr = 0;
        snoop_rdx = 0;

        $display("========================================");
        $display("   Starting MESI L1 Cache Unit Test     ");
        $display("========================================");

        // Reset Sequence
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ---------------------------------------------------------
        // Scenario 1: Clean Miss -> Transition to E
        // ---------------------------------------------------------
        $display("\n--- SCENARIO 1: Clean Read Miss (I -> E) ---");
        // No other cache shares this line
        force dut.snoop_shared = 1'b0; 
        cpu_read(32'h0000_1000);

        // ---------------------------------------------------------
        // Scenario 2: Write Hit on E -> Transition to M
        // ---------------------------------------------------------
        $display("\n--- SCENARIO 2: Write Hit (E -> M) ---");
        // Should happen immediately without bus request
        cpu_write(32'h0000_1004, 32'h1234_5678);

// ---------------------------------------------------------
        // Scenario 3: Snoop Write from other core (M -> I)
        // ---------------------------------------------------------
        $display("\n--- SCENARIO 3: Remote Write Invalidation (M -> I) ---");
        @(posedge clk);
        snoop_valid = 1'b1;
        snoop_rdx   = 1'b1; // Other core wants to write
        snoop_addr  = 32'h0000_1008; // Same block
        
        #1; // Wait 1ps for combinational logic to update
        if (snoop_flush) $display("[%0t] SNOOP     | Cache FLUSHED dirty data to bus!", $time);
        if (cancel_reservation) $display("[%0t] SNOOP     | Cancel Reservation sent to Shahab!", $time);
        
        @(posedge clk);
        snoop_valid = 1'b0;

        // ---------------------------------------------------------
        // Scenario 4: Shared Miss -> Transition to S
        // ---------------------------------------------------------
        $display("\n--- SCENARIO 4: Shared Read Miss (I -> S) ---");
        // Pretend the other cache already has this data
        release dut.snoop_shared;
        force dut.snoop_shared = 1'b1; 
        cpu_read(32'h0000_2000);

        // ---------------------------------------------------------
        // Scenario 5: Write to Shared Line -> Upgrade (S -> M)
        // ---------------------------------------------------------
        $display("\n--- SCENARIO 5: Upgrade Write (S -> M) ---");
        // Must issue BusRdX on the bus first
        cpu_write(32'h0000_2008, 32'hDEAD_BEEF);

        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("           Test Finished!               ");
        $display("   Hits: %0d, Misses: %0d               ", dut.cnt_hits, dut.cnt_misses);
        $display("   Transitions: %0d, Flushes: %0d       ", dut.cnt_state_transitions, dut.cnt_flushes);
        $display("========================================");
        $finish;
    end

endmodule