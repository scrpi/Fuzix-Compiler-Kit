#!/usr/bin/env python3
"""Structural-only HDL gate — the DUT must be a netlist of REAL chips.

BLIP's simulation is only meaningful if what it runs is what we will build: a
board of discrete chips wired together. So every module under hdl/ EXCEPT the
cell library (hdl/cells/, where each file is one real chip modeled behaviorally
from its datasheet) must elaborate to nothing but instances of those cells plus
wires and constant ties — ZERO inferred logic. Any synthetic operator (+ & | ^
~, compares, ?:, shifts), any always/if/case, even a bare Verilog primitive,
turns into a $-prefixed RTLIL cell during elaboration and is rejected here.

Mechanism: yosys reads the cell library (and every other DUT module) as
blackboxes, elaborates the module under test, runs `proc`, and asserts that
selecting `t:$*` (all inferred-logic cells) matches nothing.

Quarantine: known-synthetic placeholders are listed in QUARANTINE with the
reason they aren't structural yet. They are EXPECTED to fail the structural
check, and this gate verifies they still do — so the list can't silently rot.
When you rebuild one from real cells, the gate reports it as structural and
fails until you delete its QUARANTINE entry.

Run:  python3 tools/lint/structural_lint.py
Assumes one module per .v file, named after the file (the repo convention).
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HDL = ROOT / "hdl"
CELLS_DIR = HDL / "cells"

# DUT module file (path relative to repo root) -> why it is not yet structural.
QUARANTINE = {
    "hdl/boot/boot_loader.v":
        "functional placeholder; rebuild from a ttl_161 counter chain + a "
        "ttl_154 4->16 decoder + gates (toolchain.md §4.1)",
}


def cell_files():
    return sorted(CELLS_DIR.glob("*.v"))


def dut_files():
    return sorted(p for p in HDL.rglob("*.v") if CELLS_DIR not in p.parents)


def structural_check(module_file, top, blackbox_files):
    """Elaborate `top` with everything else blackboxed; return (is_structural,
    sorted set of synthetic $-cell types found)."""
    lib = " ".join(str(f) for f in blackbox_files)
    script = "\n".join([
        f"read_verilog -lib {lib}" if lib else "",
        f"read_verilog {module_file}",
        f"hierarchy -top {top}",
        "proc",
        "stat",
        "select -assert-none t:$*",   # no shell here -> $* is literal to yosys
    ])
    r = subprocess.run(["yosys", "-q", "-p", script],
                       capture_output=True, text=True)
    synth = sorted({ln.split()[0] for ln in r.stdout.splitlines()
                    if ln.lstrip().startswith("$")})
    return r.returncode == 0, synth


def main():
    cells = cell_files()
    duts = dut_files()
    print(f"structural-only gate: {len(duts)} DUT module(s), "
          f"{len(cells)} cell model(s), {len(QUARANTINE)} quarantined\n")

    fails = []
    for f in duts:
        rel = f.relative_to(ROOT).as_posix()
        top = f.stem
        others = [d for d in duts if d != f]
        ok, synth = structural_check(f, top, cells + others)

        if rel in QUARANTINE:
            if ok:
                print(f"  STALE QUARANTINE   {rel}")
                print(f"        now structural — delete its QUARANTINE entry")
                fails.append(rel)
            else:
                print(f"  quarantined        {rel}  [{', '.join(synth)}]")
                print(f"        {QUARANTINE[rel]}")
        elif ok:
            print(f"  ok (structural)    {rel}")
        else:
            print(f"  SYNTHETIC LOGIC    {rel}  [{', '.join(synth) or 'inferred logic'}]")
            fails.append(rel)

    print()
    if fails:
        print(f"FAIL — {len(fails)} module(s) need attention: {', '.join(fails)}")
        return 1
    print("PASS — every DUT module is a structural netlist of real chips "
          "(quarantined placeholders excepted)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
