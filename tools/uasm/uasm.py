#!/usr/bin/env python3
"""BLIP microcode assembler.

Turns human-readable microcode source (.uc, the register-transfer notation of
docs/microcode-source.md) into ONE burnable EEPROM image that is ALSO the
simulation input: the sim loads this single image and the modeled microcode loader
fans it out to the 13 control-store SRAMs, so the loading circuit is itself
exercised on every run (toolchain.md §3, §3.5, R-BUILD-3). The 88-bit
control-word layout and all symbolic value encodings come from control_word.toml
— the single field-definition source of truth (§3.1) — so this tool holds no
hard-coded bit positions.

Single-EEPROM boot model
------------------------
All 13 control-store SRAMs are programmed from ONE EEPROM that the microcode loader
fans out on power-on (refines D-03 / R-CTRL-3). The image is CHIP-MAJOR with
uniform 4 KiB segments, so the loader is pure binary address-slicing:

    EEPROM addr = (segment << 12) | sram_addr
      segment 0..10  -> WCS SRAM 0..10   (88-bit word, byte k = bits[8k..8k+7])
      segment 11     -> opcode LUT, low byte   (lut[{PAGE,IR}] & 0xFF)
      segment 12     -> opcode LUT, high 4 bits ((lut >> 8) & 0x0F)

    counter[15:12] -> 4:16 decoder -> one SRAM /WE ;  counter[11:0] -> shared addr

Total = 13 * 4096 = 53,248 bytes — the microcode image. It targets a 128 KB control-store
EEPROM (the design size); the assembler is deliberately unaware of the physical part, which
is a hardware/BOM choice (hardware.md §7) — a larger in-stock part with its upper address
pins grounded serves identically. Unused fill within the image is 0x00, the inert NOP
control word (USEQ_OP=INC, all drivers/CTRLs idle), so an unprogrammed microaddress is
harmless.

Source language (.uc) — register transfers, one statement per microword
-----------------------------------------------------------------------
Full grammar in docs/microcode-source.md. Each statement compiles to exactly one
88-bit control word (strict 1:1). This v0 front-end implements the constructs the
current routines use and errors clearly on the rest:

  # comment to end of line
  .fetch NAME                 the fetch entry (the named routine must be at addr 0)
  .opcode page0 LD A,(X+n8)   bind a routine as that mnemonic's opcode entry
  routine NAME:               start a routine; the indented lines are its microwords

  dest <- [PC] ; PC++ ; dispatch         memory read + counter tick + sequencer
  dest <- a + b                          ALU op (b must be SCR1/SCR2/const)
  dest <- sext(src)                      lane-steer (sext/low/high) + pass
  A <- [MAR] : nz, v=0                   A = D.low; flag clause after ':'

NOTE: opcode byte values are not yet assigned (D-41), so `.opcode` bindings get
placeholder sequential indices per page until the mnemonic->byte pass exists.
"""
from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent.parent                                # repo root (tools/uasm/ -> tools -> root)
DEFAULT_SPEC = ROOT / "microcode" / "control_word.toml"  # the field definition
DEFAULT_SRC  = ROOT / "microcode" / "src" / "blip.uc"    # the microcode source
OUTDIR       = ROOT / "microcode" / "build"              # the image lands here (gitignored)

# --- single-EEPROM geometry -------------------------------------------------
WCS_DEPTH   = 4096          # 2**12 microwords (NEXT_ADDR is 12 bits — 13->12 to fit each
                            #   12-bit micro-address element in three 4-bit chips)
N_WCS       = 11            # 88-bit word over 11 byte-wide SRAMs
LUT_ENTRIES = 512           # {DISPATCH_PAGE, IR} = 9 bits
SEG_SIZE    = 4096          # uniform 4 KiB segment per SRAM (loader simplicity); the 8 K
                            #   SRAM runs with its top address pin grounded (4 K used)
N_SEG       = 13            # 11 WCS + 2 LUT
SEG_LUT_LO  = 11
SEG_LUT_HI  = 12
IMG_BYTES   = N_SEG * SEG_SIZE   # 53,248 — the microcode image (13 segments); targets a
                                 # 128 KB control-store EEPROM. The physical part is a
                                 # hardware choice the assembler need not know (D-43).
