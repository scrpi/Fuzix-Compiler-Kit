#!/usr/bin/env bash
# Build + run the boot-loader testbench under Icarus. Verifies the boot loader
# fans the single EEPROM image out to all 13 control-store SRAMs correctly.
# Build artifacts go to /tmp (off the repo tree).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMG="$ROOT/microcode/build/blip_microcode.hex"

if [ ! -f "$IMG" ]; then
    echo "missing $IMG"
    echo "  run: python3 microcode/uasm.py microcode/blip.uc"
    exit 1
fi

OUT=/tmp/blip_loader
mkdir -p "$OUT"

iverilog -g2012 -Wall -D IMG="\"$IMG\"" -o "$OUT/tb" \
    "$ROOT/rtl/mem/rom.v" \
    "$ROOT/rtl/mem/sram.v" \
    "$ROOT/rtl/ctrl/boot_loader.v" \
    "$ROOT/sim/loader/tb_loader.v"

vvp "$OUT/tb"
