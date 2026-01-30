`timescale 1ns/1ps

// One processing element: passes inputs east/south and accumulates local sum.
module pe #(
    parameter DATA_W = 8,
    parameter SUM_W  = 32
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 en,
    input  logic [DATA_W-1:0]    a_in,
    input  logic [DATA_W-1:0]    b_in,
    output logic [DATA_W-1:0]    a_out,
    output logic [DATA_W-1:0]    b_out,
    output logic [SUM_W-1:0]     sum_out
);
    always_ff @(posedge clk) begin
        if (rst) begin
            a_out  <= '0;
            b_out  <= '0;
            sum_out <= '0;
        end else if (en) begin
            a_out  <= a_in;
            b_out  <= b_in;
            sum_out <= sum_out + a_in * b_in; // unsigned MAC
        end
    end
endmodule
