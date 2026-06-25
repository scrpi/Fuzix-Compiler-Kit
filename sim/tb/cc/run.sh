#!/usr/bin/env bash
# Build + run the cc testbench under Icarus (-gspecify, TIMED; D-47).
# The DUT is the condition-code board (register + write logic + condition generation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT=/tmp/blip_cc
mkdir -p "$OUT"
iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/cc_conditions.v" \
    "$ROOT/hdl/cc_register.v" \
    "$ROOT/hdl/cc.v" \
    "$ROOT/sim/tb/cc/tb_cc.v"
vvp "$OUT/tb"
