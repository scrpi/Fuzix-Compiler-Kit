#!/usr/bin/env bash
# Build + run the MMU unit testbench under Icarus (-gspecify, TIMED; D-47).
# Drives translate + the page table directly: identity boot, LDMMU/translate, map select,
# DIRECT_PHYSICAL, STMMU readback. Artifacts -> /tmp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT=/tmp/blip_mmu
mkdir -p "$OUT"
iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/mmu.v" \
    "$ROOT/sim/tb/mmu/tb_mmu.v"
vvp "$OUT/tb"
