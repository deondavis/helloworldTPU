# TPU 4x4 Systolic Array Datasheet

## Overview
Fixed-function 4×4 unsigned matrix multiply (C = A×B) using a systolic MAC array. Inputs A and B are 8-bit unsigned; accumulators are 32-bit. Software loads A/B via MMIO windows, starts the engine, polls status, then reads C from an MMIO window.

### Block Diagram (textual)
- **MMIO Interface** → **Registers/FSM** → **BRAM Buffers (A, B, C)** → **Systolic 4×4 MAC Array**
  - MMIO provides ID/version, control/status, and A/B/C windows.
  - FSM streams A rows west→east and B columns north→south into the array, drains, then captures sums into C.

## Parameters (build-time)
- `N=4`, `DATA_W=8`, `SUM_W=32`
- `ID_VALUE=0x5450_0001`, `VERSION_VALUE=0x0001_0000`
- `TPU_BASE=0x0000` (all offsets below are relative to this base)

## MMIO Map
Offsets relative to `TPU_BASE` (default 0x0000):

```
0x0000 ID        (RO) 32b: ID_VALUE
0x0004 VERSION   (RO) 32b: VERSION_VALUE
0x0008 CTRL      (WO) bit0=start (when busy=0), bit1=clear_done
0x000C STATUS    (RO) bit0=busy, bit1=done
0x0100-0x010F A window (WO) 16 × 8b, A[r][c] at idx=r*4+c
0x0200-0x020F B window (WO) 16 × 8b, B[r][c] at idx=r*4+c
0x0300-0x033F C window (RO) 16 × 32b, C[r][c] at word offset idx=r*4+c (byte address = 0x0300 + idx*4)
```

## Programmer’s Model
1) **Write A/B**: For r=0..3, c=0..3, write byte to `A_BASE + (r*4+c)` and `B_BASE + (r*4+c)`.
2) **Clear done (optional)**: write `0x2` to `CTRL` to clear `done`.
3) **Start**: write `0x1` to `CTRL` (ignored if `busy=1`).
4) **Poll**: read `STATUS` until `done=1` (busy drops first, done asserts the following cycle). Fixed latency = `4*N` cycles from start to `busy` dropping (16 cycles at `N=4`), plus one cycle to capture `done`.
5) **Read C**: read 32-bit words at `C_BASE + ((r*4+c) << 2)` for all 16 entries.
6) **Repeat**: re-write A/B as needed, clear done if desired, start again.

Notes:
- A/B writes are byte-wide; C reads are 32-bit (lower bits hold the unsigned sum).
- `done` latches high until cleared via `CTRL.bit1`.
- Engine streams A rows and B columns over `2*N` cycles and drains for `N` cycles; accumulators are not reset between runs except by reset—each run captures fresh sums into C.

## Interface Signals (top-level)
- Inputs: `clk`, `rst`, `mmio_wr`, `mmio_rd`, `mmio_addr[15:0]`, `mmio_wdata[31:0]`, `mmio_wstrb[3:0]`
- Outputs: `mmio_rdata[31:0]`, `mmio_ready` (always 1)

## Integration Tips
- If mapping to a system address map, set `TPU_BASE`, `ID_VALUE`, `VERSION_VALUE` parameters on instantiation.
- `CTRL` start must only be asserted when `STATUS.busy==0`.
- For interrupt-based flow, gate an interrupt on `done` rising; clear via `CTRL.bit1`.
- If using DMA to preload A/B, ensure byte writes to the windows; C can be read as 32-bit words.

## Files
- RTL: `rtl/tpu_accel/pe.v`, `rtl/tpu_accel/mac_array_4x4.v`, `rtl/tpu_accel/tpu_buffers.v`, `rtl/tpu_accel/tpu_regs.v`, `rtl/tpu_accel/tpu_top.v`
- Testbench: `sim/tb_mac_array.sv`
- Run scripts: `scripts/run_mac_array.sh` (accelerator-only sim) and `make -C rtl soc_sim SIM_DEFS=1` (SoC + firmware sim)
- System integration: TPU is memory-mapped at `0x4000_0000` in the SoC; offsets above are relative to that base.
