`timescale 1ns/1ps

module tpu_top #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int SUM_W   = 32
)(
    input  logic         clk,
    input  logic         rst,
    input  logic         mmio_wr,
    input  logic         mmio_rd,
    input  logic [15:0]  mmio_addr,
    input  logic [31:0]  mmio_wdata,
    input  logic [3:0]   mmio_wstrb,
    output logic [31:0]  mmio_rdata,
    output logic         mmio_ready
);
    localparam int MAT_ELEMS     = N * N;
    localparam int STREAM_CYCLES = 2 * N;

    localparam logic [1:0] S_IDLE = 2'd0;
    localparam logic [1:0] S_RUN  = 2'd1;

    logic [DATA_W-1:0] a_west  [0:N-1];
    logic [DATA_W-1:0] b_north [0:N-1];
    wire  [SUM_W-1:0]  sum     [0:N-1][0:N-1];

    logic [DATA_W*N*N-1:0] a_flat;
    logic [DATA_W*N*N-1:0] b_flat;
    logic [SUM_W*N*N-1:0]  c_flat;

    logic busy, done, capture_sums;
    logic [1:0] state;
    logic [$clog2((2*N)+N + 1)-1:0] t_ctr;

    logic we_a, we_b;
    logic [$clog2(MAT_ELEMS)-1:0] addr_a, addr_b;
    logic [DATA_W-1:0] wdata_a, wdata_b;

    function automatic [DATA_W-1:0] get_a(input [DATA_W*N*N-1:0] vec, input int idx);
        get_a = vec[idx*DATA_W +: DATA_W];
    endfunction
    function automatic [DATA_W-1:0] get_b(input [DATA_W*N*N-1:0] vec, input int idx);
        get_b = vec[idx*DATA_W +: DATA_W];
    endfunction

    // MMIO and control
    tpu_regs #(.N(N), .DATA_W(DATA_W), .SUM_W(SUM_W)) u_regs (
        .clk         (clk),
        .rst         (rst),
        .mmio_wr     (mmio_wr),
        .mmio_rd     (mmio_rd),
        .mmio_addr   (mmio_addr),
        .mmio_wdata  (mmio_wdata),
        .mmio_wstrb  (mmio_wstrb),
        .a_flat      (a_flat),
        .b_flat      (b_flat),
        .c_flat      (c_flat),
        .mmio_rdata  (mmio_rdata),
        .mmio_ready  (mmio_ready),
        .busy        (busy),
        .done        (done),
        .capture_sums(capture_sums),
        .t_ctr       (t_ctr),
        .state       (state),
        .we_a        (we_a),
        .we_b        (we_b),
        .addr_a      (addr_a),
        .addr_b      (addr_b),
        .wdata_a     (wdata_a),
        .wdata_b     (wdata_b)
    );

    // Buffer storage
    tpu_buffers #(.N(N), .DATA_W(DATA_W), .SUM_W(SUM_W)) u_buf (
        .clk        (clk),
        .rst        (rst),
        .we_a       (we_a),
        .we_b       (we_b),
        .addr_a     (addr_a),
        .addr_b     (addr_b),
        .wdata_a    (wdata_a),
        .wdata_b    (wdata_b),
        .capture_c  (capture_sums),
        .sum_in     (sum),
        .a_flat     (a_flat),
        .b_flat     (b_flat),
        .c_flat     (c_flat)
    );

    // Drive systolic inputs based on current cycle (skewed pattern).
    always_comb begin
        for (int r = 0; r < N; r++) begin
            a_west[r] = '0;
            b_north[r] = '0;
        end
        if (state == S_RUN) begin
            for (int r = 0; r < N; r++) begin
                if ((t_ctr < STREAM_CYCLES) && (t_ctr >= r) && ((t_ctr - r) < N)) begin
                    a_west[r] = get_a(a_flat, r * N + (t_ctr - r));
                end
            end
            for (int c = 0; c < N; c++) begin
                if ((t_ctr < STREAM_CYCLES) && (t_ctr >= c) && ((t_ctr - c) < N)) begin
                    b_north[c] = get_b(b_flat, (t_ctr - c) * N + c);
                end
            end
        end
    end

    // MAC array.
    systolic4x4 #(.DATA_W(DATA_W), .SUM_W(SUM_W)) u_array (
        .clk    (clk),
        .rst    (rst),
        .en     (state == S_RUN),
        .a_west (a_west),
        .b_north(b_north),
        .sum    (sum)
    );
endmodule
