#!/usr/bin/env python3
"""Directed image proving a memory read POSTS on Z in one microword (the load/store foundation).

A read names a Z destination and the flags in the SAME word (microcode-source.md §13 #1): the
byte travels memory -> D[7:0] -> Z, the register latches it, and the ALU N/Z reduction sees it
with the ALU otherwise idle (PASS_L hardware-suppressed during /RD).

    0  MAR <- +1                              ; MAR = 0x0001
    1  A <- [MAR] : nz, v=0                    ; read mem[1]=0x80 -> D.low, N=1 Z=0
    2  MAR <- +2                              ; MAR = 0x0002
    3  A <- [MAR] : nz, v=0                    ; read mem[2]=0x00 -> D.low, N=0 Z=1
    4  WAIT
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13
WE_N, WE_Z = (1 << 1), (1 << 2)

PROGRAM = {
    0: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P1", MAR_CTRL="LOAD"),
    1: dict(USEQ_OP="INC", MEM_OP="READ", MMU_ADDR_SRC="TRANSLATE_MAR",
            Z_DEST="D", Z_LANE="LOW", FLAG_WE=WE_N | WE_Z, V_SRC="FORCE_0"),
    2: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P2", MAR_CTRL="LOAD"),
    3: dict(USEQ_OP="INC", MEM_OP="READ", MMU_ADDR_SRC="TRANSLATE_MAR",
            Z_DEST="D", Z_LANE="LOW", FLAG_WE=WE_N | WE_Z, V_SRC="FORCE_0"),
    4: dict(USEQ_OP="WAIT"),
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
    (out / "ldz_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"ldz_test.hex: {len(PROGRAM)} microwords (read posts on Z; latch + N/Z in one word)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
