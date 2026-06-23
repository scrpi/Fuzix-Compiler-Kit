#!/usr/bin/env bash
# tools/viz/logisim.sh — keep a Logisim Evolution 4.1.0 .circ in step with the structural
# HDL, straight from the Verilog (docs/toolchain.md §6; P3 generated-not-authored).
#
#   Yosys (cells read -lib, so each 74-series part stays one instance)  ->  JSON netlist
#     ->  tools/viz/logisim.py  ->  generate (first time)  /  reconcile (thereafter)
#
# Like KiCad's schematic->PCB flow: the FIRST run generates the .circ; after that the .circ
# is YOURS to edit and we never overwrite it — we reconcile (LVS diff vs the HDL) and report
# drift. Tunnel<->wire rewiring that stays electrically identical is silently accepted.
#
# Usage:  tools/viz/logisim.sh [TOP] [MODE]
#   TOP   default control_word_decoder (pure TTL — the blocks the reconciler supports).
#   MODE  auto      (default) reconcile if the .circ exists, else generate
#         reconcile  force the LVS check (error if the .circ is missing)
#         insert     reconcile, then splice in any chips the HDL has but the .circ lacks
#         generate   force a fresh .circ — OVERWRITES your edits (first-time / start over)
# Output: logisim/build/<TOP>.{netlist.json,circ}   (gitignored — generated artifacts)
set -euo pipefail

TOP="${1:-control_word_decoder}"
MODE="${2:-auto}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="logisim/build"
CIRC="$OUT/$TOP.circ"
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
NL="${OUT}/${TOP}.netlist.json"

# pick the effective action
if [ "$MODE" = "auto" ]; then
  if [ -f "$CIRC" ]; then MODE="reconcile"; else MODE="generate"; fi
fi

case "$MODE" in
  generate)
    python3 tools/viz/logisim.py generate "$NL" "$TOP" "$CIRC"
    echo "open in Logisim Evolution:  $CIRC" ;;
  reconcile)
    python3 tools/viz/logisim.py reconcile "$NL" "$TOP" "$CIRC" ;;
  insert)
    python3 tools/viz/logisim.py reconcile "$NL" "$TOP" "$CIRC" --insert ;;
  *) echo "error: unknown MODE '$MODE' (auto|reconcile|insert|generate)" >&2; exit 1 ;;
esac
