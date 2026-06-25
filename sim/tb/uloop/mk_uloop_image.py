#!/usr/bin/env python3
"""Directed image exercising the ULOOP micro-loop counter + the ULOOP microcondition (cond[8]).

The count rides the Z bus (see hdl/uloop.v): a microword posts n on Z, then ULOOP_CTRL=LOAD
latches it; `uloop-- ; if not uloop.zero goto L` runs the body exactly n times.

    0  X <- 0   (X_CTRL=LOAD)                      ; loop counter = 0
    1  SCR1 <- +2                                  ; SCR1 = 2
    2  _ <- SCR1 + 1 ; ULOOP_CTRL=LOAD             ; Z = 3 -> uloop <- 3
    3  X++ ; uloop-- ; if not uloop.zero goto 3    ; body: X++  (runs 3 times)
    4  SCR2 <- X                                   ; SCR2 = X = 3
    5  WAIT

cond_inject=0, so the ULOOP condition is the real counter terminal — no injection.
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_0", X_CTRL="LOAD"),
    1: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P2", Z_DEST="SCR1"),
    2: dict(USEQ_OP="INC", ALU_OP="ADD", LEFT_SRC="SCR1", RIGHT_SRC="CONST_P1", ULOOP_CTRL="LOAD"),
    3: dict(USEQ_OP="BRANCH", UCOND_SEL="ULOOP", UCOND_POL="NEGATE", NEXT_ADDR=3,
            X_CTRL="COUNT", ULOOP_CTRL="DECREMENT"),
    4: dict(USEQ_OP="INC", ALU_OP="PASS_L", LEFT_SRC="X", Z_DEST="SCR2"),
    5: dict(USEQ_OP="WAIT"),
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
    (out / "uloop_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"uloop_test.hex: {len(PROGRAM)} microwords (load 3 -> loop body runs 3x)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
