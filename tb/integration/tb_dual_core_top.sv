`timescale 1ns/1ps
import mc_defs_pkg::*;

module tb_dual_core_top;
    localparam logic [1:0] STATE_I = 2'b00;
    localparam logic [1:0] STATE_S = 2'b01;
    localparam logic [1:0] STATE_E = 2'b10;
    localparam logic [1:0] STATE_M = 2'b11;

    localparam logic [31:0] LOCK_ADDR    = 32'h0000_0010;
    localparam logic [31:0] COUNTER_ADDR = 32'h0000_0020;

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [31:0] core0_instr_in, core0_instr_addr;
    logic [31:0] core1_instr_in, core1_instr_addr;
    logic [31:0] core0_R [0:31];
    logic [31:0] core1_R [0:31];
    logic [31:0] instructions [0:31];

    integer error_count;
    integer cycle_count;
    integer core0_sc_successes;
    integer core1_sc_successes;
    integer core0_sc_failures;
    integer core1_sc_failures;

    always #5 clk = ~clk;

    dual_core_top dut (
        .clk(clk),
        .rst(rst),
        .core0_instr_in(core0_instr_in),
        .core0_instr_addr(core0_instr_addr),
        .core1_instr_in(core1_instr_in),
        .core1_instr_addr(core1_instr_addr),
        .core0_R(core0_R),
        .core1_R(core1_R)
    );

    function automatic [31:0] ITYPE(
        input [5:0] opcode,
        input [4:0] rs,
        input [4:0] rt,
        input [15:0] imm
    );
        ITYPE = {opcode, rs, rt, imm};
    endfunction

    function automatic [31:0] ATYPE(
        input [5:0] opcode,
        input [4:0] rs,
        input [4:0] rt,
        input [4:0] rd,
        input [5:0] funct
    );
        ATYPE = {opcode, rs, rt, rd, 5'b0, funct};
    endfunction

    function automatic [31:0] JTYPE(
        input [5:0] opcode,
        input [25:0] address
    );
        JTYPE = {opcode, address};
    endfunction

    function automatic [31:0] line_word(
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

    assign core0_instr_in = instructions[core0_instr_addr[4:0]];
    assign core1_instr_in = instructions[core1_instr_addr[4:0]];

    always @(posedge clk) begin
        if (rst) begin
            cycle_count        <= 0;
            core0_sc_successes <= 0;
            core1_sc_successes <= 0;
            core0_sc_failures  <= 0;
            core1_sc_failures  <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (dut.u_core0.sc_response_success) begin
                if (dut.u_core0.final_sc_success)
                    core0_sc_successes <= core0_sc_successes + 1;
                else
                    core0_sc_failures <= core0_sc_failures + 1;
            end else if (dut.u_core0.is_sc && dut.u_core0.sc_fail_local &&
                         (dut.u_core0.mem_state == 2'd0)) begin
                core0_sc_failures <= core0_sc_failures + 1;
            end

            if (dut.u_core1.sc_response_success) begin
                if (dut.u_core1.final_sc_success)
                    core1_sc_successes <= core1_sc_successes + 1;
                else
                    core1_sc_failures <= core1_sc_failures + 1;
            end else if (dut.u_core1.is_sc && dut.u_core1.sc_fail_local &&
                         (dut.u_core1.mem_state == 2'd0)) begin
                core1_sc_failures <= core1_sc_failures + 1;
            end
        end
    end

    initial begin
        #500000;
        $display("ERROR: timeout waiting for dual-core integration regression");
        $display("FAIL: tb_dual_core_top");
        $fatal(1, "tb_dual_core_top timed out");
    end

    initial begin : run_test
        integer i;
        integer wait_cycles;
        logic c0_counter_valid;
        logic c1_counter_valid;
        logic c0_lock_valid;
        logic c1_lock_valid;
        logic [31:0] counter_value;
        logic [31:0] lock_value;

        error_count = 0;

        for (i = 0; i < 32; i = i + 1)
            instructions[i] = JTYPE(6'b000010, 26'd13);

        // Both cores execute the same program.  CPUID proves that the two
        // architectural core IDs are distinct.  Each core then acquires an
        // LR/SC spinlock, increments the shared counter once, releases the
        // lock, sets R7 as its completion flag, and halts in a self-loop.
        instructions[0]  = ATYPE(6'b011111, 5'd0, 5'd0, 5'd6, 6'b000000); // cpuid R6
        instructions[1]  = ITYPE(6'b001000, 5'd0, 5'd1, LOCK_ADDR[15:0]);
        instructions[2]  = ITYPE(6'b001000, 5'd0, 5'd5, COUNTER_ADDR[15:0]);
        instructions[3]  = ATYPE(6'b010111, 5'd1, 5'd0, 5'd2, 6'b000010); // lr.w R2,(R1)
        instructions[4]  = ITYPE(6'b000101, 5'd2, 5'd0, 16'hFFFE);        // bne R2,R0,-2
        instructions[5]  = ITYPE(6'b001000, 5'd0, 5'd3, 16'd1);
        instructions[6]  = ATYPE(6'b010111, 5'd1, 5'd3, 5'd3, 6'b000011); // sc.w R3,(R1)
        instructions[7]  = ITYPE(6'b000101, 5'd3, 5'd0, 16'hFFFB);        // bne R3,R0,-5
        instructions[8]  = ITYPE(6'b100011, 5'd5, 5'd4, 16'd0);
        instructions[9]  = ITYPE(6'b001000, 5'd4, 5'd4, 16'd1);
        instructions[10] = ITYPE(6'b101011, 5'd5, 5'd4, 16'd0);
        instructions[11] = ITYPE(6'b101011, 5'd1, 5'd0, 16'd0);
        instructions[12] = ITYPE(6'b001000, 5'd0, 5'd7, 16'd1);
        instructions[13] = JTYPE(6'b000010, 26'd13);

        $dumpfile("build/dual_core_top/waves.vcd");
        $dumpvars(0, tb_dual_core_top);
        $display("Starting self-checking dual-core LR/SC spinlock test...");

        repeat (3) @(posedge clk);
        // shared_memory intentionally does not clear its storage on reset.
        // Initialize the two shared lines deterministically before release.
        dut.u_interconnect.memory.storage[1] = 128'd0;
        dut.u_interconnect.memory.storage[2] = 128'd0;

        @(negedge clk);
        rst = 1'b0;

        wait_cycles = 0;
        while (((core0_R[7] != 32'd1) || (core1_R[7] != 32'd1)) &&
               (wait_cycles < 5000)) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end

        check_condition(wait_cycles < 5000,
                        "both cores did not complete the spinlock program");

        repeat (5) @(posedge clk);
        @(negedge clk);

        check_condition(core0_R[6] == 32'd0, "core 0 CPUID result was not 0");
        check_condition(core1_R[6] == 32'd1, "core 1 CPUID result was not 1");
        check_condition(core0_sc_successes == 1,
                        "core 0 did not commit exactly one successful SC");
        check_condition(core1_sc_successes == 1,
                        "core 1 did not commit exactly one successful SC");
        check_condition((core0_sc_failures + core1_sc_failures) >= 1,
                        "the contended spinlock did not exercise an SC failure/retry");

        c0_counter_valid = (dut.u_cache0.state_array[2] != STATE_I) &&
                           (dut.u_cache0.tag_array[2] == '0);
        c1_counter_valid = (dut.u_cache1.state_array[2] != STATE_I) &&
                           (dut.u_cache1.tag_array[2] == '0);
        c0_lock_valid = (dut.u_cache0.state_array[1] != STATE_I) &&
                        (dut.u_cache0.tag_array[1] == '0);
        c1_lock_valid = (dut.u_cache1.state_array[1] != STATE_I) &&
                        (dut.u_cache1.tag_array[1] == '0);

        if (c0_counter_valid)
            counter_value = line_word(dut.u_cache0.data_array[2], 2'd0);
        else if (c1_counter_valid)
            counter_value = line_word(dut.u_cache1.data_array[2], 2'd0);
        else
            counter_value = line_word(dut.u_interconnect.memory.storage[2], 2'd0);

        if (c0_lock_valid)
            lock_value = line_word(dut.u_cache0.data_array[1], 2'd0);
        else if (c1_lock_valid)
            lock_value = line_word(dut.u_cache1.data_array[1], 2'd0);
        else
            lock_value = line_word(dut.u_interconnect.memory.storage[1], 2'd0);

        check_condition(counter_value == 32'd2,
                        "shared counter was not incremented exactly twice");
        check_condition(lock_value == 32'd0,
                        "spinlock was not released at program completion");

        if (c0_counter_valid && c1_counter_valid) begin
            check_condition(
                line_word(dut.u_cache0.data_array[2], 2'd0) ==
                line_word(dut.u_cache1.data_array[2], 2'd0),
                "valid counter copies disagree between the two caches"
            );
        end

        if (c0_lock_valid && c1_lock_valid) begin
            check_condition(
                line_word(dut.u_cache0.data_array[1], 2'd0) ==
                line_word(dut.u_cache1.data_array[1], 2'd0),
                "valid lock copies disagree between the two caches"
            );
        end

        check_condition(!((dut.u_cache0.state_array[2] == STATE_M ||
                           dut.u_cache0.state_array[2] == STATE_E) &&
                          (dut.u_cache1.state_array[2] != STATE_I)),
                        "cache 0 has exclusive counter ownership while cache 1 is valid");
        check_condition(!((dut.u_cache1.state_array[2] == STATE_M ||
                           dut.u_cache1.state_array[2] == STATE_E) &&
                          (dut.u_cache0.state_array[2] != STATE_I)),
                        "cache 1 has exclusive counter ownership while cache 0 is valid");

        $display("RESULT: cycles=%0d counter=%0d lock=%0d", cycle_count,
                 counter_value, lock_value);
        $display("RESULT: core0_sc_success=%0d core0_sc_fail=%0d",
                 core0_sc_successes, core0_sc_failures);
        $display("RESULT: core1_sc_success=%0d core1_sc_fail=%0d",
                 core1_sc_successes, core1_sc_failures);
        $display("RESULT: cache0 hit=%0d miss=%0d flush=%0d invalidation=%0d transitions=%0d",
                 dut.u_cache0.cnt_hits, dut.u_cache0.cnt_misses,
                 dut.u_cache0.cnt_flushes, dut.u_cache0.cnt_invalidations,
                 dut.u_cache0.cnt_state_transitions);
        $display("RESULT: cache1 hit=%0d miss=%0d flush=%0d invalidation=%0d transitions=%0d",
                 dut.u_cache1.cnt_hits, dut.u_cache1.cnt_misses,
                 dut.u_cache1.cnt_flushes, dut.u_cache1.cnt_invalidations,
                 dut.u_cache1.cnt_state_transitions);

        if (error_count == 0) begin
            $display("PASS: tb_dual_core_top");
            $finish;
        end else begin
            $display("FAIL: tb_dual_core_top");
            $fatal(1, "dual-core integration regression failed");
        end
    end
endmodule
