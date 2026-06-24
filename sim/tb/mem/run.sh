#!/usr/bin/env bash
# Build + run the memory_interface testbench under Icarus (-gspecify, TIMED; D-47).
# The DUT is the MDR + external-bus port; the testbench supplies the clock, the decoded
# control lines, and a behavioural memory model (outside the CPU — R-SIM-3). Artifacts -> /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

OUT=/tmp/blip_mem
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/memory_interface.v" \
    "$ROOT/sim/tb/mem/tb_mem.v"

vvp "$OUT/tb"
