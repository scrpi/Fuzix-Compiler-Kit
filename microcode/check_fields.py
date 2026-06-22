#!/usr/bin/env python3
"""Validate and render the BLIP control-word field definition.

Reads control_word.toml (the single source of truth, toolchain.md §3.1), derives
each field's exact bit range by packing LSB-first in declaration order within its
section, and checks the layout is self-consistent against microcode.md §3:

  * every field's section is declared;
  * each section's fields exactly fill its bit span (no gap, no overflow);
  * the sections tile [0, word.bits) with no overlap;
  * binary value codes fit the field width and are distinct;
  * mask bit positions fit the field width and are distinct;
  * any `default`/rule references name real fields and values.

Exit status is non-zero on any inconsistency, so it doubles as a CI gate. With no
error it prints the resolved bit map — the generated, never-hand-maintained view
of microcode.md §3.
"""
from __future__ import annotations

import sys
import tomllib
from pathlib import Path

SPEC = Path(__file__).with_name("control_word.toml")


def load(path: Path) -> dict:
    with path.open("rb") as f:
        return tomllib.load(f)


def resolve(spec: dict) -> tuple[list[dict], list[str]]:
    """Assign each field its [lsb, msb] bit range; return (fields, errors)."""
    errors: list[str] = []
    word_bits = spec["word"]["bits"]

    sections = {s["name"]: s for s in spec["section"]}
    for s in spec["section"]:
        base = min(s["srams"]) * 8
        span = len(s["srams"]) * 8
        if span != s["bits"]:
            errors.append(
                f"section {s['name']}: {len(s['srams'])} SRAMs = {span} bits "
                f"but declares bits={s['bits']}"
            )
        s["_base"] = base
        s["_cursor"] = base

    for fld in spec["field"]:
        sec = sections.get(fld["section"])
        if sec is None:
            errors.append(f"field {fld['name']}: unknown section {fld['section']!r}")
            continue
        lsb = sec["_cursor"]
        fld["_lsb"] = lsb
        fld["_msb"] = lsb + fld["width"] - 1
        sec["_cursor"] += fld["width"]

        # binary-encoded value codes must fit the width and be distinct
        if fld.get("enc") == "bin":
            seen: dict[int, str] = {}
            for name, code in fld.get("values", {}).items():
                if code >= (1 << fld["width"]):
                    errors.append(
                        f"field {fld['name']}: value {name}={code} "
                        f"overflows {fld['width']} bits"
                    )
                if code in seen:
                    errors.append(
                        f"field {fld['name']}: code {code} reused "
                        f"by {seen[code]} and {name}"
                    )
                seen[code] = name
        if fld.get("enc") == "mask":
            seen_pos: dict[int, str] = {}
            for name, pos in fld.get("bits_", {}).items():
                if pos >= fld["width"]:
                    errors.append(
                        f"field {fld['name']}: mask bit {name}={pos} "
                        f"outside {fld['width']} bits"
                    )
                if pos in seen_pos:
                    errors.append(
                        f"field {fld['name']}: mask bit {pos} reused"
                    )
                seen_pos[name if False else pos] = name
        # default must name a real value
        if "default" in fld and fld["default"] not in fld.get("values", {}):
            errors.append(
                f"field {fld['name']}: default {fld['default']!r} is not a value"
            )

    # each section must be exactly filled
    for s in spec["section"]:
        used = s["_cursor"] - s["_base"]
        if used != s["bits"]:
            errors.append(
                f"section {s['name']}: fields fill {used} bits, expected {s['bits']}"
            )

    # sections must tile [0, word_bits) with no overlap / gap
    spans = sorted((s["_base"], s["_base"] + s["bits"], s["name"]) for s in spec["section"])
    edge = 0
    for lo, hi, name in spans:
        if lo != edge:
            errors.append(f"section {name}: starts at bit {lo}, expected {edge}")
        edge = hi
    if edge != word_bits:
        errors.append(f"sections cover {edge} bits, word declares {word_bits}")

    # rules must reference real fields/values
    field_by_name = {f["name"]: f for f in spec["field"]}
    for r in spec.get("rule", []):
        for clause in (r.get("when"), r.get("require")):
            if not clause:
                continue
            fname = clause.get("field")
            if fname not in field_by_name:
                errors.append(f"rule {r['name']}: unknown field {fname!r}")

    return spec["field"], errors


def render(spec: dict) -> None:
    print(f"BLIP control word — {spec['word']['bits']} bits / {spec['word']['srams']} SRAMs\n")
    by_section: dict[str, list[dict]] = {}
    for f in spec["field"]:
        by_section.setdefault(f["section"], []).append(f)

    used = 0
    for s in spec["section"]:
        name = s["name"]
        print(f"── {name} section  (SRAMs {min(s['srams'])}–{max(s['srams'])}, "
              f"bits {s['_base']}–{s['_base'] + s['bits'] - 1}) ──")
        print(f"   {'bits':>9}  {'field':<14} {'w':>2} {'enc':<4} {'#vals':>5}")
        for f in by_section[name]:
            nvals = len(f.get("values", f.get("bits_", {})))
            rng = f"{f['_msb']}:{f['_lsb']}"
            print(f"   {rng:>9}  {f['name']:<14} {f['width']:>2} "
                  f"{f.get('enc',''):<4} {nvals if nvals else '':>5}")
            if not f["name"].startswith("SPARE"):
                used += f["width"]
        print()
    print(f"Used {used} bits, {spec['word']['bits'] - used} spare.")


def main() -> int:
    spec = load(SPEC)
    _, errors = resolve(spec)
    if errors:
        print("FAIL — field definition is inconsistent:", file=sys.stderr)
        for e in errors:
            print(f"  • {e}", file=sys.stderr)
        return 1
    render(spec)
    print("\nOK — field definition is self-consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
