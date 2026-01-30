`timescale 1ns/1ps

module tb_soc_stub;
    // Short smoke sim to ensure the PicoRV32+TPU SoC builds.
    logic clk = 0;
    logic rst = 1;
    wire  trap;

    soc_top #(
        .MEM_WORDS(256),
        .FIRMWARE_HEX("")
    ) dut (
        .clk (clk),
        .rst (rst),
        .trap(trap)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("outputs/soc_stub.vcd");
        $dumpvars(0, tb_soc_stub);

        repeat (5) @(posedge clk);
        rst <= 0;

        repeat (200) @(posedge clk);
        $display("soc_stub: trap=%0d", trap);
        $finish;
    end
endmodule
