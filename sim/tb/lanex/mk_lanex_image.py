#!/usr/bin/env python3
"""Build a directed control-store image that exercises BYTE-LANE STEERING end-to-end.

The whole datapath runs (cond_inject=0, ir_inject=0; no memory). It builds a 16-bit value into
SCR1 a byte at a time via Z_LANE, then reads SCR1 back through every LEFT_LANE mode into SCR2 —
so the bench can read dut.scr1.q / dut.scr2.q and confirm the steer wiring in cpu.v:

    0  PASS_R RIGHT=+1  Z_DEST=SCR1                       ; SCR1 = 0x0001 (FULL16 load)
    1  PASS_R RIGHT=+2  Z_DEST=SCR1 Z_LANE=HIGH           ; SCR1.hi <- Z[7:0]=0x02, lo held -> 0x0201
    2  PASS_R RIGHT=-1  Z_DEST=SCR1 Z_LANE=LOW            ; SCR1.lo <- Z[7:0]=0xFF, hi held -> 0x02FF
    3  PASS_L LEFT=SCR1 LEFT_LANE=LOW      Z_DEST=SCR2    ; SCR2 = 0x00FF (zero-extend low byte)
    4  PASS_L LEFT=SCR1 LEFT_LANE=SIGN_EXT Z_DEST=SCR2    ; SCR2 = 0xFFFF (sign-extend FF)
    5  PASS_L LEFT=SCR1 LEFT_LANE=HIGH_TO_LOW Z_DEST=SCR2 ; SCR2 = 0x0002 (high byte 0x02 -> low)
    6  WAIT

Only the constant generator {-1,+1,+2} and the two scratch registers are used, so the program is
self-contained: no fetch, no real memory. Field encodings come from control_word.toml via uasm.
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P1", Z_DEST="SCR1"),
    1: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P2", Z_DEST="SCR1", Z_LANE="HIGH"),
    2: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_M1", Z_DEST="SCR1", Z_LANE="LOW"),
    3: dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="SCR1", LEFT_LANE="LOW", Z_DEST="SCR2"),
    4: dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="SCR1", LEFT_LANE="SIGN_EXT", Z_DEST="SCR2"),
    5: dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="SCR1", LEFT_LANE="HIGH_TO_LOW", Z_DEST="SCR2"),
    6: dict(USEQ_OP="WAIT"),
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
    (out / "lanex_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"lanex_test.hex: {len(PROGRAM)} microwords (Z_LANE byte build + LEFT_LANE widen)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
