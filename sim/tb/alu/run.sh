#!/usr/bin/env bash
# Build + run the alu testbench under Icarus (-gspecify, TIMED; D-47).
# The DUT is the 16-bit ALU compute core; the testbench drives operands/op/width and checks
# Z + N/Z/V/C/H against a behavioural reference. Artifacts -> /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

OUT=/tmp/blip_alu
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/alu_arithmetic.v" \
    "$ROOT/hdl/alu_logic.v" \
    "$ROOT/hdl/alu_shift.v" \
    "$ROOT/hdl/alu.v" \
    "$ROOT/sim/tb/alu/tb_alu.v"

vvp "$OUT/tb"
