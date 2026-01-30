#!/usr/bin/env bash
set -euo pipefail

# Run accelerator-only and/or SoC simulations.
# Usage: ./scripts/run_simulation.sh [accel|soc|both]

TARGET="${1:-both}"
RISCV_PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf}"

run_accel() {
    echo "==> Running accelerator-only sim (SIM_DEFS=1)"
    make -C rtl sim SIM_DEFS=1
}

run_soc() {
    echo "==> Building firmware (RISCV_PREFIX=${RISCV_PREFIX})"
    make -C sw/firmware clean all RISCV_PREFIX="${RISCV_PREFIX}"
    echo "==> Running SoC sim (SIM_DEFS=1)"
    make -C rtl soc_sim SIM_DEFS=1 RISCV_PREFIX="${RISCV_PREFIX}"
}

case "${TARGET}" in
    accel) run_accel ;;
    soc)   run_soc ;;
    both)  run_accel; run_soc ;;
    *)
        echo "Usage: $0 [accel|soc|both]" >&2
        exit 1
        ;;
esac
