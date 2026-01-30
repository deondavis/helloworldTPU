#!/usr/bin/env bash
set -euo pipefail

# Compile the 4x4 MAC array testbench and run it.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

IVERILOG=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}

TOP=tb_mac_array
OUT_DIR="$ROOT_DIR/outputs"
OUT="$OUT_DIR/simv"

mkdir -p "$OUT_DIR"

$IVERILOG -g2012 -s "$TOP" -o "$OUT" \
  rtl/tpu_accel/pe.v rtl/tpu_accel/mac_array_4x4.v \
  rtl/tpu_accel/tpu_buffers.v rtl/tpu_accel/tpu_regs.v rtl/tpu_accel/tpu_top.v \
  sim/tb_mac_array.sv
$VVP "$OUT"
