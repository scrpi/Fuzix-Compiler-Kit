#!/usr/bin/env bash
# Build + run the end-to-end production-microcode testbench under Icarus (-gspecify, TIMED; D-47).
# Assembles the REAL blip.uc and runs a real program (two LD A,$nn) out of harness memory with no
# injection — fetch -> dispatch -> execute -> refetch. Artifacts -> /tmp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 "$ROOT/tools/uasm/uasm.py" >/dev/null
IMG="$ROOT/microcode/build/blip_microcode.hex"
OUT=/tmp/blip_prog
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
    "$ROOT/sim/tb/prog/tb_prog.v"
vvp "$OUT/tb"
