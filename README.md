# 🧠⚡ helloworldTPU  
*A Tiny TPU‑like Accelerator on Tang Nano 9K*

<p align="center">
  <a href="https://github.com/deondavis/helloworldTPU/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/deondavis/helloworldTPU/ci.yml?label=CI&logo=github" />
  </a>
  <a href="https://github.com/deondavis/helloworldTPU/stargazers">
    <img src="https://img.shields.io/github/stars/deondavis/helloworldTPU?label=Stars&logo=github" />
  </a>
  <a href="https://github.com/deondavis/helloworldTPU/network/members">
    <img src="https://img.shields.io/github/forks/deondavis/helloworldTPU?label=Forks&logo=github" />
  </a>
  <a href="https://github.com/deondavis/helloworldTPU/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/deondavis/helloworldTPU?label=License" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FPGA-Tang%20Nano%209K-blue" />
  <img src="https://img.shields.io/badge/RISC--V-PicoRV32-orange" />
  <img src="https://img.shields.io/badge/Accelerator-4×4%20Systolic%20Array-purple" />
  <img src="https://img.shields.io/badge/Host-Fedora-informational" />
</p>

---

## ✨ What is this project?

**helloworldTPU** is a *from‑scratch*, hobbyist‑scale **TPU‑like accelerator** built on the **Tang Nano 9K FPGA**.

It is designed to be:
- 📘 **Educational**
- 🧩 **Minimal**
- 🔧 **Hackable**
- 🚀 **End‑to‑end**

---

## 🏗️ System Overview

**Architecture (v1):**
- 🧠 PicoRV32 RISC‑V CPU  
- ⚡ 4×4 int8 systolic MAC array  
- 🧱 BRAM tile buffers  
- 🗺️ Memory‑mapped accelerator  
- 🤖 Tiny MLP inference demo  

---

# Tang Nano 9K “Mini-TPU” Project Plan (README)

Goal: Build a small TPU-like accelerator on Tang Nano 9K:
- PicoRV32 control core
- Memory-mapped 4×4 int8 MAC systolic array (16 DSPs)
- BRAM tile buffers for A/B and an accumulator buffer for C
- Run inference for a tiny MLP (batched N=4 to match 4×4 tiles)

Development environment: **Fedora-based PC** (native Linux workflow).

---

## Target Architecture (v1)

### Compute format
- Inputs: int8
- Weights: int8
- Multiply: int8×int8 -> int16
- Accumulate: int32 (16 accumulators per output tile)
- Output modes:
  - Mode0: raw int32 accum results (debug + bring-up)
  - Mode1: quantized int8 = clamp((acc + bias) >> SHIFT) (later)

### Hardware blocks
1) PicoRV32 SoC (UART + simple RAM/ROM)
2) TPU accelerator (MMIO peripheral)
   - 4×4 MAC array using 16 DSP multipliers
   - A tile buffer in BRAM
   - B tile buffer in BRAM
   - C/accumulator buffer (registers or BRAM)
   - Control FSM + STATUS
3) Optional “nice-to-have” later:
   - bias add
   - ReLU
   - shift+clamp (int32->int8)
   - double-buffering

### Dataflow assumption (v1)
- CPU loads A and B tiles via MMIO “windows”
- Accelerator computes one 4×4 output tile for a given K (in chunks of K_TILE)
- CPU reads back results via MMIO

---

## 📁 Repo Layout

```
helloworldTPU/
├── docs/
│   └── sys_array_datasheet.md
├── outputs/                # sim/build artifacts
├── rtl/
│   ├── Makefile
│   ├── soc_top.v           # PicoRV32 + BRAM + TPU MMIO glue
│   ├── third_party/
│   │   └── picorv32.v      # vendored PicoRV32 core
│   ├── tpu_accel/
│   │   ├── tpu_top.v
│   │   ├── tpu_regs.v
│   │   ├── tpu_buffers.v
│   │   ├── mac_array_4x4.v
│   │   └── pe.v
├── sim/
│   ├── tb_mac_array.sv     # pure accelerator testbench
│   └── tb_soc_stub.sv      # PicoRV32+TPU smoke testbench
├── sw/
│   └── firmware/           # tiny MMIO smoke firmware (builds tpu_smoke.hex)
├── scripts/
│   ├── run_mac_array.sh
│   └── build_firmware.sh   # builds outputs/tpu_smoke.hex (set RISCV_PREFIX as needed)
└── README.md
```

