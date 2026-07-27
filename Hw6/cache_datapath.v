module cache_datapath #(
    parameter INDEX_BITS = 4,
    parameter LINE_COUNT = (1 << INDEX_BITS)
) (
    input  wire         Clk,
    input  wire         Rst,

    // Combinational lookup port
    input  wire [31:0]  LookupAddr,
    output wire         LookupHit,
    output wire [127:0] LookupLine,
    output reg  [31:0]  LookupWord,

    // Whole-line write port (used for fill and write-allocate/update)
    input  wire         LineWriteEn,
    input  wire [31:0]  LineWriteAddr,
    input  wire [127:0] LineWriteData
);

    localparam TAG_BITS = 32 - INDEX_BITS - 4;

    reg [127:0] data_array  [0:LINE_COUNT-1];
    reg [TAG_BITS-1:0] tag_array [0:LINE_COUNT-1];
    reg valid_array [0:LINE_COUNT-1];

    wire [INDEX_BITS-1:0] lookup_index;
    wire [TAG_BITS-1:0]   lookup_tag;
    wire [INDEX_BITS-1:0] write_index;
    wire [TAG_BITS-1:0]   write_tag;

    assign lookup_index = LookupAddr[INDEX_BITS+3:4];
    assign lookup_tag   = LookupAddr[31:INDEX_BITS+4];
    assign write_index  = LineWriteAddr[INDEX_BITS+3:4];
    assign write_tag    = LineWriteAddr[31:INDEX_BITS+4];

    assign LookupLine = data_array[lookup_index];
    assign LookupHit  = valid_array[lookup_index] &&
                        (tag_array[lookup_index] == lookup_tag);

    // A 16-byte cache line contains four 32-bit words.
    always @(*) begin
        case (LookupAddr[3:2])
            2'b00: LookupWord = LookupLine[31:0];
            2'b01: LookupWord = LookupLine[63:32];
            2'b10: LookupWord = LookupLine[95:64];
            2'b11: LookupWord = LookupLine[127:96];
            default: LookupWord = 32'b0;
        endcase
    end

    integer i;
    always @(posedge Clk) begin
        if (Rst) begin
            for (i = 0; i < LINE_COUNT; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= {TAG_BITS{1'b0}};
                data_array[i]  <= 128'b0;
            end
        end else if (LineWriteEn) begin
            valid_array[write_index] <= 1'b1;
            tag_array[write_index]   <= write_tag;
            data_array[write_index]  <= LineWriteData;
        end
    end

endmodule
