`timescale 1ns/1ps

// 4x4 systolic array: stream one k-slice per cycle on west/north edges.
module systolic4x4 #(
    parameter DATA_W = 8,
    parameter SUM_W  = 32
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    input  logic [DATA_W-1:0]     a_west  [3:0], // A row elements for this cycle
    input  logic [DATA_W-1:0]     b_north [3:0], // B column elements for this cycle
    output wire  [SUM_W-1:0]      sum     [3:0][3:0] // accumulated results
);
    // Buses carry A east and B south.
    logic [DATA_W-1:0] a_bus [3:0][5];
    logic [DATA_W-1:0] b_bus [5][3:0];

    // Inject edges.
    for (genvar r = 0; r < 4; r++) begin
        assign a_bus[r][0] = a_west[r];
    end
    for (genvar c = 0; c < 4; c++) begin
        assign b_bus[0][c] = b_north[c];
    end

    // Grid of processing elements.
    for (genvar r = 0; r < 4; r++) begin : row
        for (genvar c = 0; c < 4; c++) begin : col
            pe #(.DATA_W(DATA_W), .SUM_W(SUM_W)) u_pe (
                .clk    (clk),
                .rst    (rst),
                .en     (en),
                .a_in   (a_bus[r][c]),
                .b_in   (b_bus[r][c]),
                .a_out  (a_bus[r][c+1]),
                .b_out  (b_bus[r+1][c]),
                .sum_out(sum[r][c])
            );
        end
    end
endmodule
