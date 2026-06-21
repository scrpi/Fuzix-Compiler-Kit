#!/usr/bin/env bash
# tools/viz/render.sh — generate a schematic SVG of the structural HDL straight from
# the Verilog (docs/toolchain.md §6, "the plumbing"; P3). The picture is GENERATED,
# never authored, so it cannot drift from hdl/ (toolchain.md P3).
#
#   Yosys (each 74-series cell as one black box; elaborate the top)  ->  JSON netlist
#     ->  netlistsvg  ->  SVG     (->  PNG preview if a rasterizer is present)
#
# Usage:  tools/viz/render.sh [TOP]        # default TOP=cpu; e.g. uc_loader
# Output: tools/viz/build/<TOP>.{json,svg,png}   (gitignored — a generated artifact)
set -euo pipefail

TOP="${1:-cpu}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="tools/viz/build"
mkdir -p "$OUT"

# Pick a Yosys: a native install if present, else the pip WASM build (yowasp-yosys).
if   command -v yosys        >/dev/null 2>&1; then YOSYS=yosys
elif command -v yowasp-yosys >/dev/null 2>&1; then YOSYS=yowasp-yosys
else echo "error: need 'yosys' (or 'pip install yowasp-yosys')" >&2; exit 1; fi
command -v netlistsvg >/dev/null 2>&1 || {
  echo "error: need 'netlistsvg' (npm install -g netlistsvg)" >&2; exit 1; }

# 1. Elaborate. The cell library is read as black boxes (-lib) so each 74-series chip
#    is drawn as ONE box — the wiring is the subject, the datasheet behaviour is not —
#    which also sidesteps the inout/memory bodies in the cell models.
"$YOSYS" -q -p "
  read_verilog -lib hdl/cells/*.v;
  read_verilog hdl/boot/uc_loader.v hdl/cpu.v;
  hierarchy -top ${TOP};
  proc;
  write_json ${OUT}/${TOP}.json
"

# 2. netlistsvg's schema only allows input/output, but this design has real
#    bidirectional buses (the SRAM io, the EEPROM dq). Coerce inout->input in the
#    JSON for rendering only — the nets are unchanged, just the drawn pin side.
python3 - "${OUT}/${TOP}.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for m in d.get("modules", {}).values():
    for port in m.get("ports", {}).values():
        if port.get("direction") == "inout": port["direction"] = "input"
    for cell in m.get("cells", {}).values():
        pd = cell.get("port_directions", {})
        for k, v in list(pd.items()):
            if v == "inout": pd[k] = "input"
json.dump(d, open(p, "w"))
PY

# 3. Render the schematic (the real artifact).
netlistsvg "${OUT}/${TOP}.json" -o "${OUT}/${TOP}.svg"
echo "schematic: ${OUT}/${TOP}.svg"

# 4. Optional PNG preview for quick viewing; the SVG is authoritative.
if python3 -c "import cairosvg" >/dev/null 2>&1; then
  python3 -c "import cairosvg; cairosvg.svg2png(url='${OUT}/${TOP}.svg', write_to='${OUT}/${TOP}.png')"
  echo "preview:   ${OUT}/${TOP}.png"
fi
