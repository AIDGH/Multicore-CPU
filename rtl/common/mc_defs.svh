`ifndef MC_DEFS_SVH
`define MC_DEFS_SVH

package mc_defs_pkg;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer MC_ADDR_WIDTH        = 32;
    localparam integer MC_WORD_WIDTH        = 32;
    localparam integer MC_LINE_WIDTH        = 128;
    localparam integer MC_LINE_BYTES        = 16;
    localparam integer MC_LINE_OFFSET_BITS  = 4;
    localparam integer MC_LINE_ID_WIDTH     = MC_ADDR_WIDTH - MC_LINE_OFFSET_BITS;
    localparam integer MC_CORE_ID_WIDTH     = 1;

    typedef enum logic [2:0] {
        MC_MEM_LOAD   = 3'd0,
        MC_MEM_STORE  = 3'd1,
        MC_MEM_LR     = 3'd2,
        MC_MEM_SC     = 3'd3,
        MC_MEM_AMOADD = 3'd4
    } mc_mem_op_t;

    typedef enum logic [1:0] {
        MC_BUS_RD        = 2'd0,
        MC_BUS_RDX       = 2'd1,
        MC_BUS_WRITEBACK = 2'd2
    } mc_bus_txn_t;

    typedef enum logic {
        MC_LINE_READ  = 1'b0,
        MC_LINE_WRITE = 1'b1
    } mc_line_mem_op_t;

    typedef enum logic [1:0] {
        MC_RESP_OK         = 2'd0,
        MC_RESP_SC_SUCCESS = 2'd1,
        MC_RESP_SC_FAILURE = 2'd2
    } mc_resp_status_t;

endpackage

`endif
