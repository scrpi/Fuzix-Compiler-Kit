#!/usr/bin/env python3
"""Directed image exercising the rest of the register file + ACTIVE_SP banking (hardware.md §2).

Runs the whole datapath (cond_inject=0, ir_inject=0; no memory) so the bench can read the real
register Q's:

    0  X  <- +2 (X_CTRL=LOAD)                 ; X = 0x0002
    1  X++      (X_CTRL=COUNT)                ; X = 0x0003  (off-bus +1)
    2  SCR1 <- X                              ; LEFT_SRC=X -> SCR1 = 0x0003
    3  Y  <- -1 (Y_CTRL=LOAD)                 ; Y = 0xFFFF
    4  SCR2 <- Y                              ; LEFT_SRC=Y -> SCR2 = 0xFFFF
    5  D  <- +1 (Z_DEST=D, FULL16)            ; D = 0x0001
    6  D  <- -1 (Z_DEST=D, Z_LANE=HIGH)       ; D.high <- 0xFF, low held -> D = 0xFF01
    7  SSP <- +2 (Z_DEST=SSP)                 ; SSP = 0x0002  (boot = supervisor)
    8  USP <- +1 (Z_DEST=USP)                 ; USP = 0x0001
    9  SCR1 <- ACTIVE_SP                       ; supervisor -> SSP -> SCR1 = 0x0002
   10  _ <- 0 ; CC_WRITE_SRC=WHOLE_Z          ; CC <- 0 : drop to user (M=0)
   11  SCR2 <- ACTIVE_SP                       ; user -> USP -> SCR2 = 0x0001
   12  WAIT

Field encodings come from control_word.toml via uasm.Fields.
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P2", X_CTRL="LOAD"),
    1:  dict(USEQ_OP="INC", X_CTRL="COUNT"),
    2:  dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="X", Z_DEST="SCR1"),
    3:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_M1", Y_CTRL="LOAD"),
    4:  dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="Y", Z_DEST="SCR2"),
    5:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P1", Z_DEST="D"),
    6:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_M1", Z_DEST="D", Z_LANE="HIGH"),
    7:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P2", Z_DEST="SSP"),
    8:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P1", Z_DEST="USP"),
    9:  dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="ACTIVE_SP", Z_DEST="SCR1"),
    10: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_0", CC_WRITE_SRC="WHOLE_Z"),
    11: dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="ACTIVE_SP", Z_DEST="SCR2"),
    12: dict(USEQ_OP="WAIT"),
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
    (out / "regfile_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"regfile_test.hex: {len(PROGRAM)} microwords (D/X/Y/USP/SSP + ACTIVE_SP banking)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
