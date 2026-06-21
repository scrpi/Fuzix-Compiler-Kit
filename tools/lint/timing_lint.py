#!/usr/bin/env python3
"""Timing-presence lint — the always-timed simulation policy (D-47, R-SIM-6).

BLIP runs two engines for two jobs: Verilator (zero-delay) is the functional
engine; Icarus is ALWAYS run timed (-gspecify) so every regression exercises real
propagation delays (R-SIM-1). For that to mean anything, two invariants must hold,
and this lint enforces them:

  1. Every cell model carries timing — a `specify` block (combinational path
     delays) and/or an intra-assignment `#` clock-to-output delay (sequential
     cells, since Icarus mishandles a specify clk->Q path). A cell with neither is
     untimed and would run as zero-delay even under -gspecify.

  2. Every Icarus runner passes `-gspecify`. An `iverilog` invocation without it
     silently runs zero-delay — the mode we retired; functional checks are
     Verilator's job.

This is a textual check (the yosys structural gate blackboxes cells, so it cannot
see their timing). It checks that timing is PRESENT, not that the numbers are
datasheet-sourced — that quality bar (toolchain.md §10.3) is tracked separately.

Run: python3 tools/lint/timing_lint.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CELLS_DIR = ROOT / "hdl" / "cells"
SIM_DIR = ROOT / "sim"

HASH_DELAY = re.compile(r"#\s*\d")          # intra-assignment / gate delay: #15, # 8


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)   # block comments
    text = re.sub(r"//[^\n]*", "", text)                     # line comments
    return text


def main():
    fails = []

    print("timing lint: every cell carries timing; every Icarus runner is -gspecify\n")

    # 1. every cell carries timing (after stripping comments, so prose doesn't count)
    for f in sorted(CELLS_DIR.glob("*.v")):
        code = strip_comments(f.read_text())
        has_specify = "specify" in code
        has_delay = bool(HASH_DELAY.search(code))
        rel = f.relative_to(ROOT).as_posix()
        if has_specify or has_delay:
            kinds = ", ".join(k for k, v in (("specify", has_specify),
                                             ("#delay", has_delay)) if v)
            print(f"  ok           {rel}  [{kinds}]")
        else:
            print(f"  NO TIMING    {rel}  - add specify path delays or a # clk->Q delay")
            fails.append(rel)

    # 2. every Icarus runner is timed
    for sh in sorted(SIM_DIR.rglob("*.sh")):
        text = sh.read_text()
        if "iverilog" not in text:
            continue
        rel = sh.relative_to(ROOT).as_posix()
        if "-gspecify" in text:
            print(f"  ok           {rel}  [iverilog -gspecify]")
        else:
            print(f"  UNTIMED      {rel}  - iverilog without -gspecify (functional = Verilator)")
            fails.append(rel)

    print()
    if fails:
        print(f"FAIL - {len(fails)} item(s): {', '.join(fails)}")
        return 1
    print("PASS - every cell carries timing and every Icarus runner is -gspecify")
    return 0


if __name__ == "__main__":
    sys.exit(main())
