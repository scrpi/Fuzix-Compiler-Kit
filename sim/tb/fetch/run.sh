#!/usr/bin/env bash
# Build + run the real-fetch testbench under Icarus (-gspecify, TIMED; D-47).
# Power-on -> the loader copies a DIRECTED fetch image into the control store -> the CPU
# fetches opcode 0x42 from a behavioural memory model (PC -> MMU -> bus -> MDR -> IR) and
# dispatches on it. Build artifacts go to /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# The directed fetch image (read mem[PC] -> MDR -> IR -> DISPATCH). Regenerated each run.
python3 "$ROOT/sim/tb/fetch/mk_fetch_image.py"
IMG="$ROOT/microcode/build/fetch_test.hex"

OUT=/tmp/blip_fetch
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -D IMG="\"$IMG\"" -o "$OUT/tb" \
    "$ROOT"/hdl/cells/*.v \
    "$ROOT/hdl/boot/uc_loader.v" \
    "$ROOT/hdl/microsequencer.v" "$ROOT/hdl/trap_encoder.v" \
    "$ROOT/hdl/microcode_store.v" \
    "$ROOT/hdl/opcode_lut.v" \
    "$ROOT/hdl/control_word_decoder.v" \
    "$ROOT/hdl/register16.v" \
    "$ROOT/hdl/left_lane.v" "$ROOT/hdl/z_lane.v" \
    "$ROOT/hdl/sp_bank.v" "$ROOT/hdl/mmu_entry.v" "$ROOT/hdl/mmu.v" "$ROOT/hdl/uloop.v" \
    "$ROOT/hdl/memory_interface.v" \
    "$ROOT/hdl/alu_arithmetic.v" "$ROOT/hdl/alu_logic.v" "$ROOT/hdl/alu_shift.v" "$ROOT/hdl/alu.v" \
    "$ROOT/hdl/right_bus.v" \
    "$ROOT/hdl/cc_conditions.v" "$ROOT/hdl/cc_register.v" "$ROOT/hdl/cc.v" \
    "$ROOT/hdl/cpu.v" \
    "$ROOT/sim/tb/fetch/tb_fetch.v"

vvp "$OUT/tb"