FILL        = 0x00          # unused bytes -> inert NOP word

COUNTERS = ("PC", "MAR", "X", "Y")


class AsmError(Exception):
    pass


def norm(tok: str) -> str:
    """Canonicalize a value token to its field-def identifier."""
    return tok.strip().upper().replace("-", "_")


# ---------------------------------------------------------------------------
# Field definition
# ---------------------------------------------------------------------------
class Fields:
    def __init__(self, spec: dict):
        self.spec = spec
        self.by_name: dict[str, dict] = {}
        sections = {s["name"]: dict(base=min(s["srams"]) * 8, cur=min(s["srams"]) * 8)
                    for s in spec["section"]}
        for f in spec["field"]:
            sec = sections[f["section"]]
            f["lsb"] = sec["cur"]
            f["mask"] = (1 << f["width"]) - 1
            sec["cur"] += f["width"]
            self.by_name[f["name"]] = f

    def mask_code(self, fname: str, flags: list[str], lineno: int) -> int:
        bits = self.by_name[fname]["bits_"]
        code = 0
        for flag in flags:
            key = "WE_" + norm(flag)
            if key not in bits:
                raise AsmError(f"line {lineno}: {fname}: unknown flag {flag!r}")
            code |= 1 << bits[key]
        return code

    def code_of(self, fname: str, value: str | int) -> int:
        f = self.by_name.get(fname)
        if f is None:
            raise AsmError(f"unknown field {fname!r}")
        if isinstance(value, int):
            return value
        key = norm(value)
        if key not in f.get("values", {}):
            raise AsmError(f"{fname}: {value!r} is not a value")
        return f["values"][key]


# ---------------------------------------------------------------------------
# A microword
# ---------------------------------------------------------------------------
class Microword:
    __slots__ = ("addr", "fields", "lineno", "src")

    def __init__(self, lineno: int, src: str):
        self.addr = -1
        self.fields: dict[str, tuple[int, str | None]] = {}
        self.lineno = lineno
        self.src = src


# ---------------------------------------------------------------------------
# Register-transfer binding: one statement -> one set of control fields
# ---------------------------------------------------------------------------
def set_field(out: dict, fname: str, code: int, lineno: int):
    if fname in out and out[fname] != code:
        raise AsmError(f"line {lineno}: {fname} driven twice — one source/action "
                       f"per lane per microword")
    out[fname] = code


# 16-bit architectural registers — an ALU result landing here is a 16-bit op
# (ALU_WIDTH=16); A/B and the byte lanes of a scratch stay 8-bit (lane != None).
WIDE16 = ("D", "X", "Y", "ACTIVE_SP", "MAR", "PC", "USP", "SSP")

# condition token -> UCOND_SEL (microcode-source.md §9). `not` prefixes invert
# the polarity (UCOND_POL). `uloop.zero` is the loop-terminal-zero condition.
COND_SEL = {
    "z": "Z", "c": "C", "n": "N", "v": "V",
    "c|z": "C_OR_Z", "n^v": "N_XOR_V", "z|(n^v)": "Z_OR_NXORV", "true": "TRUE",
    "uloop": "ULOOP", "uloop.zero": "ULOOP",
    "irq": "IRQ_PENDING", "nmi": "NMI_PENDING", "wait-ready": "WAIT_READY",
    "multibyte-last": "MULTIBYTE_LAST", "priv": "PRIV_VIOLATION",
    "illegal": "ILLEGAL_OPCODE",
}


def parse_dest(tok: str):
    """Return (register, lane|None), resolving A/B/SP and the .low/.high suffix."""
    lane = None
    if tok.endswith(".low"):
        tok, lane = tok[:-4], "LOW"
    elif tok.endswith(".high"):
        tok, lane = tok[:-5], "HIGH"
    if tok == "A":
        return "D", "LOW"
    if tok == "B":
        return "D", "HIGH"
    if tok == "SP":
        return "ACTIVE_SP", lane
    return tok, lane


def map_src(tok: str) -> str:
    return "ACTIVE_SP" if tok == "SP" else tok


