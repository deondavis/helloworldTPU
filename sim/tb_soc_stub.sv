`timescale 1ns/1ps

module tb_soc_stub;
    // Short smoke sim to ensure the PicoRV32+TPU SoC builds.
    logic clk = 0;
    logic rst = 1;
    wire  trap;

    localparam int SIG_BYTE = 32'h3F00;

    soc_top #(
        .MEM_WORDS(4096),
        .FIRMWARE_HEX("outputs/tpu_smoke.hex")
    ) dut (
        .clk (clk),
        .rst (rst),
        .trap(trap)
    );

    always #5 clk = ~clk;

    integer cycles;

    initial begin
        $dumpfile("outputs/soc_stub.vcd");
        $dumpvars(0, tb_soc_stub);

        repeat (5) @(posedge clk);
        rst <= 0;

        // Run until the firmware hits ebreak (trap) or timeout.
        cycles = 0;
        while (!trap && cycles < 200000) begin
            @(posedge clk);
            cycles++;
        end

        if (!trap) begin
            $display("timeout: signature=0x%02x%02x%02x%02x state=%0d busy=%0b done=%0b t_ctr=%0d",
                     dut.ram[SIG_BYTE+3], dut.ram[SIG_BYTE+2], dut.ram[SIG_BYTE+1], dut.ram[SIG_BYTE+0],
                     dut.u_tpu.state, dut.u_tpu.busy, dut.u_tpu.done, dut.u_tpu.t_ctr);
            $fatal(1, "Timeout waiting for firmware to trap");
        end

        $display("soc_stub: trap=%0d after %0d cycles", trap, cycles);
        $display("soc_stub: signature=0x%02x%02x%02x%02x",
                 dut.ram[SIG_BYTE+3], dut.ram[SIG_BYTE+2], dut.ram[SIG_BYTE+1], dut.ram[SIG_BYTE+0]);
        $display("soc_stub: tpu state=%0d busy=%0b done=%0b t_ctr=%0d",
                 dut.u_tpu.state, dut.u_tpu.busy, dut.u_tpu.done, dut.u_tpu.t_ctr);
        if ({dut.ram[SIG_BYTE+3], dut.ram[SIG_BYTE+2], dut.ram[SIG_BYTE+1], dut.ram[SIG_BYTE+0]} !== 32'hCAFE0001) begin
            $fatal(1, "Firmware signature mismatch (got 0x%02x%02x%02x%02x)",
                   dut.ram[SIG_BYTE+3], dut.ram[SIG_BYTE+2], dut.ram[SIG_BYTE+1], dut.ram[SIG_BYTE+0]);
        end else begin
            $display("soc_stub: PASS");
        end

        $finish;
    end
endmodule
