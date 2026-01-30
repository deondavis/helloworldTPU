`timescale 1ns/1ps

module tb_mac_array;
    localparam int N      = 4;
    localparam int DATA_W = 8;
    localparam int SUM_W  = 32;

    localparam logic [15:0] TPU_BASE    = 16'h0000;
    localparam logic [15:0] ID_ADDR     = TPU_BASE + 16'h0000;
    localparam logic [15:0] VER_ADDR    = TPU_BASE + 16'h0004;
    localparam logic [15:0] CTRL_ADDR   = TPU_BASE + 16'h0008;
    localparam logic [15:0] STATUS_ADDR = TPU_BASE + 16'h000C;
    localparam logic [15:0] A_BASE      = TPU_BASE + 16'h0100;
    localparam logic [15:0] B_BASE      = TPU_BASE + 16'h0200;
    localparam logic [15:0] C_BASE      = TPU_BASE + 16'h0300;

    logic clk = 0;
    logic rst = 1;

    logic        mmio_wr;
    logic        mmio_rd;
    logic [15:0] mmio_addr;
    logic [31:0] mmio_wdata;
    logic [3:0]  mmio_wstrb;
    wire  [31:0] mmio_rdata;
    wire         mmio_ready;
    logic [31:0] status;
    int unsigned observed;

    // Test matrices (unsigned 8-bit).
    int unsigned A[N][N];
    int unsigned B[N][N];
    int unsigned GOLD[N][N];

    // DUT
    tpu_top #(.N(N), .DATA_W(DATA_W), .SUM_W(SUM_W)) dut (
        .clk       (clk),
        .rst       (rst),
        .mmio_wr   (mmio_wr),
        .mmio_rd   (mmio_rd),
        .mmio_addr (mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready)
    );

    // Clock: 100 MHz (10 ns period).
    always #5 clk = ~clk;

    task automatic mmio_write(input logic [15:0] addr, input logic [31:0] data);
        begin
            mmio_addr  <= addr;
            mmio_wdata <= data;
            mmio_wstrb <= 4'hF;
            mmio_wr    <= 1'b1;
            mmio_rd    <= 1'b0;
            @(posedge clk);
            mmio_wr    <= 1'b0;
        end
    endtask

    task automatic mmio_read(input logic [15:0] addr, output logic [31:0] data);
        begin
            mmio_addr <= addr;
            mmio_wr   <= 1'b0;
            mmio_rd   <= 1'b1;
            @(posedge clk);
            data = mmio_rdata;
            mmio_rd   <= 1'b0;
        end
    endtask

    // Initialize matrices and compute golden C = A * B.
    initial begin
        // A matrix
        A[0][0] = 1; A[0][1] = 2; A[0][2] = 3; A[0][3] = 4;
        A[1][0] = 5; A[1][1] = 6; A[1][2] = 7; A[1][3] = 8;
        A[2][0] = 9; A[2][1] = 1; A[2][2] = 2; A[2][3] = 3;
        A[3][0] = 4; A[3][1] = 5; A[3][2] = 6; A[3][3] = 7;

        // B matrix
        B[0][0] = 1; B[0][1] = 0; B[0][2] = 2; B[0][3] = 1;
        B[1][0] = 0; B[1][1] = 1; B[1][2] = 1; B[1][3] = 0;
        B[2][0] = 1; B[2][1] = 1; B[2][2] = 0; B[2][3] = 1;
        B[3][0] = 0; B[3][1] = 2; B[3][2] = 1; B[3][3] = 1;

        // Golden reference
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                GOLD[r][c] = 0;
                for (int k = 0; k < N; k++) begin
                    GOLD[r][c] += A[r][k] * B[k][c];
                end
            end
        end
    end

    initial begin
        $dumpfile("outputs/wave.vcd");
        $dumpvars(0, tb_mac_array);

        mmio_wr    = 0;
        mmio_rd    = 0;
        mmio_addr  = 0;
        mmio_wdata = 0;
        mmio_wstrb = 4'hF;

        // Reset for two cycles.
        repeat (2) @(posedge clk);
        rst <= 0;

        // Write A and B matrices into MMIO windows.
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                mmio_write(A_BASE + (r * N + c), A[r][c]);
                mmio_write(B_BASE + (r * N + c), B[r][c]);
            end
        end

        // Quick sanity check reads.
        mmio_read(A_BASE, status);
        $display("DBG A[0]=%0d", status[7:0]);
        mmio_read(B_BASE, status);
        $display("DBG B[0]=%0d", status[7:0]);
        mmio_read(ID_ADDR, status);
        $display("DBG ID=0x%08x", status);
        mmio_read(VER_ADDR, status);
        $display("DBG VER=0x%08x", status);

        // Kick off computation.
        mmio_write(CTRL_ADDR, 32'h1); // start

        // Poll for done.
        do begin
            mmio_read(STATUS_ADDR, status);
        end while (!status[1]);

        // Read back C matrix and check.
        $display("Observed C (sum):");
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                mmio_read(C_BASE + (r * N + c), status);
                observed = status;
                $display("C[%0d][%0d] = %0d (golden %0d)", r, c, observed, GOLD[r][c]);
                if (observed[15:0] !== GOLD[r][c][15:0]) begin
                    $fatal(1, "Mismatch at (%0d,%0d): got %0d expected %0d", r, c, observed, GOLD[r][c]);
                end
            end
        end
        $display("PASS");
        $finish;
    end
endmodule
