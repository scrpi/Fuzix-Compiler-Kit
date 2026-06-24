#!/usr/bin/env bash
# Build + run the register16 testbench under Icarus (-gspecify, TIMED; D-47).
# The DUT is the universal '163-counter register board; the testbench supplies the clock,
# the decoded load/count/drive enables, and the checks. Artifacts -> /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

OUT=/tmp/blip_reg
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/register16.v" \
    "$ROOT/sim/tb/reg/tb_reg.v"

vvp "$OUT/tb"
