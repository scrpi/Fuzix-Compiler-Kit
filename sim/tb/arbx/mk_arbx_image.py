#!/usr/bin/env python3
"""Directed image for the bus-arbiter test: a live NON-WAIT loop. Each microword advances the
µPC, counts PC, and writes CC + SCR1 with DIFFERENT values, so upc / pc_q / cc_q / SCR1 all change
every cycle while the bus is NOT granted. A held /BUSGRANT must therefore visibly FREEZE the whole
core (interface.md §4.6, R-IF-4). The old WAIT image could not test the stall — a WAIT holds the
µPC regardless of the grant, so the freeze was never exercised."""
import sys, tomllib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields
SEG, NWCS, NSEG = 4096, 11, 13
WE_N, WE_Z = (1 << 1), (1 << 2)        # FLAG_WE mask bits (WE_N=2, WE_Z=4)
# A 2-word loop. Word 0: Z=0 -> SCR1=0, CC.Z=1/N=0; word 1: Z=0xFFFF -> SCR1=0xFFFF, CC.N=1/Z=0.
# Both COUNT the PC and INC/JUMP the µPC, so every observable register changes each live cycle.
PROGRAM = {
    0: dict(USEQ_OP="INC",  PC_CTRL="COUNT", ALU_OP="PASS_R", RIGHT_SRC="CONST_0",
            Z_DEST="SCR1", FLAG_WE=WE_N | WE_Z, TAS_LOCK="OFF"),
    1: dict(USEQ_OP="JUMP", NEXT_ADDR=0, PC_CTRL="COUNT", ALU_OP="PASS_R", RIGHT_SRC="CONST_M1",
            Z_DEST="SCR1", FLAG_WE=WE_N | WE_Z, TAS_LOCK="OFF"),
}
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
    (out/"arbx_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print("arbx_test.hex: live non-WAIT loop (uPC walks; PC/CC/SCR1 mutate) for the grant-stall test")


if __name__ == "__main__":
    raise SystemExit(main())
