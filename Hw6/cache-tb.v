module tb;
    reg clk, rst;
    initial begin
        clk = 0;
        forever #1 clk = ~clk;
    end
    initial begin
        rst = 1;
        #4 rst = 0;
    end

    task rand_wait;
        reg [9:0] wait_time;
        begin
            wait_time = $random;
            #2;
            #(wait_time * 2);
        end
    endtask

    reg mm_done, cpu_write, cpu_read;
    reg [31:0] cpu_data_in, cpu_addr;
    reg [127:0] mm_data_in;
    wire cpu_done, mm_write, mm_read;
    wire [31:0] cpu_data_out, mm_addr;
    wire [127:0] mm_data_out;
    initial begin
        mm_done = 0;
        cpu_write = 0;
        cpu_read = 0;
        cpu_data_in = 0;
        cpu_addr = 0;
        mm_data_in = 0;
    end
    main _main (
        .Clk(clk),
        .Rst(rst),

        .CPU_Addr(cpu_addr),
        .CPU_Read(cpu_read),
        .CPU_Write(cpu_write),
        .CPU_Done(cpu_done),
        .CPU_DataIn(cpu_data_in),
        .CPU_DataOut(cpu_data_out),

        .MM_Addr(mm_addr),
        .MM_Read(mm_read),
        .MM_Write(mm_write),
        .MM_Done(mm_done),
`ifndef LOGISIM
        .MM_DataIn(mm_data_in),
        .MM_DataOut(mm_data_out)
`else
        .MM_DataIn0(mm_data_in[63:0]),
        .MM_DataIn1(mm_data_in[127:64]),
        .MM_DataOut0(mm_data_out[63:0]),
        .MM_DataOut1(mm_data_out[127:64])
`endif
    );


    reg [127:0] mm_lines[1024];
    initial foreach (mm_lines[i]) mm_lines[i] = {$random, $random, $random, $random};

    integer total_evals, failed_evals;
    initial {total_evals, failed_evals} = 0;
    task eval32(input reality_ready, input [31:0] reality, input [31:0] expectation,
                input string message);
        begin
            total_evals += 1;
            if (!(reality_ready === 1)) begin
                $display("t@", $time, " ", message, " => not ready!");
                failed_evals += 1;
            end else if (reality !== expectation) begin
                $display("t@", $time, " ", message, " => Reality: %x | Expectation: %x", reality,
                         expectation);
                failed_evals += 1;
            end
        end
    endtask

    task fatal(input string msg);
        begin
            $display("t@", $time, " ", "FATAL : ", msg);
            $finish(0);
        end
    endtask

    /// memory function
    always @(posedge clk) begin
        if (mm_read && mm_write) fatal("mm_read&mm_write at the same time");

        if (mm_write || mm_read)
            if (mm_addr[3:0] !== 0) fatal("unaligned mm request.\n    hint: mm_addr[3:0] == 0");
        if (mm_read) begin
            mm_done <= 0;
            rand_wait();
            mm_done <= 1;
            mm_data_in <= mm_lines[mm_addr>>4];
            #2;
        end else if (mm_write) begin
            mm_done <= 0;
            rand_wait();
            mm_done <= 1;
            mm_lines[mm_addr>>4] <= mm_data_out;
            #2;
        end
    end

    /// cpu function
    task cpu_read_req(input [31:0] addr);
        integer iter_offset;
        begin
            {cpu_read, cpu_write} <= 'b10;
            cpu_addr <= addr;
            #2;
            // $display("@t", $time, " Read Request @[%x] Initiation", cpu_addr);
            while (!cpu_done) #2;
            {cpu_read, cpu_write} <= 'b00;
            eval32(cpu_done, cpu_data_out, mm_lines[addr>>4][(addr[3:0]*8+31)-:32], $sformatf(
                   "Read Request @[%x]", cpu_addr));
            for (iter_offset = 0; iter_offset < 16; iter_offset += 4) begin
                #2;
                {cpu_read, cpu_write} <= 'b10;
                cpu_addr <= ~((~addr) | 15) + iter_offset;
                #2;
                {cpu_read, cpu_write} <= 'b00;
                eval32(cpu_done, cpu_data_out, mm_lines[addr>>4][(iter_offset*8+31)-:32], $sformatf(
                       "Read Request @[%x]", cpu_addr));
            end
            #2;
        end
    endtask

    task cpu_write_req(input [31:0] addr, new_data);
        integer iter_offset;
        begin
            {cpu_read, cpu_write} <= 'b01;
            cpu_addr <= addr;
            cpu_data_in <= new_data;
            #2;
            // $display("@t", $time, " Write Request @[%x]=%x Initiation", cpu_addr, new_data);
            while (!cpu_done || !mm_done) #2;
            {cpu_read, cpu_write} <= 'b00;
            eval32(cpu_done, mm_lines[addr>>4][(addr[3:0]*8+31)-:32], new_data, $sformatf(
                   "Write Request @[%x]=%x", cpu_addr, new_data));
            for (iter_offset = 0; iter_offset < 16; iter_offset += 4) begin
                #2;
                {cpu_read, cpu_write} <= 'b10;
                cpu_addr <= ~((~addr) | 15) + iter_offset;
                #2;
                {cpu_read, cpu_write} <= 'b00;
                eval32(cpu_done, cpu_data_out, mm_lines[addr>>4][(iter_offset*8+31)-:32], $sformatf(
                       "Read Request @[%x]", cpu_addr));
            end
            #2;
        end
    endtask

    integer i;
    integer rnd_addr;
    initial begin
        #11;
        for (i = 0; i < 100; i += 1) begin
            rnd_addr = ($random * 4) & ((1 << 14) - 1);
            if (($random & 1) == 0) cpu_read_req(rnd_addr);
            else cpu_write_req(rnd_addr, $random);
        end

        if (failed_evals === 0) begin
            $display("ACCEPTED");
        end else begin
            $display("FAILED");
        end
        $display((total_evals - failed_evals), " / ", total_evals);

        $finish;
    end
endmodule
