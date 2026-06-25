#!/usr/bin/env python3
"""Directed image: a WAIT holding TAS_LOCK=LOCK, for the bus-arbiter test."""
import sys, tomllib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields
SEG, NWCS, NSEG = 4096, 11, 13
PROGRAM = {0: dict(USEQ_OP="WAIT", TAS_LOCK="LOCK")}
def main():
    spec = tomllib.load((ROOT/"microcode"/"control_word.toml").open("rb")); F = Fields(spec)
    def pack(fields):
        w = 0
        for name, val in fields.items():
            f = F.by_name[name]; code = val if isinstance(val, int) else F.code_of(name, val)
            w |= (code & f["mask"]) << f["lsb"]
        return w
    img = bytearray(NSEG*SEG)
    for addr, fields in PROGRAM.items():
        w = pack(fields)
        for k in range(NWCS): img[k*SEG+addr] = (w >> (8*k)) & 0xFF
    out = ROOT/"microcode"/"build"; out.mkdir(parents=True, exist_ok=True)
    (out/"tasx_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print("tasx_test.hex: WAIT, TAS_LOCK=LOCK")


if __name__ == "__main__":
    raise SystemExit(main())
