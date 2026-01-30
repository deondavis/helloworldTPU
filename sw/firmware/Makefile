ROOT := $(abspath ../..)
OUT_DIR := $(ROOT)/outputs

RISCV_PREFIX ?= riscv32-unknown-elf
CC  := $(RISCV_PREFIX)-gcc
OBJCOPY := $(RISCV_PREFIX)-objcopy

CFLAGS := -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Wall -Wextra -Os
LDFLAGS := -T linker.ld -nostdlib -static -Wl,--gc-sections

SRCS = crt0.S main.c
ELF  := $(OUT_DIR)/tpu_smoke.elf
HEX  := $(OUT_DIR)/tpu_smoke.hex

.PHONY: all clean

all: $(HEX)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(ELF): $(SRCS) linker.ld | $(OUT_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)

$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $(HEX)

clean:
	rm -f $(ELF) $(HEX)
