#!/usr/bin/env bash
# Build + run the byte-lane steer unit testbench under Icarus (-gspecify, TIMED; D-47).
# The DUTs are the two combinational steer blocks (left_lane + z_lane); the bench drives every
# LEFT_LANE / Z_LANE mode and checks the steered output. Artifacts -> /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

OUT=/tmp/blip_lane
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/left_lane.v" "$ROOT/hdl/z_lane.v" \
    "$ROOT/sim/tb/lane/tb_lane.v"

vvp "$OUT/tb"
