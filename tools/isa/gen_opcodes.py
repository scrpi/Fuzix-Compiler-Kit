#!/usr/bin/env python3
"""BLIP opcode-map generator + validator.

Single source of truth: isa/opcodes.toml. Every other opcode artifact derives
from it (R-BUILD-3 discipline, toolchain.md P1): the isa.md §8.2 inventory table,
the future assembler mnemonic table (as6-blip), and the D-40 opcode→start-address
map. Do not hand-edit those; edit isa/opcodes.toml and regenerate.

Subcommands:
  check      validate bytes (unique / dense / in-range / length budget); exit 1 on error
  emit-md    print the §8.2 page sections (markdown) to stdout
  write-md   splice emit-md into docs/isa.md between the inventory markers
  emit-json  print a JSON opcode list for the assembler

The byte assignment is mechanical and sequential per page; 0x80 is reserved as the
page-1 prefix and so is skipped on page 0 (isa.md §5.1, §8.1; D-41, D-48).
"""
import argparse, json, sys, tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOML = ROOT / "isa" / "opcodes.toml"
ISA_MD = ROOT / "docs" / "isa.md"
BEGIN = "<!-- BEGIN opcode-inventory (generated from isa/opcodes.toml by tools/isa/gen_opcodes.py — do not edit by hand) -->"
END = "<!-- END opcode-inventory -->"
PAGE_TITLE = {0: "hot (no prefix)", 1: "cold (`0x80` prefix)"}


def load():
    return tomllib.loads(TOML.read_text())["op"]


def by_page(ops):
    return {p: [o for o in ops if o["page"] == p] for p in (0, 1)}


def expected_bytes(n, page):
    out, b = [], 0
    for _ in range(n):
        if page == 0 and b == 0x80:
            b += 1
        out.append(b)
        b += 1
    return out


def check(ops):
    errs = []
    pages = by_page(ops)
    for page, pl in pages.items():
        maxlen = 3 if page == 0 else 4
        bs = [o["byte"] for o in pl]
        for o in pl:
            if not 0 <= o["byte"] <= 0xFF:
                errs.append(f"page{page} {o['mnem']!r}: byte 0x{o['byte']:X} out of range")
            if page == 0 and o["byte"] == 0x80:
                errs.append(f"page0 {o['mnem']!r}: uses 0x80 (reserved page-1 prefix)")
            if o["length"] > maxlen:
                errs.append(f"page{page} {o['mnem']!r}: length {o['length']} > {maxlen}")
        dup = sorted({x for x in bs if bs.count(x) > 1})
        if dup:
            errs.append(f"page{page}: duplicate bytes {[hex(x) for x in dup]}")
        if sorted(bs) != expected_bytes(len(pl), page):
            errs.append(f"page{page}: bytes are not dense/sequential from 0x00 (0x80 skipped on page0)")
    for page, pl in pages.items():
        free = (255 if page == 0 else 256) - len(pl)
        print(f"page{page}: {len(pl)} opcodes, {free} free")
    if errs:
        print("FAIL:")
        for e in errs:
            print("  - " + e)
        return 1
    print("OK: dense, unique, in-range, within length budget")
    return 0


def emit_md(ops):
    out = []
    for page in (0, 1):
        pl = by_page(ops)[page]
        out += [f"#### Page {page} — {PAGE_TITLE[page]}, {len(pl)} opcodes", ""]
        groups = []
        for o in pl:
            if o["group"] not in groups:
                groups.append(o["group"])
        for g in groups:
            gops = [o for o in pl if o["group"] == g]
            toks = ", ".join(f"`{o['byte']:02X} {o['mnem']}`" for o in gops)
            out += [f"**{g} — {len(gops)}.**", toks, ""]
    return "\n".join(out).rstrip() + "\n"


def write_md(ops):
    md = ISA_MD.read_text()
    if BEGIN not in md or END not in md:
        sys.exit("inventory markers not found in docs/isa.md")
    pre, rest = md.split(BEGIN, 1)
    _, post = rest.split(END, 1)
    ISA_MD.write_text(f"{pre}{BEGIN}\n\n{emit_md(ops)}\n{END}{post}")
    print("docs/isa.md inventory rewritten from isa/opcodes.toml")


def emit_json(ops):
    keys = ("mnem", "page", "byte", "trailing", "length", "priv")
    print(json.dumps([{k: o[k] for k in keys} for o in ops], indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cmd", choices=["check", "emit-md", "write-md", "emit-json"])
    cmd = ap.parse_args().cmd
    ops = load()
    if cmd == "check":
        sys.exit(check(ops))
    if cmd == "emit-md":
        print(emit_md(ops))
    if cmd == "write-md":
        write_md(ops)
    if cmd == "emit-json":
        emit_json(ops)


if __name__ == "__main__":
    main()
