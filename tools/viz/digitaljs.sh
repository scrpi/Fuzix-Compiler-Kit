#!/usr/bin/env bash
# tools/viz/digitaljs.sh — interactive DigitalJS view of a structural HDL block,
# generated from the Verilog (docs/toolchain.md §6, "interactive / animated logic";
# P3). Thin wrapper around tools/viz/digitaljs.js.
#
# Usage:  tools/viz/digitaljs.sh [TOP]
#   Default TOP=uc_loader — a block that fully simulates. The whole `cpu` has a
#   shared bidirectional control-store bus that DigitalJS's functional model can't
#   resolve (it errors with a clear message); use `make viz` for the cpu schematic.
# Output: tools/viz/build/<TOP>.{digitaljs.json,html}   (gitignored — generated)
set -euo pipefail

TOP="${1:-uc_loader}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="tools/viz/build"
mkdir -p "$OUT"

command -v yosys >/dev/null 2>&1 || { echo "error: need 'yosys'" >&2; exit 1; }
command -v node  >/dev/null 2>&1 || { echo "error: need 'node' (Node.js)" >&2; exit 1; }
[ -d tools/viz/node_modules/yosys2digitaljs ] || {
  echo "error: viz deps not installed — run: npm --prefix tools/viz install" >&2; exit 1; }

# Resolve TOP -> the Verilog that defines it: the cell library always, plus only the
# source(s) the top needs (the loader for cpu, which instantiates it). digitaljs.js
# pins `hierarchy -top $TOP`, so we must include TOP's own source — and we add no
# unrelated module that could otherwise shadow it.
FILES=(hdl/cells/*.v)
case "$TOP" in
  cpu)       FILES+=(hdl/boot/uc_loader.v hdl/cpu.v) ;;   # cpu instantiates the loader
  uc_loader) FILES+=(hdl/boot/uc_loader.v) ;;
  *) if   [ -f "hdl/${TOP}.v" ];      then FILES+=("hdl/${TOP}.v")
     elif [ -f "hdl/boot/${TOP}.v" ]; then FILES+=("hdl/boot/${TOP}.v")
     else echo "error: no Verilog source found for TOP='${TOP}'" >&2; exit 1; fi ;;
esac

node tools/viz/digitaljs.js "$TOP" "$OUT" "${FILES[@]}"
