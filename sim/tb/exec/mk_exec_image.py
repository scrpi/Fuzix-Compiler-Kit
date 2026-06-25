#!/usr/bin/env python3
"""Build a directed control-store image that EXECUTES and BRANCHES on real, computed flags.

This is the milestone that retires the cond_drive injection: the ALU computes a result, CC
latches its flags, and the microsequencer branches on the CC-derived condition — no condition
is injected (the bench runs with cond_inject=0).

    0  PASS_R  RIGHT=+1   -> Z=1 ; Z_DEST=SCR1            (load SCR1 = 1)
    1  SUB     LEFT=SCR1, RIGHT=+1 -> Z=0 ; FLAG_WE=Z,C   (CC.Z<-1, CC.C<-0 : 1-1, no borrow)
    2  BRANCH  on C (=0)  -> NOT taken -> fall through to 3   (proves a false condition)
    3  BRANCH  on Z (=1)  -> taken     -> 10                  (proves a true  condition)
   10  WAIT    (success: the Z branch was taken on the real flag)
   99  WAIT    (failure marker: only reached if the C branch wrongly took)

Field encodings come from microcode/control_word.toml via uasm.Fields (single source of truth).
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13
WE_Z, WE_C = (1 << 2), (1 << 4)     # FLAG_WE mask bits (WE_Z=2, WE_C=4)

PROGRAM = {
    # phase 1: 1-1=0 -> Z=1, C=0.  Prove C(=0) does NOT branch, Z(=1) DOES.
    0:  dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_P1", Z_DEST="SCR1"),
    1:  dict(USEQ_OP="INC", ALU_OP="SUB", LEFT_SRC="SCR1", RIGHT_SRC="CONST_P1", FLAG_WE=WE_Z | WE_C),
    2:  dict(USEQ_OP="BRANCH", UCOND_SEL="C", NEXT_ADDR=99),    # C=0 -> not taken -> 3
    3:  dict(USEQ_OP="BRANCH", UCOND_SEL="Z", NEXT_ADDR=10),    # Z=1 -> taken     -> 10
    # phase 2: 0-1=0xFFFF -> Z=0, C=1.  Prove Z(=0) does NOT branch, C(=1) DOES.
    # (SCR2 was never loaded, so it reads 0 from reset — a clean 0-1 borrow.)
    10: dict(USEQ_OP="INC", ALU_OP="SUB", LEFT_SRC="SCR2", RIGHT_SRC="CONST_P1", FLAG_WE=WE_Z | WE_C),
    11: dict(USEQ_OP="BRANCH", UCOND_SEL="Z", NEXT_ADDR=98),    # Z=0 -> not taken -> 12
    12: dict(USEQ_OP="BRANCH", UCOND_SEL="C", NEXT_ADDR=20),    # C=1 -> taken     -> 20
    20: dict(USEQ_OP="WAIT"),                                   # success
    98: dict(USEQ_OP="WAIT"),                                   # failure: Z wrongly took
    99: dict(USEQ_OP="WAIT"),                                   # failure: C wrongly took
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
    (out / "exec_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"exec_test.hex: {len(PROGRAM)} microwords (compute -> CC -> branch on real flags)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
