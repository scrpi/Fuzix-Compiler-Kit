#!/usr/bin/env python3
"""Directed image proving the trap-vector encoder intercepts RETURN_FETCH (microcode.md §2).

A short loop reaches a RETURN_FETCH (the instruction boundary). With no request it goes to the
fetch entry 0; a pending NMI/IRQ redirects the µPC to that trap's fixed microroutine entry
(trap_encoder defaults: NMI_ENTRY=4, IRQ_ENTRY=8). CC.I is cleared first so IRQ is unmasked.

    0  CLR_I ; goto 1                 ; unmask IRQ, then loop
    1  RETURN_FETCH                   ; boundary -> 0 (no trap) / 4 (NMI) / 8 (IRQ)
    4  goto 1   (NMI_ENTRY)           ; NMI handled, back to the loop
    8  goto 1   (IRQ_ENTRY)           ; IRQ handled, back to the loop
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0: dict(USEQ_OP="JUMP", NEXT_ADDR=1, CC_MI_LOAD="CLR_I"),
    1: dict(USEQ_OP="RETURN_FETCH"),
    4: dict(USEQ_OP="JUMP", NEXT_ADDR=1),
    8: dict(USEQ_OP="JUMP", NEXT_ADDR=1),
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
    (out / "trap_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"trap_test.hex: {len(PROGRAM)} microwords (RETURN_FETCH trap interception)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
