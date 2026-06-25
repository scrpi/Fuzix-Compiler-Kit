#!/usr/bin/env python3
"""Directed image for the fault detectors (PRIV_VIOLATION + ILLEGAL_OPCODE -> cond[13]/[14]).

Holds DISPATCH_PAGE=PAGE1 so the opcode LUT (indexed by {page, IR}) sees the injected page-1
opcode, and drops to user mode mid-way so the bench can read the priv/illegal detectors at CC.M=1
and CC.M=0:

    0  (M=1) hold the page-1 index                 ; supervisor: no priv violation
    1  CC <- whole(0)                              ; drop to user (M=0)
    2  (M=0) WAIT                                  ; user: a priv opcode now violates
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0: dict(USEQ_OP="INC", DISPATCH_PAGE="PAGE1"),
    1: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_0", CC_WRITE_SRC="WHOLE_Z", DISPATCH_PAGE="PAGE1"),
    2: dict(USEQ_OP="WAIT", DISPATCH_PAGE="PAGE1"),
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

    # Populate the opcode-LUT entries the bench probes (segments 11/12 = LUT low/high).
    # entry = 12-bit addr | priv<<12 | valid<<13 ; lut_hi byte = (entry>>8) & 0x3F.
    SEG_LUT_LO, SEG_LUT_HI = 11, 12

    def set_lut(page, byte, priv):
        idx = (page << 8) | byte
        entry = 0x100 | (priv << 12) | (1 << 13)         # any addr + priv? + VALID
        img[SEG_LUT_LO * SEG + idx] = entry & 0xFF
        img[SEG_LUT_HI * SEG + idx] = (entry >> 8) & 0x3F

    set_lut(1, 0x07, priv=1)        # SEI: page1, privileged, bound
    set_lut(1, 0x00, priv=0)        # DAA: page1, not privileged, bound
    # page1 0xFF left unbound (entry 0) -> VALID=0 -> illegal-opcode.

    out = ROOT / "microcode" / "build"
    out.mkdir(parents=True, exist_ok=True)
    (out / "fault_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"fault_test.hex: {len(PROGRAM)} microwords (PRIV_VIOLATION + ILLEGAL_OPCODE detectors)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
