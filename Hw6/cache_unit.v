// ============================================================
// cache_unit
// Direct-mapped, 16-byte line, write-through + write-allocate
// This is the reusable top-level wrapper around cache controller/datapath.
// ============================================================
module cache_unit (
    input  wire         Clk,
    input  wire         Rst,

    // CPU-side interface
    input  wire [31:0]  CPU_Addr,
    input  wire         CPU_Read,
    input  wire         CPU_Write,
    output wire         CPU_Done,
    input  wire [31:0]  CPU_DataIn,
    output wire [31:0]  CPU_DataOut,

    // Main-memory-side interface
    output wire [31:0]  MM_Addr,
    output wire         MM_Read,
    output wire         MM_Write,
    input  wire         MM_Done,
    input  wire [127:0] MM_DataIn,
    output wire [127:0] MM_DataOut
);

    wire [31:0]  lookup_addr;
    wire         lookup_hit;
    wire [127:0] lookup_line;
    wire [31:0]  lookup_word;

    wire         line_write_en;
    wire [31:0]  line_write_addr;
    wire [127:0] line_write_data;

    cache_datapath #(
        .INDEX_BITS(4),
        .LINE_COUNT(16)
    ) datapath (
        .Clk(Clk),
        .Rst(Rst),
        .LookupAddr(lookup_addr),
        .LookupHit(lookup_hit),
        .LookupLine(lookup_line),
        .LookupWord(lookup_word),
        .LineWriteEn(line_write_en),
        .LineWriteAddr(line_write_addr),
        .LineWriteData(line_write_data)
    );

    cache_controller controller (
        .Clk(Clk),
        .Rst(Rst),
        .CPU_Addr(CPU_Addr),
        .CPU_Read(CPU_Read),
        .CPU_Write(CPU_Write),
        .CPU_DataIn(CPU_DataIn),
        .CPU_Done(CPU_Done),
        .CPU_DataOut(CPU_DataOut),
        .LookupAddr(lookup_addr),
        .LookupHit(lookup_hit),
        .LookupLine(lookup_line),
        .LookupWord(lookup_word),
        .LineWriteEn(line_write_en),
        .LineWriteAddr(line_write_addr),
        .LineWriteData(line_write_data),
        .MM_Addr(MM_Addr),
        .MM_Read(MM_Read),
        .MM_Write(MM_Write),
        .MM_Done(MM_Done),
        .MM_DataIn(MM_DataIn),
        .MM_DataOut(MM_DataOut)
    );

endmodule
