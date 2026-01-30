`timescale 1ns/1ps

module soc_top #(
    parameter int MEM_WORDS    = 4096,          // 16 KB default
    parameter string FIRMWARE_HEX = ""          // optional hex file to preload RAM
)(
    input  logic clk,
    input  logic rst,
    output logic trap
);
    localparam int MEM_BYTES = MEM_WORDS * 4;
    localparam int RAM_ADDR_W = $clog2(MEM_WORDS);

    localparam logic [31:0] TPU_BASE_ADDR = 32'h4000_0000;
    localparam logic [31:0] TPU_ADDR_MASK = 32'hF000_0000;

    // PicoRV32 memory bus.
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    wire        mem_la_read;
    wire        mem_la_write;
    wire [31:0] mem_la_addr;
    wire [31:0] mem_la_wdata;
    wire [3:0]  mem_la_wstrb;

    // CPU core.
    picorv32 #(
        .ENABLE_COUNTERS     (0),
        .ENABLE_COUNTERS64   (0),
        .ENABLE_REGS_16_31   (1),
        .ENABLE_REGS_DUALPORT(1),
        .BARREL_SHIFTER      (0),
        .TWO_STAGE_SHIFT     (1),
        .TWO_CYCLE_COMPARE   (0),
        .TWO_CYCLE_ALU       (0),
        .COMPRESSED_ISA      (0),
        .ENABLE_MUL          (0),
        .ENABLE_DIV          (0),
        .ENABLE_FAST_MUL     (0),
        .ENABLE_PCPI         (0),
        .ENABLE_IRQ          (0),
        .ENABLE_IRQ_TIMER    (0),
        .PROGADDR_RESET      (32'h0000_0000),
        .PROGADDR_IRQ        (32'h0000_0010),
        .STACKADDR           (MEM_BYTES - 4)
    ) u_cpu (
        .clk         (clk),
        .resetn      (!rst),
        .trap        (trap),
        .mem_valid   (mem_valid),
        .mem_instr   (mem_instr),
        .mem_ready   (mem_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata),
        .mem_la_read (mem_la_read),
        .mem_la_write(mem_la_write),
        .mem_la_addr (mem_la_addr),
        .mem_la_wdata(mem_la_wdata),
        .mem_la_wstrb(mem_la_wstrb),
        .pcpi_valid  (),
        .pcpi_insn   (),
        .pcpi_rs1    (),
        .pcpi_rs2    (),
        .pcpi_wr     (1'b0),
        .pcpi_rd     (32'b0),
        .pcpi_wait   (1'b0),
        .pcpi_ready  (1'b0),
        .irq         (32'b0),
        .eoi         (),
`ifdef RISCV_FORMAL
        .rvfi_valid  (),
        .rvfi_order  (),
        .rvfi_insn   (),
        .rvfi_trap   (),
        .rvfi_halt   (),
        .rvfi_intr   (),
        .rvfi_mode   (),
        .rvfi_ixl    (),
        .rvfi_rs1_addr(),
        .rvfi_rs2_addr(),
        .rvfi_rs1_rdata(),
        .rvfi_rs2_rdata(),
        .rvfi_rd_addr(),
        .rvfi_rd_wdata(),
        .rvfi_pc_rdata(),
        .rvfi_pc_wdata(),
        .rvfi_mem_addr(),
        .rvfi_mem_rmask(),
        .rvfi_mem_wmask(),
        .rvfi_mem_rdata(),
        .rvfi_mem_wdata(),
        .rvfi_csr_mcycle_rmask(),
        .rvfi_csr_mcycle_wmask(),
        .rvfi_csr_mcycle_rdata(),
        .rvfi_csr_mcycle_wdata(),
        .rvfi_csr_minstret_rmask(),
        .rvfi_csr_minstret_wmask(),
        .rvfi_csr_minstret_rdata(),
        .rvfi_csr_minstret_wdata(),
`endif
        .trace_valid (),
        .trace_data  ()
    );

    // On-chip RAM (simple single-ported BRAM style).
    reg [31:0] ram [0:MEM_WORDS-1];
    reg [31:0] ram_rdata;
    reg        ram_ready;

    // Avoid Xs when no firmware is provided.
    initial begin
        for (int i = 0; i < MEM_WORDS; i++) begin
            ram[i] = 32'h0000_0013; // ADDI x0, x0, 0 (NOP)
        end
        if (FIRMWARE_HEX != "") begin
            $display("soc_top: loading firmware from %s", FIRMWARE_HEX);
            $readmemh(FIRMWARE_HEX, ram);
        end
    end

    wire ram_sel = mem_valid && (mem_addr[31:2] < MEM_WORDS) && (mem_addr[31:28] == 4'h0);
    wire [RAM_ADDR_W-1:0] ram_word_addr = mem_addr[RAM_ADDR_W+1:2];

    always_ff @(posedge clk) begin
        ram_ready <= 1'b0;
        if (rst) begin
            ram_ready <= 1'b0;
        end else if (ram_sel) begin
            ram_ready <= 1'b1;
            ram_rdata <= ram[ram_word_addr];
            if (mem_wstrb[0]) ram[ram_word_addr][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) ram[ram_word_addr][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) ram[ram_word_addr][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[ram_word_addr][31:24] <= mem_wdata[31:24];
        end
    end

    // TPU MMIO decode.
    wire        tpu_sel   = mem_valid && ((mem_addr & TPU_ADDR_MASK) == TPU_BASE_ADDR);
    wire        tpu_wr    = tpu_sel && (|mem_wstrb);
    wire        tpu_rd    = tpu_sel && !tpu_wr;
    wire [15:0] tpu_addr  = mem_addr[15:0];
    wire [31:0] tpu_wdata = mem_wdata;
    wire [3:0]  tpu_wstrb = mem_wstrb;
    wire [31:0] tpu_rdata;
    wire        tpu_ready;

    tpu_top u_tpu (
        .clk       (clk),
        .rst       (rst),
        .mmio_wr   (tpu_wr),
        .mmio_rd   (tpu_rd),
        .mmio_addr (tpu_addr),
        .mmio_wdata(tpu_wdata),
        .mmio_wstrb(tpu_wstrb),
        .mmio_rdata(tpu_rdata),
        .mmio_ready(tpu_ready)
    );

    // Simple bus multiplexer.
    assign mem_ready = ram_sel ? ram_ready :
                       tpu_sel ? tpu_ready :
                       (mem_valid ? 1'b1 : 1'b0);

    assign mem_rdata = tpu_sel ? tpu_rdata :
                       ram_sel ? ram_rdata : 32'h0;
endmodule
