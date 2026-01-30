`timescale 1ns/1ps

// Holds A/B input buffers and C output buffer.
module tpu_buffers #(
    parameter int N      = 4,
    parameter int DATA_W = 8,
    parameter int SUM_W  = 32
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    we_a,
    input  logic                    we_b,
    input  logic [$clog2(N*N)-1:0]  addr_a,
    input  logic [$clog2(N*N)-1:0]  addr_b,
    input  logic [DATA_W-1:0]       wdata_a,
    input  logic [DATA_W-1:0]       wdata_b,
    input  logic                    capture_c,
    input  logic [SUM_W-1:0]        sum_in [0:N-1][0:N-1],
    output logic [DATA_W*N*N-1:0]   a_flat,
    output logic [DATA_W*N*N-1:0]   b_flat,
    output logic [SUM_W*N*N-1:0]    c_flat
);
    localparam int MAT_ELEMS = N * N;

    logic [DATA_W-1:0] a_mem [0:MAT_ELEMS-1];
    logic [DATA_W-1:0] b_mem [0:MAT_ELEMS-1];
    logic [SUM_W-1:0]  c_mem [0:MAT_ELEMS-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < MAT_ELEMS; i++) begin
                a_mem[i] <= '0;
                b_mem[i] <= '0;
                c_mem[i] <= '0;
            end
        end else begin
            if (we_a) a_mem[addr_a] <= wdata_a;
            if (we_b) b_mem[addr_b] <= wdata_b;

            if (capture_c) begin
                for (int r = 0; r < N; r++) begin
                    for (int c = 0; c < N; c++) begin
                        c_mem[r * N + c] <= sum_in[r][c];
                    end
                end
            end
        end
    end

    // Packed views for interfacing without unpacked array ports.
    always_comb begin
        for (int i = 0; i < MAT_ELEMS; i++) begin
            a_flat[i*DATA_W +: DATA_W] = a_mem[i];
            b_flat[i*DATA_W +: DATA_W] = b_mem[i];
            c_flat[i*SUM_W  +: SUM_W ] = c_mem[i];
        end
    end
endmodule
