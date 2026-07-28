import mc_defs_pkg::*;

module mock_core (
    input  logic              clk,
    input  logic              rst,

    input  logic              issue_valid,
    output logic              issue_ready,
    input  logic [MC_ADDR_WIDTH-1:0] issue_address,
    input  mc_mem_op_t        issue_op,
    input  logic [MC_WORD_WIDTH-1:0] issue_write_data,

    output logic              request_valid,
    input  logic              request_ready,
    output logic [MC_ADDR_WIDTH-1:0] request_address,
    output mc_mem_op_t        request_op,
    output logic [MC_WORD_WIDTH-1:0] request_write_data,

    input  logic              response_valid,
    input  logic [MC_WORD_WIDTH-1:0] response_read_data,
    input  mc_resp_status_t   response_status,

    output logic              outstanding,
    output logic              completed,
    output logic [MC_WORD_WIDTH-1:0] completed_read_data,
    output mc_resp_status_t   completed_status
);
    timeunit 1ns;
    timeprecision 1ps;

    typedef enum logic [1:0] {
        CORE_IDLE,
        CORE_REQUEST,
        CORE_WAIT_RESPONSE
    } core_state_t;

    core_state_t state;

    always_comb begin
        issue_ready = (state == CORE_IDLE);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state                 <= CORE_IDLE;
            request_valid         <= 1'b0;
            request_address       <= '0;
            request_op            <= MC_MEM_LOAD;
            request_write_data    <= '0;
            outstanding           <= 1'b0;
            completed             <= 1'b0;
            completed_read_data   <= '0;
            completed_status      <= MC_RESP_OK;
        end else begin
            completed <= 1'b0;

            case (state)
                CORE_IDLE: begin
                    request_valid <= 1'b0;
                    outstanding   <= 1'b0;

                    if (issue_valid) begin
                        request_address    <= issue_address;
                        request_op         <= issue_op;
                        request_write_data <= issue_write_data;
                        request_valid      <= 1'b1;
                        outstanding        <= 1'b1;
                        state              <= CORE_REQUEST;
                    end
                end

                CORE_REQUEST: begin
                    if (request_valid && request_ready) begin
                        request_valid <= 1'b0;
                        state         <= CORE_WAIT_RESPONSE;
                    end
                end

                CORE_WAIT_RESPONSE: begin
                    if (response_valid) begin
                        completed_read_data <= response_read_data;
                        completed_status    <= response_status;
                        completed           <= 1'b1;
                        outstanding         <= 1'b0;
                        state               <= CORE_IDLE;
                    end
                end

                default: begin
                    state         <= CORE_IDLE;
                    request_valid <= 1'b0;
                    outstanding   <= 1'b0;
                end
            endcase
        end
    end
endmodule
