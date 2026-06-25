#!/usr/bin/env bash
# Build + run the cpu microsequencer testbench under Icarus (-gspecify, TIMED; D-47).
# Power-on -> the loader copies the control store -> loading drops -> the real
# microsequencer walks a DIRECTED control-store image (generated here) through
# INC/JUMP/BRANCH/DISPATCH_IR/WAIT, which the bench verifies. Build artifacts go to /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# The directed sequencer-test image (hand-placed microwords; reuses control_word.toml as the
# field-definition source of truth). Regenerated each run.
python3 "$ROOT/sim/tb/useq/mk_useq_image.py"
IMG="$ROOT/microcode/build/useq_test.hex"

OUT=/tmp/blip_useq
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -D IMG="\"$IMG\"" -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/boot/uc_loader.v" \
    "$ROOT/hdl/microsequencer.v" \
    "$ROOT/hdl/microcode_store.v" \
    "$ROOT/hdl/opcode_lut.v" \
    "$ROOT/hdl/control_word_decoder.v" \
    "$ROOT/hdl/register16.v" \
    "$ROOT/hdl/left_lane.v" "$ROOT/hdl/z_lane.v" \
    "$ROOT/hdl/sp_bank.v" "$ROOT/hdl/mmu_entry.v" "$ROOT/hdl/uloop.v" \
    "$ROOT/hdl/memory_interface.v" \
    "$ROOT/hdl/alu_arithmetic.v" "$ROOT/hdl/alu_logic.v" "$ROOT/hdl/alu_shift.v" "$ROOT/hdl/alu.v" \
    "$ROOT/hdl/right_bus.v" \
    "$ROOT/hdl/cc_conditions.v" "$ROOT/hdl/cc_register.v" "$ROOT/hdl/cc.v" \
    "$ROOT/hdl/cpu.v" \
    "$ROOT/sim/tb/useq/tb_useq.v"

vvp "$OUT/tb"