def bind_left(expr: str, out: dict, fields: Fields, lineno: int):
    """Drive the LEFT bus from a source expression: a lane function, A/B (= the
       byte lanes of D), an explicit SP, or a plain LEFT_SRC register."""
    expr = expr.strip()
    m = re.fullmatch(r"(sext|low|high)\((.+)\)", expr)
    if m:
        fn, inner = m.group(1), m.group(2).strip()
        src = "D" if inner in ("A", "B") else map_src(inner)   # A/B are lanes of D
        set_field(out, "LEFT_SRC", fields.code_of("LEFT_SRC", src), lineno)
        set_field(out, "LEFT_LANE", fields.code_of("LEFT_LANE",
                  {"sext": "SIGN_EXT", "low": "LOW", "high": "HIGH_TO_LOW"}[fn]), lineno)
        return
    if expr == "A":
        set_field(out, "LEFT_SRC", fields.code_of("LEFT_SRC", "D"), lineno)
        set_field(out, "LEFT_LANE", fields.code_of("LEFT_LANE", "LOW"), lineno)
        return
    if expr == "B":
        set_field(out, "LEFT_SRC", fields.code_of("LEFT_SRC", "D"), lineno)
        set_field(out, "LEFT_LANE", fields.code_of("LEFT_LANE", "HIGH_TO_LOW"), lineno)
        return
    set_field(out, "LEFT_SRC", fields.code_of("LEFT_SRC", map_src(expr)), lineno)


def map_right(tok: str, fields: Fields, lineno: int) -> int:
    if tok in ("SCR1", "SCR2"):
        return fields.code_of("RIGHT_SRC", tok)
    try:
        n = int(tok, 0)
    except ValueError:
        raise AsmError(f"line {lineno}: RIGHT operand {tok!r} must be SCR1/SCR2 "
                       f"or a constant -2..+2")
    name = {-2: "CONST_M2", -1: "CONST_M1", 0: "CONST_0",
            1: "CONST_P1", 2: "CONST_P2"}.get(n)
    if name is None:
        raise AsmError(f"line {lineno}: constant {n} out of range -2..+2")
    return fields.code_of("RIGHT_SRC", name)


def set_result_dest(out: dict, dst: str, fields: Fields, lineno: int):
    if dst == "_":                       # compute for flags only (Z_DEST = none)
        return
    d, lane = parse_dest(dst)
    if d in COUNTERS:
        if lane:
            raise AsmError(f"line {lineno}: counter {d} cannot take a byte lane")
        set_field(out, f"{d}_CTRL", fields.code_of(f"{d}_CTRL", "LOAD"), lineno)
    else:
        set_field(out, "Z_DEST", fields.code_of("Z_DEST", d), lineno)
        if lane:
            set_field(out, "Z_LANE", fields.code_of("Z_LANE", lane), lineno)
    if d in WIDE16 and lane is None:     # a 16-bit result -> ALU_WIDTH=16
        set_field(out, "ALU_WIDTH", fields.code_of("ALU_WIDTH", "W16"), lineno)


def bind_read(dst: str, addr: str, out: dict, fields: Fields, lineno: int):
    set_field(out, "MEM_OP", fields.code_of("MEM_OP", "READ"), lineno)
    mmu = {"PC": "TRANSLATE_PC", "MAR": "TRANSLATE_MAR"}.get(addr)
    if mmu is None:
        raise AsmError(f"line {lineno}: read address [{addr}] — expected [PC] or [MAR]")
    set_field(out, "MMU_ADDR_SRC", fields.code_of("MMU_ADDR_SRC", mmu), lineno)
    d, lane = parse_dest(dst)
    if d == "_":
        pass  # read that only sets flags (TST mem) — lands in MDR, no Z dest
    elif d == "IR":
        set_field(out, "IR_LOAD", fields.code_of("IR_LOAD", "OPCODE"), lineno)
    elif d == "MDR":
        pass  # MDR is the default read capture (microcode.md §3.2)
    else:
        # read posts on Z, so a named dest latches it the same cycle (§13 #1)
        set_field(out, "Z_DEST", fields.code_of("Z_DEST", d), lineno)
        if lane:
            set_field(out, "Z_LANE", fields.code_of("Z_LANE", lane), lineno)


