#!/usr/bin/env bash
# Build + run the cpu top-level testbench under Icarus (-gspecify, TIMED; D-47).
# The single entry point: power-on -> the microcode loader copies the EEPROM into the
# control store -> loading drops -> the micro-PC walks the control store. Verifies the
# booted control words against the image. Build artifacts go to /tmp (off the repo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IMG="$ROOT/microcode/build/blip_microcode.hex"

if [ ! -f "$IMG" ]; then
    echo "missing $IMG"
    echo "  run: python3 tools/uasm/uasm.py"
    exit 1
fi

OUT=/tmp/blip_cpu
mkdir -p "$OUT"

iverilog -g2012 -gspecify -Wall -D IMG="\"$IMG\"" -o "$OUT/tb" \
    "$ROOT/hdl/cells/sst39sf010a.v" \
    "$ROOT/hdl/cells/is61c64.v" \
    "$ROOT/hdl/cells/cd74act161.v" \
    "$ROOT/hdl/cells/sn74ahct138.v" \
    "$ROOT/hdl/cells/sn74ahct157.v" \
    "$ROOT/hdl/cells/sn74ahct04.v" \
    "$ROOT/hdl/cells/sn74ahct541.v" \
    "$ROOT/hdl/cells/sn74ahct32.v" \
    "$ROOT/hdl/boot/uc_loader.v" \
    "$ROOT/hdl/cpu.v" \
    "$ROOT/sim/tb/cpu/tb_cpu.v"

vvp "$OUT/tb"
