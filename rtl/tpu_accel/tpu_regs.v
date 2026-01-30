`timescale 1ns/1ps

module tpu_regs #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int SUM_W   = 32,
    parameter logic [31:0] ID_VALUE     = 32'h5450_0001,
    parameter logic [31:0] VERSION_VALUE= 32'h0001_0000,
    parameter logic [15:0] TPU_BASE     = 16'h0000
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    mmio_wr,
    input  logic                    mmio_rd,
    input  logic [15:0]             mmio_addr,
    input  logic [31:0]             mmio_wdata,
    input  logic [3:0]              mmio_wstrb,
    input  logic [DATA_W*N*N-1:0]   a_flat,
    input  logic [DATA_W*N*N-1:0]   b_flat,
    input  logic [SUM_W*N*N-1:0]    c_flat,
    output logic [31:0]             mmio_rdata,
    output logic                    mmio_ready,
    output logic                    busy,
    output logic                    done,
    output logic                    capture_sums,
    output logic [$clog2((2*N)+N + 1)-1:0] t_ctr,
    output logic [1:0]              state,
    output logic                    we_a,
    output logic                    we_b,
    output logic [$clog2(N*N)-1:0]  addr_a,
    output logic [$clog2(N*N)-1:0]  addr_b,
    output logic [DATA_W-1:0]       wdata_a,
    output logic [DATA_W-1:0]       wdata_b
);
    localparam int MAT_ELEMS     = N * N;
    localparam int STREAM_CYCLES = 2 * N;
    localparam int DRAIN_CYCLES  = 2 * N; // allow full pipeline drain
    localparam int RUN_CYCLES    = STREAM_CYCLES + DRAIN_CYCLES;
    localparam int TC_WIDTH      = $clog2(RUN_CYCLES + 1);
    localparam int ADDR_W        = $clog2(MAT_ELEMS);

    localparam logic [15:0] ID_ADDR      = TPU_BASE + 16'h0000;
    localparam logic [15:0] VERSION_ADDR = TPU_BASE + 16'h0004;
    localparam logic [15:0] CTRL_ADDR    = TPU_BASE + 16'h0008;
    localparam logic [15:0] STATUS_ADDR  = TPU_BASE + 16'h000C;
    localparam logic [15:0] A_BASE       = TPU_BASE + 16'h0100;
    localparam logic [15:0] B_BASE       = TPU_BASE + 16'h0200;
    localparam logic [15:0] C_BASE       = TPU_BASE + 16'h0300;

    localparam logic [1:0] S_IDLE = 2'd0;
    localparam logic [1:0] S_RUN  = 2'd1;
    localparam logic [1:0] S_DONE = 2'd2;

    wire start_pulse = mmio_wr && (mmio_addr == CTRL_ADDR) && mmio_wdata[0] && !busy;
    wire clear_done  = mmio_wr && (mmio_addr == CTRL_ADDR) && mmio_wdata[1];

    wire [ADDR_W-1:0] mmio_low = mmio_addr[ADDR_W-1:0];

    function automatic [DATA_W-1:0] get_a(input [DATA_W*N*N-1:0] vec, input int idx);
        get_a = vec[idx*DATA_W +: DATA_W];
    endfunction
    function automatic [DATA_W-1:0] get_b(input [DATA_W*N*N-1:0] vec, input int idx);
        get_b = vec[idx*DATA_W +: DATA_W];
    endfunction
    function automatic [SUM_W-1:0] get_c(input [SUM_W*N*N-1:0] vec, input int idx);
        get_c = vec[idx*SUM_W +: SUM_W];
    endfunction

    // MMIO read path.
    always_comb begin
        mmio_ready = 1'b1;
        mmio_rdata = 32'h0;
        if (mmio_rd) begin
            if (mmio_addr == ID_ADDR) begin
                mmio_rdata = ID_VALUE;
            end else if (mmio_addr == VERSION_ADDR) begin
                mmio_rdata = VERSION_VALUE;
            end else if (mmio_addr == STATUS_ADDR) begin
                mmio_rdata = {30'b0, done, busy};
            end else if ((mmio_addr >= A_BASE) && (mmio_addr < (A_BASE + MAT_ELEMS))) begin
                mmio_rdata = {24'h0, get_a(a_flat, mmio_low)};
            end else if ((mmio_addr >= B_BASE) && (mmio_addr < (B_BASE + MAT_ELEMS))) begin
                mmio_rdata = {24'h0, get_b(b_flat, mmio_low)};
            end else if ((mmio_addr >= C_BASE) && (mmio_addr < (C_BASE + MAT_ELEMS))) begin
                mmio_rdata = get_c(c_flat, mmio_low);
            end
        end
    end

    // Decode buffer writes (combinational strobes).
    assign we_a    = mmio_wr && (mmio_addr >= A_BASE) && (mmio_addr < (A_BASE + MAT_ELEMS));
    assign we_b    = mmio_wr && (mmio_addr >= B_BASE) && (mmio_addr < (B_BASE + MAT_ELEMS));
    assign addr_a  = mmio_low;
    assign addr_b  = mmio_low;
    assign wdata_a = mmio_wdata[DATA_W-1:0];
    assign wdata_b = mmio_wdata[DATA_W-1:0];

    // Control FSM and capture request.
    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            capture_sums <= 1'b0;
            t_ctr        <= '0;
        end else begin
            capture_sums <= 1'b0;
            if (clear_done) done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start_pulse) begin
                        state <= S_RUN;
                        busy  <= 1'b1;
                        done  <= 1'b0;
                        t_ctr <= '0;
                    end
                end
                S_RUN: begin
                    if (t_ctr == RUN_CYCLES - 1) begin
                        state <= S_DONE;
                        busy  <= 1'b0;
                        t_ctr <= '0;
                    end else begin
                        t_ctr <= t_ctr + 1'b1;
                    end
                end
                S_DONE: begin
                    // Capture sums one cycle after the run completes to avoid missing the final MAC.
                    if (!done) begin
                        capture_sums <= 1'b1;
                        done         <= 1'b1;
                    end
                    if (start_pulse) begin
                        state <= S_RUN;
                        busy  <= 1'b1;
                        done  <= 1'b0;
                        t_ctr <= '0;
                    end
                end
            endcase
        end
    end
endmodule