def bind_write(addr: str, src: str, out: dict, fields: Fields, lineno: int):
    set_field(out, "MEM_OP", fields.code_of("MEM_OP", "WRITE"), lineno)
    if addr != "MAR":
        raise AsmError(f"line {lineno}: write [{addr}] <- … — writes address via MAR")
    set_field(out, "MMU_ADDR_SRC", fields.code_of("MMU_ADDR_SRC", "TRANSLATE_MAR"), lineno)
    bind_left(src, out, fields, lineno)   # the source drives the data bus on LEFT


def bind_alu(dst: str, rhs: str, out: dict, fields: Fields, lineno: int):
    m = re.fullmatch(r"(sext|low|high)\((.+)\)", rhs)
    if m:                                  # lane-steer pass
        bind_left(rhs, out, fields, lineno)
        set_field(out, "ALU_OP", fields.code_of("ALU_OP", "PASS_L"), lineno)
        set_result_dest(out, dst, fields, lineno)
        return
    m = re.fullmatch(r"(asl|lsr|asr|rol|ror)\((.+)\)", rhs)
    if m:                                  # shift / rotate
        fn, inner = m.group(1), m.group(2).strip()
        bind_left(inner, out, fields, lineno)
        set_field(out, "ALU_OP", fields.code_of("ALU_OP", "SHIFT"), lineno)
        set_field(out, "ALU_SHIFT", fields.code_of("ALU_SHIFT", fn.upper()), lineno)
        set_result_dest(out, dst, fields, lineno)
        return
    if rhs.startswith("~"):                 # COM (unary)
        bind_left(rhs[1:].strip(), out, fields, lineno)
        set_field(out, "ALU_OP", fields.code_of("ALU_OP", "COM"), lineno)
        set_result_dest(out, dst, fields, lineno)
        return
    if rhs.startswith("-") and " - " not in rhs:   # NEG (unary)
        bind_left(rhs[1:].strip(), out, fields, lineno)
        set_field(out, "ALU_OP", fields.code_of("ALU_OP", "NEG"), lineno)
        set_result_dest(out, dst, fields, lineno)
        return
    for sym, op in ((" +c ", "ADC"), (" -c ", "SBC"), (" + ", "ADD"),
                    (" - ", "SUB"), (" & ", "AND"), (" | ", "OR"), (" ^ ", "EOR")):
        if sym in rhs:
            a, b = rhs.split(sym, 1)
            bind_left(a.strip(), out, fields, lineno)
            set_field(out, "RIGHT_SRC", map_right(b.strip(), fields, lineno), lineno)
            set_field(out, "ALU_OP", fields.code_of("ALU_OP", op), lineno)
            set_result_dest(out, dst, fields, lineno)
            return
    try:                                   # a bare const-gen value -> PASS_R
        n = int(rhs, 0)
    except ValueError:
        bind_left(rhs.strip(), out, fields, lineno)     # plain source -> PASS_L
        set_field(out, "ALU_OP", fields.code_of("ALU_OP", "PASS_L"), lineno)
        set_result_dest(out, dst, fields, lineno)
        return
    set_field(out, "RIGHT_SRC", map_right(str(n), fields, lineno), lineno)
    set_field(out, "ALU_OP", fields.code_of("ALU_OP", "PASS_R"), lineno)
    set_result_dest(out, dst, fields, lineno)


def bind_counter_inc(part: str, out: dict, fields: Fields, lineno: int):
    reg = part[:-2].strip()
    if reg not in COUNTERS:
        raise AsmError(f"line {lineno}: '{reg}++' — only PC/MAR/X/Y are counters")
    set_field(out, f"{reg}_CTRL", fields.code_of(f"{reg}_CTRL", "COUNT"), lineno)


def bind_cond(cond: str, out: dict, fields: Fields, lineno: int):
    """Bind UCOND_SEL/UCOND_POL from a condition string (with optional `not`)."""
    pol = "ASSERT"
    if cond.startswith("not "):
        pol, cond = "NEGATE", cond[4:].strip()
    sel = COND_SEL.get(cond)
    if sel is None:
        raise AsmError(f"line {lineno}: unknown condition {cond!r}")
    set_field(out, "UCOND_SEL", fields.code_of("UCOND_SEL", sel), lineno)
    set_field(out, "UCOND_POL", fields.code_of("UCOND_POL", pol), lineno)


