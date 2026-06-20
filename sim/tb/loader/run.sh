#!/usr/bin/env bash
# Build + run the boot-loader testbench under Icarus. Verifies the boot loader
# fans the single EEPROM image out to all 13 control-store SRAMs correctly.
# Build artifacts go to /tmp (off the repo tree).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IMG="$ROOT/microcode/build/blip_microcode.hex"

if [ ! -f "$IMG" ]; then
    echo "missing $IMG"
    echo "  run: python3 tools/uasm/uasm.py"
    exit 1
fi

OUT=/tmp/blip_loader
mkdir -p "$OUT"

iverilog -g2012 -Wall -D IMG="\"$IMG\"" -o "$OUT/tb" \
    "$ROOT/hdl/cells/sst39sf010a.v" \
    "$ROOT/hdl/cells/is61c64.v" \
    "$ROOT/hdl/boot/boot_loader.v" \
    "$ROOT/sim/tb/loader/tb_loader.v"

vvp "$OUT/tb"
