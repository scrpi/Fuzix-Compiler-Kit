#!/usr/bin/env bash
# tools/viz/render.sh — generate a schematic SVG of the structural HDL straight from
# the Verilog (docs/toolchain.md §6, "the plumbing"; P3). The picture is GENERATED,
# never authored, so it cannot drift from hdl/ (toolchain.md P3).
#
#   Yosys (each 74-series cell as one black box; elaborate the top)  ->  JSON netlist
#     ->  netlistsvg  ->  SVG     (->  PNG preview if a rasterizer is present)
#
# Usage:  tools/viz/render.sh [TOP]
#   With no TOP: render EVERY block (each hdl/ module — cpu and the factored blocks).
#   With a TOP:  render just that one (e.g. `render.sh microsequencer`).
# Each block is drawn with its OWN cells direct and every OTHER module (cells + the
# sibling blocks) as a black box, so a sub-block instance shows as one labelled box —
# the same "module under test, everything else blackboxed" view as the structural lint.
# Output: tools/viz/build/<TOP>.{json,svg,png}   (gitignored — generated artifacts)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="tools/viz/build"
mkdir -p "$OUT"

# Pick a Yosys: a native install if present, else the pip WASM build (yowasp-yosys).
if   command -v yosys        >/dev/null 2>&1; then YOSYS=yosys
elif command -v yowasp-yosys >/dev/null 2>&1; then YOSYS=yowasp-yosys
else echo "error: need 'yosys' (or 'pip install yowasp-yosys')" >&2; exit 1; fi
# Prefer the repo-local netlistsvg (tools/viz/node_modules, from `npm --prefix
# tools/viz install`); fall back to a global install on PATH.
if   [ -x tools/viz/node_modules/.bin/netlistsvg ]; then NETLISTSVG=tools/viz/node_modules/.bin/netlistsvg
elif command -v netlistsvg >/dev/null 2>&1;          then NETLISTSVG=netlistsvg
else echo "error: need 'netlistsvg' — run: npm --prefix tools/viz install" >&2; exit 1; fi

# Every DUT module is one hdl/ file named after the module (the repo convention the
# structural lint relies on); the cell library is hdl/cells/.
DUTS=(hdl/boot/*.v hdl/*.v)

render_one() {
  local TOP="$1"
  # Resolve TOP's source; everything else (cells + sibling blocks) is a black box, so
  # each instantiated sub-block is drawn as ONE labelled box (the wiring is the subject).
  local topfile="" others=()
  local f
  for f in "${DUTS[@]}"; do
    if [ "$(basename "$f" .v)" = "$TOP" ]; then topfile="$f"; else others+=("$f"); fi
  done
  if [ -z "$topfile" ]; then
    echo "error: no module '$TOP' under hdl/ (have: $(for f in "${DUTS[@]}"; do basename "$f" .v; done | tr '\n' ' '))" >&2
    return 1
  fi

  # 1. Elaborate TOP with all other modules blackboxed.
  "$YOSYS" -q -p "
    read_verilog -lib hdl/cells/*.v ${others[*]};
    read_verilog ${topfile};
    hierarchy -top ${TOP};
    proc;
    write_json ${OUT}/${TOP}.json
  "

  # 2. Two render-only JSON rewrites. Neither touches the nets or the BOM — they only
  #    change what netlistsvg DRAWS:
  #    a. netlistsvg's schema only allows input/output, but this design has real
  #       bidirectional buses (the SRAM io, the EEPROM dq). Coerce inout->input for
  #       drawing only — the nets are unchanged, just the drawn pin side.
  #    b. Label each chip with its PURPOSE. netlistsvg titles a generic box with the cell
  #       TYPE (the part number) only. We prepend each chip's `(* purpose = "..." *)`
  #       attribute — authored in the HDL, so the label is GENERATED from source and can't
  #       drift (toolchain.md P3) — falling back to the instance name when none is given.
  #       The part number is kept in parentheses, so the box still reads as a real part.
  python3 - "${OUT}/${TOP}.json" <<'PY'
import json, sys
from xml.sax.saxutils import escape   # labels become SVG <text>; netlistsvg does NOT escape
p = sys.argv[1]; d = json.load(open(p))
for m in d.get("modules", {}).values():
    for port in m.get("ports", {}).values():
        if port.get("direction") == "inout": port["direction"] = "input"
    for name, cell in m.get("cells", {}).items():
        pd = cell.get("port_directions", {})
        for k, v in list(pd.items()):
            if v == "inout": pd[k] = "input"
        t = cell.get("type", "")
        if t.startswith("$"):            # yosys builtins (constants, $_split_/$_join_) keep their glyph
            continue
        note = (cell.get("attributes", {}) or {}).get("purpose") or name
        # XML-escape (& < >) so a label like "ADD&ALU_CIN" or "Z<-SUM" can't break the SVG.
        cell["type"] = f"{escape(str(note))}  ({escape(t)})"  # "<purpose | instance>  (<part number>)"
json.dump(d, open(p, "w"))
PY

  # 3. Render the schematic (the real artifact).
  "$NETLISTSVG" "${OUT}/${TOP}.json" -o "${OUT}/${TOP}.svg"
  echo "schematic: ${OUT}/${TOP}.svg"

  # 4. Optional PNG preview for quick viewing; the SVG is authoritative.
  if python3 -c "import cairosvg" >/dev/null 2>&1; then
    python3 -c "import cairosvg; cairosvg.svg2png(url='${OUT}/${TOP}.svg', write_to='${OUT}/${TOP}.png')"
    echo "preview:   ${OUT}/${TOP}.png"
  fi
}

# No TOP -> render every block; otherwise just the named one. Render-all is best-effort:
# a block that fails to elaborate doesn't stop the others, but the run still exits nonzero.
if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  render_one "$1"
else
  rc=0
  for f in "${DUTS[@]}"; do
    render_one "$(basename "$f" .v)" || { echo "error: failed to render $(basename "$f" .v)" >&2; rc=1; }
  done
  exit $rc
fi