def bind_control(part: str, out: dict, labels: dict, fields: Fields, lineno: int):
    toks = part.split()
    kw = toks[0]
    if kw == "dispatch":
        set_field(out, "USEQ_OP", fields.code_of("USEQ_OP", "DISPATCH_IR"), lineno)
        if len(toks) > 1:
            if toks[1] == "page1":
                set_field(out, "DISPATCH_PAGE", fields.code_of("DISPATCH_PAGE", "PAGE1"), lineno)
            else:
                raise AsmError(f"line {lineno}: dispatch qualifier {toks[1]!r} — expected 'page1'")
    elif kw == "goto":
        set_field(out, "USEQ_OP", fields.code_of("USEQ_OP", "JUMP"), lineno)
        set_field(out, "NEXT_ADDR", 0, lineno)
        labels["NEXT_ADDR"] = toks[1]
    elif kw == "call":
        set_field(out, "USEQ_OP", fields.code_of("USEQ_OP", "CALL"), lineno)
        set_field(out, "NEXT_ADDR", 0, lineno)
        labels["NEXT_ADDR"] = toks[1]
    elif kw == "if":
        gi = toks.index("goto")
        bind_cond(" ".join(toks[1:gi]), out, fields, lineno)
        set_field(out, "USEQ_OP", fields.code_of("USEQ_OP", "BRANCH"), lineno)
        set_field(out, "NEXT_ADDR", 0, lineno)
        labels["NEXT_ADDR"] = toks[gi + 1]
    elif kw == "return":
        op = "RETURN_FETCH" if toks[1:3] == ["to", "fetch"] else "RETURN"
        set_field(out, "USEQ_OP", fields.code_of("USEQ_OP", op), lineno)
    elif kw == "wait":
        set_field(out, "USEQ_OP", fields.code_of("USEQ_OP", "WAIT"), lineno)
    elif kw == "uloop--":
        set_field(out, "ULOOP_CTRL", fields.code_of("ULOOP_CTRL", "DECREMENT"), lineno)
    elif kw in ("lock", "unlock"):
        set_field(out, "TAS_LOCK", fields.code_of("TAS_LOCK", "LOCK" if kw == "lock" else "OFF"), lineno)
    elif "(" in kw:                         # cc(…) / mi(…) / map(…) / pt(…) / vector(…)
        fn, arg = re.fullmatch(r"(\w+)\((\w+)\)", kw).groups()
        if fn == "cc":
            set_field(out, "CC_WRITE_SRC", fields.code_of("CC_WRITE_SRC",
                      {"whole": "WHOLE_Z", "and": "AND_MASK", "or": "OR_MASK"}[arg]), lineno)
        elif fn == "mi":
            set_field(out, "CC_MI_LOAD", fields.code_of("CC_MI_LOAD",
                      {"enter": "SET_ON_ENTRY", "from_z": "FROM_Z",
                       "set_i": "EXPLICIT", "clr_i": "EXPLICIT"}[arg]), lineno)
        elif fn == "map":
            set_field(out, "MMU_MAP_SEL", fields.code_of("MMU_MAP_SEL",
                      {"kernel": "FORCE_KERNEL", "user": "FORCE_USER", "imm8": "FROM_IMM8"}[arg]), lineno)
        elif fn == "pt":
            set_field(out, "MMU_PT_OP", fields.code_of("MMU_PT_OP",
                      {"write": "WRITE_ENTRY", "read": "READ_ENTRY"}[arg]), lineno)
        elif fn == "vector":
            pass  # the trap-vector slot address is materialized by the trap logic
        else:
            raise AsmError(f"line {lineno}: unknown clause {kw!r}")
    else:
        raise AsmError(f"line {lineno}: unrecognized clause {part!r}")


