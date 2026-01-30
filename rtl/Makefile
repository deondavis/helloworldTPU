IVERILOG = iverilog
SIM_DEFS ?= 1
IVERILOG_FLAGS = -g2012
ifeq ($(SIM_DEFS),1)
IVERILOG_FLAGS += -DSIM
endif
VVP      = vvp
GTK      = gtkwave

ROOT := $(abspath ..)
RTL  := $(ROOT)/rtl/tpu_accel
SIMDIR  := $(ROOT)/sim
OUT_DIR := $(ROOT)/outputs

SRC = $(RTL)/pe.v $(RTL)/mac_array_4x4.v $(RTL)/tpu_buffers.v $(RTL)/tpu_regs.v $(RTL)/tpu_top.v $(SIMDIR)/tb_mac_array.sv
TOP = tb_mac_array
OUT = $(OUT_DIR)/simv

SOC_SRC = $(ROOT)/rtl/third_party/picorv32.v $(RTL)/pe.v $(RTL)/mac_array_4x4.v \
          $(RTL)/tpu_buffers.v $(RTL)/tpu_regs.v $(RTL)/tpu_top.v \
          $(ROOT)/rtl/soc_top.v $(SIMDIR)/tb_soc_stub.sv
SOC_TOP = tb_soc_stub
SOC_OUT = $(OUT_DIR)/soc_simv
SOC_HEX = $(OUT_DIR)/tpu_smoke.hex

.PHONY: sim soc_sim wave clean

sim:
	mkdir -p $(OUT_DIR)
	cd $(ROOT) && $(IVERILOG) $(IVERILOG_FLAGS) -s $(TOP) -o $(OUT) $(SRC)
	cd $(ROOT) && $(VVP) $(OUT)

soc_sim: $(SOC_HEX)
	mkdir -p $(OUT_DIR)
	cd $(ROOT) && $(IVERILOG) $(IVERILOG_FLAGS) -s $(SOC_TOP) -o $(SOC_OUT) $(SOC_SRC)
	cd $(ROOT) && $(VVP) $(SOC_OUT)

$(SOC_HEX):
	$(MAKE) -C $(ROOT)/sw/firmware

wave:
	$(GTK) $(OUT_DIR)/wave.vcd

clean:
	rm -f $(OUT) $(SOC_OUT) $(OUT_DIR)/wave.vcd $(OUT_DIR)/soc_stub.vcd