### PicoRV32 SoC + TPU glue
- `soc_top.v` instantiates PicoRV32 with a small on-chip RAM (parameter `MEM_WORDS`, default 16 KB) and memory-maps the TPU at `0x4000_0000`.
- Firmware is preloaded via `FIRMWARE_HEX` (`$readmemh` of 32-bit words) and starts at `0x0000_0000`; the stack is placed at the top of the BRAM window.
- TPU offsets are identical to `docs/sys_array_datasheet.md`, but shifted up to the `0x4000_0000` region (e.g. ID at `0x4000_0000`, CTRL at `0x4000_0008`, A/B/C windows at `0x4000_0100/0x4000_0200/0x4000_0300`).
- Quick sims:
  - Accelerator-only: `make -C rtl sim SIM_DEFS=1`
  - SoC + firmware: `make -C rtl soc_sim SIM_DEFS=1 RISCV_PREFIX=riscv64-unknown-elf`
  - Convenience wrapper: `./scripts/run_simulation.sh [accel|soc|both]` (default `both`); set `RISCV_PREFIX` as needed.
  - Outputs: `outputs/wave.vcd` (accel), `outputs/soc_stub.vcd` (SoC) and PASS/FAIL in the console.
  - Requires a RISC-V bare-metal toolchain; set `RISCV_PREFIX` to match your install (e.g. `riscv64-unknown-elf`).
  - For synthesis-style builds, drop SIM defines: `SIM_DEFS=0`.

---

## 🧰 Tools used (Fedora Linux)

### FPGA build + flash (open-source flow)
- **Yosys**: synthesize Verilog to netlist
- **nextpnr-gowin**: place & route for Gowin FPGAs
- **Apicula**: Gowin bitstream packing + device database
- **openFPGALoader**: program the Tang Nano 9K

### RTL simulation + debugging
- **Icarus Verilog (iverilog)**: compile/run testbenches
- **GTKWave**: waveform viewing
- (Optional) **Verilator**: faster sims once things grow

### Firmware toolchain
- **riscv32-unknown-elf-gcc / binutils**: bare-metal builds
- **make** (or ninja), **python3**: scripts + build glue
- **picocom/minicom**: UART serial monitor
- (Optional) **gdb-multiarch**: if you add debug support later

### Editor / IDE
- VS Code (or your AI workflow IDE) + Git

---

## Phase Plan (Final)

### 🟢 Phase 0 — Toolchain + Board Bring-up (Fedora)
**Outcome:** You can build/flash bitstreams and observe UART/LED output.

**Primary development guide**
- Tang Nano 9K setup and workflow:
  https://learn.lushaylabs.com/getting-setup-with-the-tang-nano-9k/

**Tools used**
- yosys, nextpnr-gowin, apicula, openFPGALoader
- iverilog, gtkwave (optional in this phase but useful)
- git, make, python3
- picocom/minicom (for UART tests)

**Tasks**
- Install/verify toolchain works on Fedora (USB permissions included)
- Verify you can program the board repeatedly
- Flash known-good examples:
  - LED blink
  - UART TX “hello”

**Deliverables**
- `scripts/build_hw.sh` produces a bitstream
- `scripts/flash.sh` flashes and runs
- `sw/apps/hello_uart` prints over UART

**Effort (rough):** 6–12 hours (up to 1–3 days if tool quirks)

**Exit criteria**
- You can flash repeatedly and get deterministic UART output.

---

### 🔵 Phase 1 — 4×4 MAC Array in Simulation (Correctness First) — **DONE (SIM)**
**Outcome:** A 4×4 MAC array passes self-checking tests in simulation.

**Tools used**
- iverilog, gtkwave (core)
- (Optional) verilator for speed later
- python3 (optional) for vector generation

**Tasks**
- Implement `pe.v` (int8×int8->int16, accumulate int32)
- Implement `mac_array_4x4.v`
- Create a self-checking testbench:
  - Random A/B vectors
  - Golden reference computed in TB (or Python)
  - Waveform debug

**Deliverables**
- `rtl/tpu_accel/pe.v`
- `rtl/tpu_accel/mac_array_4x4.v`
- `sim/tb_mac_array.sv` + automated run script

**Effort:** 15–30 hours

**Exit criteria**
- 100+ randomized tests pass in simulation. ✅ (accelerator-only and SoC smoke sims now pass with firmware checksum 0x0000027c)

---

### 🟣 Phase 2 — PicoRV32 SoC Bring-up (MMIO Peripheral Pattern) — **IN PROGRESS (SIM)**  
*Waiting on FPGA hardware delivery; SoC + TPU smoke passes in simulation.*
**Outcome:** PicoRV32 boots firmware and can talk to an MMIO peripheral.

**Tools used**
- yosys, nextpnr-gowin, apicula, openFPGALoader
- riscv32-unknown-elf-gcc, binutils, make
- picocom/minicom for UART
- gtkwave (optional) for RTL-level debug

**Tasks**
- Integrate PicoRV32 + minimal bus fabric
- Add UART for printf/debug
- Add a trivial MMIO peripheral (LED reg / counter) to validate address decode
- Cross-compile bare-metal RISC-V program and run it on FPGA

