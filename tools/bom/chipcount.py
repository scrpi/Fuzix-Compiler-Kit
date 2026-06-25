#!/usr/bin/env python3
"""Chip-count BOM for the BLIP HDL — how many real packages the design is.

BLIP is a board of discrete chips, so "how big is it" is answered in PACKAGES, not
gates: every file in hdl/cells/ models exactly one real chip, and every other module
under hdl/ must elaborate to nothing but instances of those cells (the structural-only
gate, tools/lint/structural_lint.py, enforces this). This tool reports the package
count by letting the elaborator do the honest tally:

    yosys reads the cell library as blackboxes, elaborates a top, FLATTENS the whole
    hierarchy (expanding generate loops and every level of submodule), and `stat`
    counts the surviving instances. One instance == one chip you have to buy, place,
    and solder. No regex, no hand maintenance: the count is whatever the design
    actually elaborates to.

Board-level tops are found automatically: a "root" is any module under hdl/ that no
other module instantiates. `cpu` is the integrated machine; any other root is a block
that is BUILT but not yet wired into cpu (today: the ALU and the RIGHT bus). The moment
such a block gets instantiated by cpu it stops being a root and folds into the cpu
total on its own — nothing here needs editing.

Run:   python3 tools/bom/chipcount.py        (human report)
       python3 tools/bom/chipcount.py --json  (machine-readable, for diffing in CI)
Assumes one module per .v file, named after the file (the repo convention).
"""
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HDL = ROOT / "hdl"
CELLS_DIR = HDL / "cells"


def cell_files():
    return sorted(CELLS_DIR.glob("*.v"))


def dut_files():
    return sorted(p for p in HDL.rglob("*.v") if CELLS_DIR not in p.parents)


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def design_roots(duts):
    """Design modules that NOTHING else instantiates — each is a board-level top.

    A module name is a distinctive identifier (cd74act161, alu_logic, ...) that never
    appears in another module except as an instantiation, so a comment-stripped
    word-boundary search is a reliable test for "is this instantiated anywhere".
    """
    names = [p.stem for p in duts]
    bodies = {p.stem: strip_comments(p.read_text()) for p in duts}
    instantiated = set()
    for owner, body in bodies.items():
        for name in names:
            if name != owner and re.search(rf"\b{re.escape(name)}\b", body):
                instantiated.add(name)
    return [n for n in names if n not in instantiated]


def count_chips(top, cells, duts):
    """Elaborate `top`, flatten the whole hierarchy, return {cell: package_count}."""
    cell_names = {f.stem for f in cells}
    lib = " ".join(str(f) for f in cells)
    src = " ".join(str(f) for f in duts)
    script = (f"read_verilog -lib {lib}; read_verilog {src}; "
              f"hierarchy -top {top}; flatten; stat")
    proc = subprocess.run(["yosys", "-p", script], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"chipcount: yosys failed elaborating top '{top}':\n"
                 f"{proc.stderr or proc.stdout}")
    counts = Counter()
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] in cell_names and parts[1].isdigit():
            counts[parts[0]] += int(parts[1])
    return counts


def fmt_block(title, note, counts):
    total = sum(counts.values())
    kinds = len(counts)
    lines = [f"{title}: {total} chips ({kinds} type{'s' if kinds != 1 else ''}){note}"]
    for cell, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"    {n:4d}  {cell}")
    return "\n".join(lines)


def main(argv):
    as_json = "--json" in argv[1:]
    if not (CELLS_DIR.exists() and any(CELLS_DIR.glob("*.v"))):
        sys.exit(f"chipcount: no cell library at {CELLS_DIR}")
    if subprocess.run(["which", "yosys"], capture_output=True).returncode != 0:
        sys.exit("chipcount: yosys not found (the count comes from the elaborator)")

    cells = cell_files()
    duts = dut_files()
    roots = design_roots(duts)
    # cpu (the integrated machine) first, then the not-yet-wired blocks alphabetically.
    roots.sort(key=lambda r: (r != "cpu", r))

    blocks = {r: count_chips(r, cells, duts) for r in roots}
    grand = Counter()
    for counts in blocks.values():
        grand.update(counts)

    if as_json:
        out = {
            "tops": {
                r: {"total": sum(c.values()),
                    "integrated": r == "cpu",
                    "by_cell": dict(sorted(c.items()))}
                for r, c in blocks.items()
            },
            "grand_total": sum(grand.values()),
            "distinct_types": len(grand),
            "by_cell": dict(sorted(grand.items())),
        }
        print(json.dumps(out, indent=2))
        return 0

    integrated = blocks.get("cpu", Counter())
    print(fmt_block("INTEGRATED CPU (cpu top)", "", integrated))
    for r in roots:
        if r == "cpu":
            continue
        print()
        print(fmt_block(f"{r} (built, NOT yet wired into cpu)", "", blocks[r]))
    print()
    print(fmt_block("GRAND TOTAL (every board-level top in hdl/)", "", grand))
    print()
    parts = " + ".join(f"{r} {sum(blocks[r].values())}" for r in roots)
    print(f"   {parts}  =  {sum(grand.values())} chips")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
