#!/usr/bin/env bash
set -euo pipefail

# Build the PicoRV32 TPU smoke-test firmware and emit outputs/tpu_smoke.hex.
# Override RISCV_PREFIX if your toolchain is named differently.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RISCV_PREFIX="${RISCV_PREFIX:-riscv32-unknown-elf}"

echo "Building firmware with RISCV_PREFIX=${RISCV_PREFIX}"
make -C "$ROOT_DIR/sw/firmware" RISCV_PREFIX="$RISCV_PREFIX"
echo "Firmware hex: $ROOT_DIR/outputs/tpu_smoke.hex"
