#!/usr/bin/env python3
"""Build a directed control-store image that exercises the real microsequencer.

Unlike the production microcode (microcode/src/blip.uc, assembled by uasm.py), this is a
hand-placed sequence of microwords chosen to drive a *known* µPC walk through the
fetch/branch core of USEQ_OP — INC / JUMP / BRANCH (taken & not, low/high condition
groups, both polarities) / DISPATCH_IR / WAIT — plus one opcode-LUT entry for the
dispatch. The microsequencer testbench (tb_cpu.v) asserts the µPC follows this walk.

Field bit positions and value encodings come from the SAME source of truth as the
assembler — microcode/control_word.toml, via uasm.Fields — so the test cannot drift from
the spec. Output: <build>/seq_test.hex, the 13×4096 chip-major format the loader fans out
(same as uasm), loaded by the testbench's EEPROM model.

The expected walk has two passes. Pass 1 (cond_drive: C=1, IRQ_PENDING=1, Z=0;
ir_drive = 0x42):

    0  JUMP   -> 3
    3  BRANCH Z(=0)              -> not taken -> 4
    4  BRANCH C(=1)              -> taken     -> 6
    6  BRANCH IRQ_PENDING(=1)    -> taken     -> 8   (high condition group)
    8  BRANCH TRUE, NEGATE(=0)   -> not taken -> 9   (polarity)
    9  INC                       -> 10
   10  DISPATCH_IR  (IR=0x42)    -> lut[{0,0x42}] = 16
   16  INC                       -> 17
   17  RETURN_FETCH              -> 0          (back to the fetch entry)

The bench then raises Z (cond_drive Z=1) and pass 2 diverges — proving the condition
mux really reads the line and RETURN_FETCH/WAIT both work:

    0  JUMP   -> 3
    3  BRANCH Z(=1)              -> taken     -> 99
   99  WAIT                      -> holds at 99
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields  # reuse the field-definition packer (single source of truth)

SEG, NWCS, NSEG = 4096, 11, 13
SEG_LUT_LO, SEG_LUT_HI = 11, 12
IR_OPCODE, DISPATCH_TARGET = 0x42, 16

# the directed walk: µaddr -> microword fields. A few datapath fields are set so the
# control-word decoder sees non-trivial values (decoder spot-check in the bench).
PROGRAM = {
    0:  dict(USEQ_OP="JUMP",   NEXT_ADDR=3),
    3:  dict(USEQ_OP="BRANCH", UCOND_SEL="Z",           NEXT_ADDR=99),   # Z: 0->not taken, 1->99
    4:  dict(USEQ_OP="BRANCH", UCOND_SEL="C",           NEXT_ADDR=6),    # C=1  -> taken
    6:  dict(USEQ_OP="BRANCH", UCOND_SEL="IRQ_PENDING", NEXT_ADDR=8),    # idx9 -> taken
    8:  dict(USEQ_OP="BRANCH", UCOND_SEL="TRUE", UCOND_POL="NEGATE", NEXT_ADDR=50),  # not taken
    9:  dict(USEQ_OP="INC",    LEFT_SRC="X", RIGHT_SRC="SCR2", MEM_OP="READ"),
    10: dict(USEQ_OP="DISPATCH_IR"),                                     # -> lut[{0,IR}]
    16: dict(USEQ_OP="INC",    LEFT_SRC="D", MEM_OP="WRITE"),
    17: dict(USEQ_OP="RETURN_FETCH"),                                    # -> 0 (fetch entry)
    99: dict(USEQ_OP="WAIT"),                                            # terminal hold (pass 2)
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

    idx = (0 << 8) | IR_OPCODE                       # {page0, IR}
    img[SEG_LUT_LO * SEG + idx] = DISPATCH_TARGET & 0xFF
    img[SEG_LUT_HI * SEG + idx] = (DISPATCH_TARGET >> 8) & 0x0F

    out = ROOT / "microcode" / "build"
    out.mkdir(parents=True, exist_ok=True)
    (out / "seq_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"seq_test.hex: {len(PROGRAM)} microwords, "
          f"lut[page0,{IR_OPCODE:#04x}] = {DISPATCH_TARGET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
