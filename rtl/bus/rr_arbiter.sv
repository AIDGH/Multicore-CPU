module rr_arbiter (
    input  logic       clk,
    input  logic       rst,
    input  logic [1:0] req,
    input  logic       txn_done,
    output logic [1:0] grant
);
    timeunit 1ns;
    timeprecision 1ps;

    logic tie_priority;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            grant        <= 2'b00;
            tie_priority <= 1'b0;
        end else begin
            case (grant)
                2'b00: begin
                    case (req)
                        2'b01: grant <= 2'b01;
                        2'b10: grant <= 2'b10;
                        2'b11: begin
                            if (tie_priority)
                                grant <= 2'b10;
                            else
                                grant <= 2'b01;
                        end
                        default: grant <= 2'b00;
                    endcase
                end

                2'b01: begin
                    if (txn_done) begin
                        tie_priority <= 1'b1;

                        case (req)
                            2'b01: grant <= 2'b01;
                            2'b10: grant <= 2'b10;
                            2'b11: grant <= 2'b10;
                            default: grant <= 2'b00;
                        endcase
                    end
                end

                2'b10: begin
                    if (txn_done) begin
                        tie_priority <= 1'b0;

                        case (req)
                            2'b01: grant <= 2'b01;
                            2'b10: grant <= 2'b10;
                            2'b11: grant <= 2'b01;
                            default: grant <= 2'b00;
                        endcase
                    end
                end

                default: begin
                    grant        <= 2'b00;
                    tie_priority <= 1'b0;
                end
            endcase
        end
    end
endmodule
