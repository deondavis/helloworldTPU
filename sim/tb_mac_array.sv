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
        // A matrix (match firmware)
        A[0][0] = 1;  A[0][1] = 2;  A[0][2] = 3;  A[0][3] = 4;
        A[1][0] = 5;  A[1][1] = 6;  A[1][2] = 7;  A[1][3] = 8;
        A[2][0] = 9;  A[2][1] = 10; A[2][2] = 11; A[2][3] = 12;
        A[3][0] = 13; A[3][1] = 14; A[3][2] = 15; A[3][3] = 16;

        // B matrix (match firmware)
        B[0][0] = 2; B[0][1] = 1; B[0][2] = 0; B[0][3] = 3;
        B[1][0] = 1; B[1][1] = 0; B[1][2] = 2; B[1][3] = 1;
        B[2][0] = 3; B[2][1] = 1; B[2][2] = 1; B[2][3] = 0;
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

    integer cycle = 0;
    integer capture_cycle = -1;
    logic busy_q;

    always @(posedge clk) begin
        busy_q <= dut.busy;
        if (rst) begin
            cycle <= 0;
            capture_cycle <= -1;
        end else begin
            cycle <= cycle + 1;
            if (dut.capture_sums) begin
                capture_cycle = cycle;
                $display("capture_sums asserted at cycle=%0d t_ctr=%0d state=%0d", cycle, dut.t_ctr, dut.state);
            end
            if (busy_q && !dut.busy) begin
                $display("busy dropped at cycle=%0d t_ctr=%0d state=%0d", cycle, dut.t_ctr, dut.state);
            end
        end
    end

    initial begin
        int mismatches;
        int first_r;
        int first_c;
        int first_obs;
        int first_gold;
        int unsigned checksum_obs;
        int unsigned checksum_gold;

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
        mismatches = 0;
        first_r = -1;
        first_c = -1;
        first_obs = 0;
        first_gold = 0;
        checksum_obs = 0;
        checksum_gold = 0;
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                mmio_read(C_BASE + ((r * N + c) << 2), status);
                observed = status;
                checksum_obs += observed;
                checksum_gold += GOLD[r][c];
                $display("C[%0d][%0d] = %0d (golden %0d)", r, c, observed, GOLD[r][c]);
                if (observed[15:0] !== GOLD[r][c][15:0]) begin
                    if (mismatches == 0) begin
                        first_r = r;
                        first_c = c;
                        first_obs = observed;
                        first_gold = GOLD[r][c];
                    end
                    mismatches++;
                end
            end
        end
        $display("checksum_obs=0x%08x checksum_gold=0x%08x mismatches=%0d", checksum_obs, checksum_gold, mismatches);
        if (mismatches != 0) begin
            $fatal(1, "Mismatch count %0d first (%0d,%0d) got %0d expected %0d",
                   mismatches, first_r, first_c, first_obs, first_gold);
        end else begin
            $display("PASS");
            $finish;
        end
    end
endmodule