def bind_flags(flagstr: str, out: dict, fields: Fields, lineno: int):
    we: list[str] = []
    for item in flagstr.split(","):
        item = item.strip()
        if not item:
            continue
        if item == "z+":                   # accumulate Z across a 16-bit op's two lanes
            we.append("Z")
            set_field(out, "Z_ACCUM", fields.code_of("Z_ACCUM", "ACCUM"), lineno)
        elif "=" in item:
            f, val = (x.strip() for x in item.split("=", 1))
            f = f.upper()
            we.append(f)
            src = {"0": "FORCE_0", "1": "FORCE_1"}.get(val)
            if src is None:
                raise AsmError(f"line {lineno}: flag force {item!r} must be =0 or =1")
            if f == "V":
                set_field(out, "V_SRC", fields.code_of("V_SRC", src), lineno)
            elif f == "C":
                set_field(out, "C_SRC", fields.code_of("C_SRC", src), lineno)
            else:
                raise AsmError(f"line {lineno}: only V/C can be forced, not {f}")
        else:
            we.extend(item.upper())
    if we:
        set_field(out, "FLAG_WE", fields.mask_code("FLAG_WE", we, lineno), lineno)


def bind_statement(s: str, fields: Fields, lineno: int) -> dict:
    out: dict[str, int] = {}
    labels: dict[str, str] = {}            # field -> label (resolved to an address later)
    # The flag clause is introduced by ':' and runs to the next ';'; everything
    # else (transfer + concurrent + control clauses) is ';'-separated.
    flagstr = ""
    if ":" in s:
        pre, _, rest = s.partition(":")
        flagstr, _, post = rest.partition(";")
        s = pre + (";" + post if post.strip() else "")
    for part in (p.strip() for p in s.split(";")):
        if not part:
            continue
        if "reg[" in part:
            continue  # selector-driven register move — no control-word field routes it
        if "->" in part:                   # count -> uloop  (load the loop counter)
            set_field(out, "ULOOP_CTRL", fields.code_of("ULOOP_CTRL", "LOAD"), lineno)
            continue
        if "<-" in part:
            dst, rhs = (x.strip() for x in part.split("<-", 1))
            if dst == "MMU_ENTRY":         # LDMMU: data on LEFT, written via pt(write)
                bind_left(rhs, out, fields, lineno)
            elif dst.startswith("["):
                bind_write(dst[1:dst.index("]")].strip(), rhs, out, fields, lineno)
            elif rhs.startswith("["):
                bind_read(dst, rhs[1:rhs.index("]")].strip(), out, fields, lineno)
            elif rhs.startswith("vector("):
                set_result_dest(out, dst, fields, lineno)   # MAR <- vector(NAME)
            else:
                bind_alu(dst, rhs, out, fields, lineno)
        elif part.endswith("++"):
            bind_counter_inc(part, out, fields, lineno)
        else:
            bind_control(part, out, labels, fields, lineno)
    if flagstr:
        bind_flags(flagstr, out, fields, lineno)
    return {f: (c, labels.get(f)) for f, c in out.items()}


# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------
def parse(text: str, fields: Fields):
    words: list[Microword] = []
    labels: dict[str, int] = {}            # routine/label name -> word index
    opcodes: list[tuple[int, str, int]] = []   # (page, mnemonic, lineno)
    fetch_label = None
    pending: list[tuple[str, int]] = []    # labels awaiting their microword

    for lineno, raw in enumerate(text.splitlines(), 1):
        s = raw.split("#", 1)[0].strip()
        if not s:
            continue

        if s.startswith("."):
            toks = s.split(None, 1)
            d, rest = toks[0], (toks[1].strip() if len(toks) > 1 else "")
            if d == ".fetch":
                fetch_label = rest
            elif d == ".opcode":
                ptoks = rest.split(None, 1)
                if len(ptoks) != 2 or ptoks[0].lower() not in ("page0", "page1"):
                    raise AsmError(f"line {lineno}: .opcode expects 'page0|page1 <mnemonic>'")
                opcodes.append((0 if ptoks[0].lower() == "page0" else 1,
                                ptoks[1].strip(), lineno))
            else:
                raise AsmError(f"line {lineno}: unknown directive {d!r}")
            continue

        if s.startswith("routine "):
            pending.append((s[len("routine "):].rstrip().rstrip(":").strip(), lineno))
            continue
        if s.endswith(":") and "<-" not in s:
            pending.append((s[:-1].strip(), lineno))
            continue

        mw = Microword(lineno, s)
        mw.fields = bind_statement(s, fields, lineno)
        words.append(mw)
        for name, _ in pending:
            labels[name] = len(words) - 1
        pending = []

    if pending:
        raise AsmError(f"line {pending[0][1]}: '{pending[0][0]}' binds no microword")
    return words, labels, opcodes, fetch_label


# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------
def assemble(text: str, fields: Fields):
    words, label_idx, opcodes, fetch_label = parse(text, fields)

    for addr, mw in enumerate(words):
        mw.addr = addr
    if len(words) > WCS_DEPTH:
        raise AsmError(f"{len(words)} microwords exceed the {WCS_DEPTH}-word store")
    labels = {name: words[idx].addr for name, idx in label_idx.items()}

    if fetch_label is None:
        raise AsmError("no .fetch directive — the fetch entry is undefined")
    if labels.get(fetch_label) != 0:
        raise AsmError(f".fetch {fetch_label} must be at address 0, "
                       f"is at {labels.get(fetch_label)}")

    # resolve any label references in fields (NEXT_ADDR / CALL targets)
    for mw in words:
        for fname, (code, lbl) in list(mw.fields.items()):
            if lbl is not None:
                if lbl not in labels:
                    raise AsmError(f"line {mw.lineno}: undefined label {lbl!r}")
                mw.fields[fname] = (labels[lbl], None)

    validate_rules(words, fields)

    # opcode -> start-address LUT. Byte values are unassigned (D-41), so each
    # binding gets a placeholder sequential index per page for now.
    clut = [0] * LUT_ENTRIES
    page_next = {0: 0, 1: 0}
    placeholders: list[tuple[int, int, str]] = []
    for page, mnem, lineno in opcodes:
        if mnem not in labels:
            raise AsmError(f"line {lineno}: .opcode {mnem!r} has no matching 'routine'")
        idx = page_next[page]
        page_next[page] += 1
        clut[(page << 8) | idx] = labels[mnem]
        placeholders.append((page, idx, mnem))

    return words, labels, clut, placeholders


def field_value(mw: Microword, fname: str) -> int:
    v = mw.fields.get(fname)
    return 0 if v is None else v[0]


def validate_rules(words: list[Microword], fields: Fields):
    for rule in fields.spec.get("rule", []):
        when, req = rule.get("when"), rule.get("require")
        for mw in words:
            if when:
                cur = field_value(mw, when["field"])
                if "not_in" in when and cur in {fields.code_of(when["field"], v) for v in when["not_in"]}:
                    continue
                if "in" in when and cur not in {fields.code_of(when["field"], v) for v in when["in"]}:
                    continue
                if "eq" in when and cur != fields.code_of(when["field"], when["eq"]):
                    continue
            want = fields.code_of(req["field"], req["eq"])
            if field_value(mw, req["field"]) != want:
                raise AsmError(f"line {mw.lineno}: rule {rule['name']!r} violated — "
                               f"{rule['desc']}")


def pack(mw: Microword, fields: Fields) -> int:
    w = 0
    for fname, (code, _) in mw.fields.items():
        f = fields.by_name[fname]
        w |= (code & f["mask"]) << f["lsb"]
    return w


# ---------------------------------------------------------------------------
# Emit the single image + sim slices
# ---------------------------------------------------------------------------
def build_image(words, clut, fields: Fields) -> bytearray:
    img = bytearray([FILL]) * IMG_BYTES
    for mw in words:
        w = pack(mw, fields)
        for k in range(N_WCS):
            img[k * SEG_SIZE + mw.addr] = (w >> (8 * k)) & 0xFF
    for i, entry in enumerate(clut):
        img[SEG_LUT_LO * SEG_SIZE + i] = entry & 0xFF
        img[SEG_LUT_HI * SEG_SIZE + i] = (entry >> 8) & 0x0F
    return img


