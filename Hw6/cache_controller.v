module cache_controller (
    input  wire         Clk,
    input  wire         Rst,

    // CPU-side interface
    input  wire [31:0]  CPU_Addr,
    input  wire         CPU_Read,
    input  wire         CPU_Write,
    input  wire [31:0]  CPU_DataIn,
    output reg          CPU_Done,
    output reg  [31:0]  CPU_DataOut,

    // Cache datapath lookup interface
    output wire [31:0]  LookupAddr,
    input  wire         LookupHit,
    input  wire [127:0] LookupLine,
    input  wire [31:0]  LookupWord,

    // Cache datapath write interface
    output reg          LineWriteEn,
    output reg  [31:0]  LineWriteAddr,
    output reg  [127:0] LineWriteData,

    // Main-memory interface
    output reg  [31:0]  MM_Addr,
    output reg          MM_Read,
    output reg          MM_Write,
    input  wire         MM_Done,
    input  wire [127:0] MM_DataIn,
    output reg  [127:0] MM_DataOut
);

    localparam [3:0]
        S_IDLE                  = 4'd0,
        S_READ_ISSUE            = 4'd1,
        S_READ_WAIT             = 4'd2,
        S_WRITE_HIT_ISSUE       = 4'd3,
        S_WRITE_HIT_WAIT        = 4'd4,
        S_WRITE_MISS_READ_ISSUE = 4'd5,
        S_WRITE_MISS_READ_WAIT  = 4'd6,
        S_WRITE_MISS_WR_ISSUE   = 4'd7,
        S_WRITE_MISS_WR_WAIT    = 4'd8,
        S_RESPONSE              = 4'd9;

    reg [3:0] state;

    reg [31:0]  req_addr;
    reg [31:0]  req_data;
    reg [127:0] pending_line;
    reg [31:0]  response_data;

    function [31:0] select_word;
        input [127:0] line;
        input [1:0]   word_offset;
        begin
            case (word_offset)
                2'b00: select_word = line[31:0];
                2'b01: select_word = line[63:32];
                2'b10: select_word = line[95:64];
                2'b11: select_word = line[127:96];
                default: select_word = 32'b0;
            endcase
        end
    endfunction

    function [127:0] replace_word;
        input [127:0] line;
        input [1:0]   word_offset;
        input [31:0]  new_word;
        reg   [127:0] result;
        begin
            result = line;
            case (word_offset)
                2'b00: result[31:0]    = new_word;
                2'b01: result[63:32]   = new_word;
                2'b10: result[95:64]   = new_word;
                2'b11: result[127:96]  = new_word;
            endcase
            replace_word = result;
        end
    endfunction

    // During idle, lookup the live CPU address so a read hit can complete
    // combinationally. During a miss/transaction, use the latched address.
    assign LookupAddr = (state == S_IDLE) ? CPU_Addr : req_addr;

    always @(*) begin
        CPU_Done      = 1'b0;
        CPU_DataOut   = response_data;

        LineWriteEn   = 1'b0;
        LineWriteAddr = req_addr;
        LineWriteData = pending_line;

        MM_Addr       = {req_addr[31:4], 4'b0000};
        MM_Read       = 1'b0;
        MM_Write      = 1'b0;
        MM_DataOut    = pending_line;

        case (state)
            S_IDLE: begin
                // Read hits are intentionally zero-wait-state. This is also
                // required by the provided testbench's one-cycle hit requests.
                if (CPU_Read && !CPU_Write && LookupHit) begin
                    CPU_Done    = 1'b1;
                    CPU_DataOut = LookupWord;
                end

                // On a write hit, update the cache line at the acceptance edge.
                if (CPU_Write && !CPU_Read && LookupHit) begin
                    LineWriteEn   = 1'b1;
                    LineWriteAddr = CPU_Addr;
                    LineWriteData = replace_word(LookupLine,
                                                 CPU_Addr[3:2],
                                                 CPU_DataIn);
                end
            end

            S_READ_ISSUE: begin
                MM_Read = 1'b1;
            end

            S_READ_WAIT: begin
                if (MM_Done) begin
                    LineWriteEn   = 1'b1;
                    LineWriteAddr = req_addr;
                    LineWriteData = MM_DataIn;
                end
            end

            S_WRITE_HIT_ISSUE: begin
                MM_Write   = 1'b1;
                MM_DataOut = pending_line;
            end

            S_WRITE_MISS_READ_ISSUE: begin
                MM_Read = 1'b1;
            end

            S_WRITE_MISS_READ_WAIT: begin
                if (MM_Done) begin
                    LineWriteEn   = 1'b1;
                    LineWriteAddr = req_addr;
                    LineWriteData = replace_word(MM_DataIn,
                                                 req_addr[3:2],
                                                 req_data);
                end
            end

            S_WRITE_MISS_WR_ISSUE: begin
                MM_Write   = 1'b1;
                MM_DataOut = pending_line;
            end

            S_RESPONSE: begin
                CPU_Done    = 1'b1;
                CPU_DataOut = response_data;
            end

            default: begin
            end
        endcase
    end

    always @(posedge Clk) begin
        if (Rst) begin
            state         <= S_IDLE;
            req_addr      <= 32'b0;
            req_data      <= 32'b0;
            pending_line  <= 128'b0;
            response_data <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (CPU_Read && !CPU_Write) begin
                        if (!LookupHit) begin
                            req_addr <= CPU_Addr;
                            state    <= S_READ_ISSUE;
                        end
                    end else if (CPU_Write && !CPU_Read) begin
                        req_addr <= CPU_Addr;
                        req_data <= CPU_DataIn;

                        if (LookupHit) begin
                            pending_line <= replace_word(LookupLine,
                                                         CPU_Addr[3:2],
                                                         CPU_DataIn);
                            state <= S_WRITE_HIT_ISSUE;
                        end else begin
                            state <= S_WRITE_MISS_READ_ISSUE;
                        end
                    end
                end

                S_READ_ISSUE: begin
                    state <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    if (MM_Done) begin
                        response_data <= select_word(MM_DataIn, req_addr[3:2]);
                        state         <= S_RESPONSE;
                    end
                end

                S_WRITE_HIT_ISSUE: begin
                    state <= S_WRITE_HIT_WAIT;
                end

                S_WRITE_HIT_WAIT: begin
                    if (MM_Done) begin
                        state <= S_RESPONSE;
                    end
                end

                S_WRITE_MISS_READ_ISSUE: begin
                    state <= S_WRITE_MISS_READ_WAIT;
                end

                S_WRITE_MISS_READ_WAIT: begin
                    if (MM_Done) begin
                        pending_line <= replace_word(MM_DataIn,
                                                     req_addr[3:2],
                                                     req_data);
                        state <= S_WRITE_MISS_WR_ISSUE;
                    end
                end

                S_WRITE_MISS_WR_ISSUE: begin
                    state <= S_WRITE_MISS_WR_WAIT;
                end

                S_WRITE_MISS_WR_WAIT: begin
                    if (MM_Done) begin
                        state <= S_RESPONSE;
                    end
                end

                S_RESPONSE: begin
                    // Do not accept the still-held request a second time.
                    if (!CPU_Read && !CPU_Write)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
