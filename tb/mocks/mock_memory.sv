import mc_defs_pkg::*;

module mock_memory (
    input  logic              clk,
    input  logic              rst,

    input  logic [7:0]        cfg_accept_delay,
    input  logic [7:0]        cfg_completion_delay,
    input  logic [MC_LINE_WIDTH-1:0] cfg_read_data,

    input  logic              request_valid,
    output logic              request_ready,
    input  mc_line_mem_op_t   request_op,
    input  logic [MC_ADDR_WIDTH-1:0] request_line_address,
    input  logic [MC_LINE_WIDTH-1:0] request_write_data,

    output logic              response_valid,
    output logic [MC_LINE_WIDTH-1:0] response_read_data,

    output logic              accepted,
    output logic              response_issued
);
    timeunit 1ns;
    timeprecision 1ps;

    typedef enum logic [2:0] {
        MEM_IDLE,
        MEM_WAIT_ACCEPT,
        MEM_WAIT_COMPLETION,
        MEM_RESPOND
    } memory_state_t;

    memory_state_t state;
    logic [7:0] accept_count;
    logic [7:0] completion_count;
    mc_line_mem_op_t accepted_op;
    logic [MC_ADDR_WIDTH-1:0] accepted_line_address;
    logic [MC_LINE_WIDTH-1:0] accepted_write_data;
    logic [MC_LINE_WIDTH-1:0] selected_read_data;

    always_comb begin
        request_ready = (state == MEM_WAIT_ACCEPT) &&
                        (accept_count == 8'd0);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state                   <= MEM_IDLE;
            accept_count            <= '0;
            completion_count        <= '0;
            accepted_op             <= MC_LINE_READ;
            accepted_line_address   <= '0;
            accepted_write_data     <= '0;
            selected_read_data      <= '0;
            response_valid          <= 1'b0;
            response_read_data      <= '0;
            accepted                <= 1'b0;
            response_issued         <= 1'b0;
        end else begin
            accepted        <= 1'b0;
            response_issued <= 1'b0;

            case (state)
                MEM_IDLE: begin
                    response_valid <= 1'b0;

                    if (request_valid) begin
                        accept_count <= cfg_accept_delay;
                        state        <= MEM_WAIT_ACCEPT;
                    end
                end

                MEM_WAIT_ACCEPT: begin
                    if (!request_valid) begin
                        state <= MEM_IDLE;
                    end else if (request_ready) begin
                        accepted_op           <= request_op;
                        accepted_line_address <= request_line_address;
                        accepted_write_data   <= request_write_data;
                        selected_read_data    <= cfg_read_data;
                        completion_count      <= cfg_completion_delay;
                        accepted              <= 1'b1;
                        state                 <= MEM_WAIT_COMPLETION;
                    end else begin
                        accept_count <= accept_count - 8'd1;
                    end
                end

                MEM_WAIT_COMPLETION: begin
                    if (completion_count != 8'd0) begin
                        completion_count <= completion_count - 8'd1;
                    end else begin
                        response_read_data <= selected_read_data;
                        response_valid     <= 1'b1;
                        response_issued    <= 1'b1;
                        state              <= MEM_RESPOND;
                    end
                end

                MEM_RESPOND: begin
                    response_valid <= 1'b0;
                    state          <= MEM_IDLE;
                end

                default: begin
                    state          <= MEM_IDLE;
                    response_valid <= 1'b0;
                end
            endcase
        end
    end

    wire _unused = &{
        1'b0,
        accepted_op,
        accepted_line_address[0],
        accepted_write_data[0]
    };
endmodule
