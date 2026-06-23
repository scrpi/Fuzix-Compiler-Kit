#!/usr/bin/env bash
# tools/viz/logisim.sh — generate a runnable Logisim Evolution 4.1.0 .circ for a structural
# HDL block, straight from the Verilog (docs/toolchain.md §6; P3 generated-not-authored).
#
#   Yosys (cells read -lib, so each 74-series part stays one instance)  ->  JSON netlist
#     ->  tools/viz/logisim.py  ->  .circ   (TTL chips + named-tunnel connectivity)
#
# Usage:  tools/viz/logisim.sh [TOP]
#   Default TOP=control_word_decoder (pure TTL — the first block the generator supports).
# Output: logisim/build/<TOP>.{netlist.json,circ}   (gitignored — generated artifacts)
set -euo pipefail

TOP="${1:-control_word_decoder}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="logisim/build"
mkdir -p "$OUT"

command -v yosys   >/dev/null 2>&1 || { echo "error: need 'yosys'" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: need 'python3'" >&2; exit 1; }

# Resolve TOP -> its Verilog source (the cell library is always read as -lib so the cells
# stay as instances). Sub-block hierarchy (the whole cpu) is a later step.
case "$TOP" in
  uc_loader) SRC="hdl/boot/uc_loader.v" ;;
  *) if   [ -f "hdl/${TOP}.v" ];      then SRC="hdl/${TOP}.v"
     elif [ -f "hdl/boot/${TOP}.v" ]; then SRC="hdl/boot/${TOP}.v"
     else echo "error: no Verilog source for TOP='${TOP}'" >&2; exit 1; fi ;;
esac

yosys -q -p "
  read_verilog -lib hdl/cells/*.v;
  read_verilog ${SRC};
  hierarchy -top ${TOP};
  proc;
  write_json ${OUT}/${TOP}.netlist.json
"

python3 tools/viz/logisim.py "${OUT}/${TOP}.netlist.json" "${TOP}" "${OUT}/${TOP}.circ"
echo "open in Logisim Evolution:  ${OUT}/${TOP}.circ"
