import mc_defs_pkg::*;

module mock_l1 (
    input  logic              clk,
    input  logic              rst,

    input  logic [7:0]        cfg_accept_delay,
    input  logic [7:0]        cfg_completion_delay,
    input  logic [MC_WORD_WIDTH-1:0] cfg_response_data,
    input  logic              cfg_sc_success,

    input  logic              request_valid,
    output logic              request_ready,
    input  logic [MC_ADDR_WIDTH-1:0] request_address,
    input  mc_mem_op_t        request_op,
    input  logic [MC_WORD_WIDTH-1:0] request_write_data,

    output logic              response_valid,
    output logic [MC_WORD_WIDTH-1:0] response_read_data,
    output mc_resp_status_t   response_status,

    output logic              accepted,
    output logic              response_issued
);
    timeunit 1ns;
    timeprecision 1ps;

    typedef enum logic [2:0] {
        L1_IDLE,
        L1_WAIT_ACCEPT,
        L1_WAIT_COMPLETION,
        L1_RESPOND
    } l1_state_t;

    l1_state_t state;
    logic [7:0] accept_count;
    logic [7:0] completion_count;
    mc_mem_op_t accepted_op;
    logic [MC_ADDR_WIDTH-1:0] accepted_address;
    logic [MC_WORD_WIDTH-1:0] accepted_write_data;
    logic [MC_WORD_WIDTH-1:0] selected_response_data;
    logic selected_sc_success;

    always_comb begin
        request_ready = (state == L1_WAIT_ACCEPT) &&
                        (accept_count == 8'd0);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state                   <= L1_IDLE;
            accept_count            <= '0;
            completion_count        <= '0;
            accepted_op             <= MC_MEM_LOAD;
            accepted_address        <= '0;
            accepted_write_data     <= '0;
            selected_response_data  <= '0;
            selected_sc_success     <= 1'b0;
            response_valid          <= 1'b0;
            response_read_data      <= '0;
            response_status         <= MC_RESP_OK;
            accepted                <= 1'b0;
            response_issued         <= 1'b0;
        end else begin
            accepted        <= 1'b0;
            response_issued <= 1'b0;

            case (state)
                L1_IDLE: begin
                    response_valid <= 1'b0;

                    if (request_valid) begin
                        accept_count <= cfg_accept_delay;
                        state        <= L1_WAIT_ACCEPT;
                    end
                end

                L1_WAIT_ACCEPT: begin
                    if (!request_valid) begin
                        state <= L1_IDLE;
                    end else if (request_ready) begin
                        accepted_op            <= request_op;
                        accepted_address       <= request_address;
                        accepted_write_data    <= request_write_data;
                        selected_response_data <= cfg_response_data;
                        selected_sc_success    <= cfg_sc_success;
                        completion_count       <= cfg_completion_delay;
                        accepted               <= 1'b1;
                        state                  <= L1_WAIT_COMPLETION;
                    end else begin
                        accept_count <= accept_count - 8'd1;
                    end
                end

                L1_WAIT_COMPLETION: begin
                    if (completion_count != 8'd0) begin
                        completion_count <= completion_count - 8'd1;
                    end else begin
                        response_read_data <= selected_response_data;

                        if (accepted_op == MC_MEM_SC) begin
                            if (selected_sc_success)
                                response_status <= MC_RESP_SC_SUCCESS;
                            else
                                response_status <= MC_RESP_SC_FAILURE;
                        end else begin
                            response_status <= MC_RESP_OK;
                        end

                        response_valid  <= 1'b1;
                        response_issued <= 1'b1;
                        state           <= L1_RESPOND;
                    end
                end

                L1_RESPOND: begin
                    response_valid <= 1'b0;
                    state          <= L1_IDLE;
                end

                default: begin
                    state          <= L1_IDLE;
                    response_valid <= 1'b0;
                end
            endcase
        end
    end

    wire _unused = &{1'b0, accepted_address[0], accepted_write_data[0]};
endmodule
