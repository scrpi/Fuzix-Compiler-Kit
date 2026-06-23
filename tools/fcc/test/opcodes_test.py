#!/usr/bin/env python3
"""Exhaustive assembler check: every instruction in isa/opcodes.toml assembled
in its canonical form must emit the opcode byte (and the 0x80 page-1 prefix)
the table assigns. This cross-checks the assembler against the single source of
truth for opcode selection across every addressing mode, page, and operand kind.

Run after building: sh tools/fcc/build.sh && python3 tools/fcc/test/opcodes_test.py
"""
import os
import re
import subprocess
import sys
import tempfile
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))     # tools/fcc/test
FCC = os.path.dirname(HERE)                            # tools/fcc
ROOT = os.path.dirname(os.path.dirname(FCC))           # repo root
TOML = os.path.join(ROOT, "isa", "opcodes.toml")
BIN = os.path.join(FCC, "bin")
ASM = os.path.join(BIN, "asblip")
DUMP = os.path.join(BIN, "dumprelocsblip")


def concrete(mnem):
    """Turn a table mnemonic into a concrete, assemblable line. Offsets/immediates
    are sized so each entry selects itself (n8 fits 8-bit, n16 does not)."""
    parts = mnem.split(None, 1)
    if len(parts) == 1:
        return mnem
    verb, s = parts
    s = s.replace("reg,reg", "X,Y")
    s = s.replace("$nnnn", "$1234").replace("$nn", "$12").replace("$n", "$3")
    s = s.replace("n16", "300").replace("n8", "4")
    s = s.replace("rel16", "$100").replace("rel8", "$10").replace("mask8", "$0F")
    return verb + " " + s


def code_bytes(obj):
    out = subprocess.run([DUMP, obj], capture_output=True, text=True).stdout
    seg = out.split("Segment 1:")[1].split("Segment 2:")[0]
    bs = []
    for ln in seg.splitlines():
        m = re.match(r"^[0-9a-fA-F]{4}\t(.*)$", ln)
        if m:
            bs += [int(t, 16) for t in m.group(1).split()
                   if re.fullmatch(r"[0-9A-Fa-f]{2}", t)]
    return bs


def main():
    if not os.path.exists(ASM):
        sys.exit("build first: sh tools/fcc/build.sh")
    ops = tomllib.loads(open(TOML, "rb").read().decode())["op"]
    d = tempfile.mkdtemp()
    src, obj = os.path.join(d, "t.s"), os.path.join(d, "t.o")
    passed, failures = 0, []
    for o in ops:
        asm = concrete(o["mnem"])
        open(src, "w").write("\t.code\n\t%s\n" % asm)
        if os.path.exists(obj):
            os.remove(obj)
        r = subprocess.run([ASM, src], capture_output=True, text=True)
        if not os.path.exists(obj):
            failures.append((o["mnem"], asm, "assemble failed: " + r.stderr.strip()))
            continue
        exp = [0x80, o["byte"]] if o["page"] == 1 else [o["byte"]]
        got = code_bytes(obj)[:len(exp)]
        if got == exp:
            passed += 1
        else:
            failures.append((o["mnem"], asm,
                             "got %s expected %s" % ([hex(x) for x in got],
                                                     [hex(x) for x in exp])))
    print("PASS %d / %d" % (passed, len(ops)))
    for mnem, asm, why in failures:
        print("  FAIL %-24r asm=%-22r %s" % (mnem, asm, why))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