def emit(img: bytearray, outdir: Path):
    outdir.mkdir(parents=True, exist_ok=True)
    bypass = outdir / "sim" / "bypass"
    bypass.mkdir(parents=True, exist_ok=True)

    def hexfile(path: Path, data: bytes):
        path.write_text("".join(f"{b:02x}\n" for b in data))

    # The single image is BOTH the burnable truth and the simulation input: the
    # sim's EEPROM model loads this one file and the modeled microcode loader fans it
    # out to the 13 SRAMs, so the loading circuit is exercised on every run
    # (toolchain.md §3.5). The .hex is the $readmemh form of the same bytes.
    (outdir / "blip_microcode.bin").write_bytes(img)
    hexfile(outdir / "blip_microcode.hex", img)

    # Optional DIRECT-LOAD BYPASS: per-SRAM slices that pre-load the SRAM models
    # without the loader, to isolate a loader bug from a microcode bug. Not the
    # default sim path — these are byte-identical cuts of the image above.
    for k in range(N_WCS):
        hexfile(bypass / f"wcs{k:02d}.hex", img[k * SEG_SIZE:(k + 1) * SEG_SIZE])
    hexfile(bypass / "lut_lo.hex", img[SEG_LUT_LO * SEG_SIZE:SEG_LUT_LO * SEG_SIZE + LUT_ENTRIES])
    hexfile(bypass / "lut_hi.hex", img[SEG_LUT_HI * SEG_SIZE:SEG_LUT_HI * SEG_SIZE + LUT_ENTRIES])

    manifest = ["# segment -> chip -> EEPROM offset (chip-major, 8 KiB segments)"]
    for k in range(N_WCS):
        manifest.append(f"seg {k:2d}  WCS SRAM {k:2d}        offset 0x{k*SEG_SIZE:05x}")
    manifest.append(f"seg {SEG_LUT_LO:2d}  opcode LUT low     offset 0x{SEG_LUT_LO*SEG_SIZE:05x}")
    manifest.append(f"seg {SEG_LUT_HI:2d}  opcode LUT high5   offset 0x{SEG_LUT_HI*SEG_SIZE:05x}")
    (outdir / "manifest.txt").write_text("\n".join(manifest) + "\n")


def roundtrip(img: bytearray, words, clut, fields: Fields):
    """Re-read the emitted image and confirm every word/LUT entry survives."""
    for mw in words:
        w = sum(img[k * SEG_SIZE + mw.addr] << (8 * k) for k in range(N_WCS))
        for fname, (code, _) in mw.fields.items():
            f = fields.by_name[fname]
            got = (w >> f["lsb"]) & f["mask"]
            if got != (code & f["mask"]):
                raise AsmError(f"round-trip FAIL @addr {mw.addr} {fname}: "
                               f"{got} != {code}")
    for i, entry in enumerate(clut):
        lo = img[SEG_LUT_LO * SEG_SIZE + i]
        hi = img[SEG_LUT_HI * SEG_SIZE + i]
        if (hi << 8 | lo) != entry:
            raise AsmError(f"round-trip FAIL @lut {i}: {hi<<8|lo} != {entry}")


def main(argv: list[str]) -> int:
    import argparse
    p = argparse.ArgumentParser(description="BLIP microcode assembler")
    p.add_argument("source", nargs="?", default=str(DEFAULT_SRC),
                   help=f"microcode source (.uc)  [default: {DEFAULT_SRC}]")
    p.add_argument("-f", "--field-def", default=str(DEFAULT_SPEC),
                   help=f"control-word field definition  [default: {DEFAULT_SPEC}]")
    args = p.parse_args(argv[1:])

    src = Path(args.source)
    with open(args.field_def, "rb") as f:
        fields = Fields(tomllib.load(f))

    try:
        words, labels, clut, placeholders = assemble(src.read_text(), fields)
        img = build_image(words, clut, fields)
        roundtrip(img, words, clut, fields)
    except AsmError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    outdir = OUTDIR
    emit(img, outdir)

    used = sum(1 for b in img if b != FILL)
    print(f"assembled {src.name}: {len(words)} microwords, {len(placeholders)} opcode entries")
    print("  routines: " + ", ".join(f"{n}@{a}" for n, a in sorted(labels.items(), key=lambda x: x[1])))
    if placeholders:
        print("  opcode LUT (placeholder indices — byte values unassigned, D-41):")
        for page, idx, mnem in placeholders:
            print(f"    page{page} #{idx} -> {mnem} @{labels[mnem]}")
    print(f"  image:  {outdir/'blip_microcode.bin'} (+ .hex)  "
          f"({IMG_BYTES} bytes, {used} non-zero, {N_SEG} segments)")
    print(f"  sim in: blip_microcode.hex — single image; loader fans out to {N_SEG} SRAMs")
    print(f"  bypass: {outdir/'sim'/'bypass'}/  (per-SRAM slices, direct-load only)")
    print("  round-trip: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
