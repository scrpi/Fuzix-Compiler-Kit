#!/usr/bin/env python3
"""Directed image exercising the external/internal microconditions IRQ/NMI/WAIT_READY (cond[9..11]).

The sequencer branches on the real condition lines (cond_inject=0); the bench drives irq/nmi/
wait_ready and watches the µPC advance through the gates:

    0  if irq goto 3                 ; spin here until IRQ
    1  goto 0
    3  if nmi goto 6                 ; then spin until NMI
    4  goto 3
    6  if not wait-ready goto 6      ; then stall until the bus is ready
    7  WAIT                          ; success

UCOND_SEL picks the condition; UCOND_POL=NEGATE gives the `if not` sense.
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields

SEG, NWCS, NSEG = 4096, 11, 13

PROGRAM = {
    0: dict(USEQ_OP="BRANCH", UCOND_SEL="IRQ_PENDING", UCOND_POL="ASSERT", NEXT_ADDR=3),
    1: dict(USEQ_OP="JUMP", NEXT_ADDR=0),
    3: dict(USEQ_OP="BRANCH", UCOND_SEL="NMI_PENDING", UCOND_POL="ASSERT", NEXT_ADDR=6),
    4: dict(USEQ_OP="JUMP", NEXT_ADDR=3),
    6: dict(USEQ_OP="BRANCH", UCOND_SEL="WAIT_READY", UCOND_POL="NEGATE", NEXT_ADDR=6),
    7: dict(USEQ_OP="WAIT"),
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
    (out / "irqx_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"irqx_test.hex: {len(PROGRAM)} microwords (IRQ -> NMI -> WAIT_READY gate)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
