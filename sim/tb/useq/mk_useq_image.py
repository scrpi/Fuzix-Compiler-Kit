#!/usr/bin/env python3
"""Directed control-store image exercising CALL / RETURN + the µSR (micro-subroutine return reg).

A shared leaf routine at 20 (INC then RETURN) is called from three sites; each RETURN must land on
the caller's NEXT step — proving the µSR is READ (not a constant) and that the µPC+1 adder carries:

    0  CALL 20      ; µSR<-1,  -> 20 .. RETURN -> 1
    1  CALL 20      ; µSR<-2,  -> 20 .. RETURN -> 2
    2  JUMP 15
   15  CALL 20      ; µSR<-16 (0x0F+1, nibble carry), -> 20 .. RETURN -> 16
   16  WAIT
   20  INC          ; the leaf routine body
   21  RETURN
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0:  dict(USEQ_OP="CALL", NEXT_ADDR=20),
    1:  dict(USEQ_OP="CALL", NEXT_ADDR=20),
    2:  dict(USEQ_OP="JUMP", NEXT_ADDR=15),
    15: dict(USEQ_OP="CALL", NEXT_ADDR=20),
    16: dict(USEQ_OP="WAIT"),
    20: dict(USEQ_OP="INC"),
    21: dict(USEQ_OP="RETURN"),
}


def main() -> int:
    spec = tomllib.load((ROOT / "microcode" / "control_word.toml").open("rb"))
    F = Fields(spec)

    def pack(fields: dict) -> int:
        w = 0
        for name, val in fields.items():
            f = F.by_name[name]
            code = val if isinstance(val, int) else F.code_of(name, val)
            w |= (code & f["mask"]) << f["lsb"]
        return w

    img = bytearray(NSEG * SEG)
    for addr, fields in PROGRAM.items():
        w = pack(fields)
        for k in range(NWCS):
            img[k * SEG + addr] = (w >> (8 * k)) & 0xFF

    out = ROOT / "microcode" / "build"
    out.mkdir(parents=True, exist_ok=True)
    (out / "useq_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"useq_test.hex: {len(PROGRAM)} microwords (CALL/RETURN + µSR, with a carry)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
