#!/usr/bin/env bash
# Build + run the right_bus testbench under Icarus (-gspecify, TIMED; D-47).
# The DUT is the ALU RIGHT source bus (scratch + const-gen); the testbench selects each
# RIGHT_SRC and checks the bus value. Artifacts -> /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

OUT=/tmp/blip_right
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/right_bus.v" \
    "$ROOT/sim/tb/right/tb_right.v"

vvp "$OUT/tb"
