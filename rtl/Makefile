IVERILOG = iverilog
VVP      = vvp
GTK      = gtkwave

ROOT := $(abspath ..)
RTL  := $(ROOT)/rtl/tpu_accel
SIM  := $(ROOT)/sim
OUT_DIR := $(ROOT)/outputs

SRC = $(RTL)/pe.v $(RTL)/mac_array_4x4.v $(RTL)/tpu_buffers.v $(RTL)/tpu_regs.v $(RTL)/tpu_top.v $(SIM)/tb_mac_array.sv
TOP = tb_mac_array
OUT = $(OUT_DIR)/simv

.PHONY: sim wave clean

sim:
	mkdir -p $(OUT_DIR)
	cd $(ROOT) && $(IVERILOG) -g2012 -s $(TOP) -o $(OUT) $(SRC)
	$(VVP) $(OUT)

wave:
	$(GTK) $(OUT_DIR)/wave.vcd

clean:
	rm -f $(OUT) $(OUT_DIR)/wave.vcd
