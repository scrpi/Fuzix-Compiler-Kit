#!/usr/bin/env python3
"""Build a directed control-store image that performs a REAL instruction fetch.

Unlike mk_seq_image.py (which injects the opcode via ir_drive to test the microsequencer
walk in isolation), this image drives the datapath that now exists — PC, the address mux,
the MMU identity map, MDR, and IR — to pull an opcode out of MEMORY and dispatch on it:

    0  INC   MMU_ADDR_SRC=TRANSLATE_PC, MEM_OP=READ, PC_CTRL=COUNT
             -> address memory with PC, latch mem[PC] into MDR, advance PC off-bus
    1  INC   IR_LOAD=OPCODE
             -> latch the fetched byte (MDR) into IR
    2  DISPATCH_IR  (DISPATCH_PAGE=PAGE0)
             -> vector the micro-PC to lut[{0, IR}]
   48  WAIT  -> terminal hold at the dispatch target, so the bench can observe

IR must be latched (end of step 1) BEFORE the dispatch microword (step 2) reads the LUT,
since the opcode-LUT is addressed by the registered IR — hence the three distinct steps.

Field bit positions and value encodings come from the SAME source of truth as the
assembler (microcode/control_word.toml, via uasm.Fields), so the test cannot drift.
"""
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "uasm"))
from uasm import Fields  # reuse the field-definition packer (single source of truth)

SEG, NWCS, NSEG = 4096, 11, 13
SEG_LUT_LO, SEG_LUT_HI = 11, 12
IR_OPCODE, DISPATCH_TARGET = 0x42, 48          # opcode placed in memory; its LUT target

# The production single-cycle FETCH (blip.uc:48): read opcode @PC -> IR, PC+1, and dispatch on
# the just-fetched opcode — all in ONE microword. The read posts the opcode on Z (so IR latches
# it) and the LUT is indexed by the next-IR value, so the dispatch sees it the same cycle.
PROGRAM = {
    0:  dict(USEQ_OP="DISPATCH_IR", DISPATCH_PAGE="PAGE0", MMU_ADDR_SRC="TRANSLATE_PC",
             MEM_OP="READ", PC_CTRL="COUNT", IR_LOAD="OPCODE"),
    DISPATCH_TARGET: dict(USEQ_OP="WAIT"),
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
    (out / "fetch_test.hex").write_text("".join(f"{b:02x}\n" for b in img))
    print(f"fetch_test.hex: {len(PROGRAM)} microwords, "
          f"opcode {IR_OPCODE:#04x} -> lut[page0] = {DISPATCH_TARGET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
