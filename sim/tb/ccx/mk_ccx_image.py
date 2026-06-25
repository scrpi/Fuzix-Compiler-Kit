#!/usr/bin/env python3
"""Build a directed control-store image that exercises the privileged M/I controls end-to-end.

Runs the whole datapath (cond_inject=0, ir_inject=0; no memory). The machine boots in supervisor
(reset CC=0x90: M=1, I=1) and drives the CC_MI_LOAD / CC_WRITE_SRC controls through the real
decoder -> CC path, so the bench can read cc_q and confirm finding #1/#3's contract:

    0  CC_MI_LOAD=CLR_I                          ; I<-0, M held   (CLI)
    1  CC_MI_LOAD=SET_I                          ; I<-1, M held   (SEI)
    2  PASS_R CONST_0 ; CC_WRITE_SRC=WHOLE_Z     ; CC<-whole(0): M<-0 (drop to user), I<-0  (RTI/PULS CC)
    3  CC_MI_LOAD=SET_I                          ; in USER: the I write is IGNORED (privilege)
    4  WAIT

So SET_I/CLR_I change I alone with M held (supervisor), a whole CC write restores M/I, and once
in user mode a privileged M/I write is suppressed (isa.md §8.7). Field encodings come from
control_word.toml via uasm.Fields.
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0: dict(USEQ_OP="INC", CC_MI_LOAD="CLR_I"),
    1: dict(USEQ_OP="INC", CC_MI_LOAD="SET_I"),
    2: dict(USEQ_OP="INC", ALU_OP="PASS_R", RIGHT_SRC="CONST_0", CC_WRITE_SRC="WHOLE_Z"),
    3: dict(USEQ_OP="INC", CC_MI_LOAD="SET_I"),
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
    (out / "ccx_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"ccx_test.hex: {len(PROGRAM)} microwords (SET_I/CLR_I, WHOLE_Z restore, M/I privilege)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