**Deliverables**
- `rtl/soc_top.v` + `mmio_decode.v`
- `sw/apps/hello_uart` and `sw/apps/mmio_led_demo`

**Effort:** 20–40 hours

**Exit criteria**
- Firmware prints over UART and toggles LEDs via MMIO writes (pending hardware).

---

### 🟠 Phase 3 — TPU Accelerator MMIO + BRAM Tile Buffers (Single-Tile Compute) — **DONE (SIM)**  
*CPU loads A/B, starts accelerator, and reads C successfully in simulation.*
**Outcome:** CPU can load A/B tiles, start accelerator, and read back C.

**Tools used**
- FPGA toolchain (yosys/nextpnr/apicula/openFPGALoader)
- iverilog + gtkwave (for accelerator-level simulation)
- riscv32-unknown-elf-gcc + picocom (for hardware bring-up + testing)

**Design choices (lock these)**
- K_TILE = 32 or 64 (start with 32)
- Output mode: Mode0 raw int32 results first

**Tasks**
- Implement BRAM buffers for A and B
- Implement control FSM
- Implement MMIO register block + windows

**Deliverables**
- `rtl/tpu_accel/tpu_top.v`
- `sw/lib/tpu.c` with basic accelerator API

**Effort:** 30–60 hours

**Exit criteria**
- Hardware matches CPU reference for one 4×4 output tile across random tests (SIM ✅; HW pending board).

---

### 🟡 Phase 4 — GEMM in Firmware (Tiling + Full Matrix Multiply)
**Outcome:** Firmware can compute general GEMM using tiling loops over your 4×4 tile kernel.

**Tools used**
- riscv32-unknown-elf-gcc, make
- picocom/minicom (prints + test status)
- (Optional) python3 to generate randomized test matrices

**Tasks**
- Implement tiled GEMM in C
- Add random-matrix tests
- Handle edge cases (non-multiple-of-4 dimensions)

**Deliverables**
- `sw/apps/tpu_selftest`

**Effort:** 20–40 hours

**Exit criteria**
- Multiple matrix sizes pass vs CPU reference on FPGA.

---

### 🔴 Phase 5 — Post-Process (Bias + Shift + Clamp + ReLU)
**Outcome:** Accelerator can emit inference-ready int8 activations.

**Tools used**
- FPGA toolchain for iteration
- iverilog/gtkwave for checking the post-processing pipeline
- riscv32-unknown-elf-gcc for verification firmware

**Tasks**
- Add bias support
- Add shift + clamp
- Add optional ReLU

**Deliverables**
- Quantized output mode verified against CPU

**Effort:** 20–50 hours

**Exit criteria**
- Quantized results match CPU reference.

---

### 🤖 Phase 6 — Tiny MLP Inference Demo (Batch=4)
**Outcome:** Run inference for a small MLP using the TPU accelerator.

**Reference / inspiration**
- Karpathy-style minimal neural networks and MLP intuition:
  https://youtu.be/VMj-3S1tku0?si=aHmfzCFD7H8ZmxkB

**Tools used**
- riscv32-unknown-elf-gcc, make
- picocom/minicom for results logging
- (Optional) python3 script to export weights/test vectors

**Model recommendation**
- Batch size = 4 (to match 4×4 tiles)
- Example: `MLP 16 → 16 → 4`
  - Layer1: (16×16) × (16×4)
  - ReLU
  - Layer2: (4×16) × (16×4)

**Tasks**
- Implement MLP forward pass in C
- Store weights/bias in flash or BRAM (start with hardcoded arrays)
- Compare accelerator output vs CPU reference

**Deliverables**
- `sw/apps/mlp_infer` demo
- PASS/FAIL verification output

**Effort:** 40–80 hours

**Exit criteria**
- MLP inference matches CPU reference across multiple inputs.

---

## Quality Gates (Do Not Skip)
- Golden CPU reference always exists
- Same vectors used in simulation and hardware
- Raw int32 mode verified before quantization

---

## Immediate Next Steps
1) Hardware bring-up once Tang Nano 9K arrives: flash SoC + TPU bitstream, verify UART and MMIO writes/reads.
2) Run TPU smoke firmware on hardware; compare C buffer vs CPU golden (already matching in sim).
3) Trim SIM debug (`SIM_DEFS=0`) for synth builds; keep `SIM_DEFS=1` for sims.
4) Begin tiled GEMM firmware (Phase 4) after HW validation.

---

## Definition of Done
- TPU self-tests pass on FPGA
- Tiny MLP inference runs correctly on hardware
- MMIO map, data formats, and assumptions are documented

---

## 📜 License

MIT License — educational and experimental use.

---

<p align="center">
  🚀 <b>Have fun hacking silicon.</b>
</p>
