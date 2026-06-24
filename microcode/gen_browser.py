#!/usr/bin/env python3
"""Generate a self-contained HTML microcode browser for BLIP.

Reads microcode/src/blip.uc + control_word.toml through the assembler
(tools/uasm/uasm.py), then renders a single static HTML file:

  * LEFT panel  — the opcode->start-address LUT; each opcode links to the
    microaddress its routine starts at.
  * RIGHT panel — the writable control store, one microaddress per row, the
    full 88-bit word shown both as raw hex and decomposed into colour-coded
    field columns (pinned header). The view is SEQUENCER-FOCUSED: the
    microsequencer op is a colour badge, and a branch/jump/call NEXT_ADDR is a
    link you can click to jump to the target row. The final column is the
    register-transfer source line (the semantics of the word).

Output: microcode/build/microcode.html  (open in any browser; no dependencies).
"""
from __future__ import annotations
import html
import json
import sys
import tomllib
from bisect import bisect_right
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools" / "uasm"))
import uasm  # noqa: E402

SRC = REPO / "microcode" / "src" / "blip.uc"
SPEC = REPO / "microcode" / "control_word.toml"
OUT = REPO / "microcode" / "build" / "microcode.html"

# microsequencer op -> CSS colour class (easy to differentiate at a glance)
SEQ_COLOR = {
    "INC": "#6b7280", "BRANCH": "#a855f7", "JUMP": "#3b82f6",
    "DISPATCH_IR": "#22c55e", "RETURN_FETCH": "#14b8a6", "WAIT": "#ef4444",
    "CALL": "#f59e0b", "RETURN": "#ec4899",
}
SEQ_DESC = {
    "INC": "fall through to µPC+1",
    "BRANCH": "if (cond ⊕ pol) then µPC ← NEXT_ADDR, else µPC+1",
    "JUMP": "unconditional µPC ← NEXT_ADDR",
    "DISPATCH_IR": "µPC ← opcode-LUT[{DISPATCH_PAGE, IR}]",
    "RETURN_FETCH": "return to the fetch entry (a pending trap is vectored away)",
    "WAIT": "hold µPC (bus /WAIT stretch or panel single-step)",
    "CALL": "µSR ← µPC+1; µPC ← NEXT_ADDR (enter a micro-subroutine)",
    "RETURN": "µPC ← µSR (resume the caller of a micro-subroutine)",
}
COND_SYM = {
    "Z": "Z", "C": "C", "N": "N", "V": "V", "C_OR_Z": "C∨Z", "N_XOR_V": "N⊻V",
    "Z_OR_NXORV": "Z∨(N⊻V)", "TRUE": "true", "ULOOP": "µloop.0",
    "IRQ_PENDING": "irq", "NMI_PENDING": "nmi", "WAIT_READY": "wait-rdy",
    "MULTIBYTE_LAST": "mb-last", "PRIV_VIOLATION": "priv",
    "ILLEGAL_OPCODE": "illegal", "SPARE": "spare",
}
# datapath fields to show as columns, in bit order (SPARE/sequencer omitted)
DP_FIELDS = [
    "IR_LOAD", "LEFT_SRC", "LEFT_LANE", "RIGHT_SRC", "ALU_OP", "ALU_SHIFT",
    "ALU_CIN", "ALU_WIDTH", "FLAG_WE", "V_SRC", "C_SRC", "Z_ACCUM",
    "CC_WRITE_SRC", "CC_MI_LOAD", "Z_DEST", "Z_LANE", "PC_CTRL", "MAR_CTRL",
    "X_CTRL", "Y_CTRL", "MEM_OP", "MMU_ADDR_SRC", "MMU_MAP_SEL", "MMU_PT_OP",
    "SP_BANK", "TAS_LOCK",
]

# datapath field -> lens group, and the lenses (which groups each shows)
LENS_GROUP = {
    "LEFT_SRC": "alu", "LEFT_LANE": "alu", "RIGHT_SRC": "alu", "ALU_OP": "alu",
    "ALU_SHIFT": "alu", "ALU_CIN": "alu", "ALU_WIDTH": "alu",
    "FLAG_WE": "flag", "V_SRC": "flag", "C_SRC": "flag", "Z_ACCUM": "flag",
    "CC_WRITE_SRC": "flag", "CC_MI_LOAD": "flag",
    "IR_LOAD": "reg", "Z_DEST": "reg", "Z_LANE": "reg", "PC_CTRL": "reg",
    "MAR_CTRL": "reg", "X_CTRL": "reg", "Y_CTRL": "reg",
    "MEM_OP": "mem", "MMU_ADDR_SRC": "mem", "MMU_MAP_SEL": "mem",
    "MMU_PT_OP": "mem", "SP_BANK": "mem", "TAS_LOCK": "mem",
}
LENSES = {            # lens -> the groups it keeps visible
    "all": {"alu", "flag", "reg", "mem"},
    "sequencer": set(),
    "ALU": {"alu", "flag", "reg"},
    "memory": {"mem", "reg"},
    "flags/CC": {"flag", "reg"},
}


def field_hue(i: int) -> int:
    return int((i * 137.508) % 360)            # golden-angle spread


# Hand-written, educational per-VALUE explanations (the control_word.toml `role`
# only describes the field; these teach what each value actually does). Keyed by
# field -> {value name: explanation}. Missing values just show their name.
VALUE_DOC = {
    "IR_LOAD": {
        "HOLD": "leave IR unchanged",
        "OPCODE": "latch the byte being read into IR — opcode fetch (or the page-1 prefix's second byte)",
    },
    "LEFT_SRC": {
        "NONE": "nothing drives the LEFT bus this cycle",
        "D": "the 16-bit accumulator A:B drives LEFT",
        "X": "index register X drives LEFT", "Y": "index register Y drives LEFT",
        "USP": "the user stack pointer drives LEFT (explicit, privileged)",
        "SSP": "the supervisor stack pointer drives LEFT (explicit)",
        "PC": "the program counter drives LEFT", "MAR": "the memory-address register drives LEFT",
        "SCR1": "scratch register 1 drives LEFT", "SCR2": "scratch register 2 drives LEFT",
        "MDR": "the memory-data register (last byte read) drives LEFT",
        "IR_IMM": "an immediate field taken from IR drives LEFT",
        "MMU_ENTRY": "an MMU page-table entry drives LEFT (STMMU read-back)",
        "CC": "the condition-code register drives LEFT (e.g. to push CC in a trap frame)",
        "ACTIVE_SP": "the active stack pointer — USP or SSP per SP_BANK — drives LEFT",
    },
    "LEFT_LANE": {
        "FULL16": "pass all 16 bits of the LEFT source unchanged",
        "LOW": "drive only the low byte (bits 7:0); the high byte is ignored",
        "SIGN_EXT": "take the low byte and sign-extend it to 16 bits — copy bit 7 across the whole "
                    "high byte. This is how a signed 8-bit offset like (X+n8) becomes a 16-bit "
                    "value before it is added to an index register.",
        "HIGH_TO_LOW": "route the high byte down onto the low-byte lane — used to put a register's "
                       "high half (e.g. A, or PC-high) onto the 8-bit memory bus for a store.",
    },
    "RIGHT_SRC": {
        "SCR1": "scratch register 1 on the RIGHT ALU input",
        "SCR2": "scratch register 2 on the RIGHT ALU input",
        "CONST_M2": "the constant −2 from the const generator (D-36)",
        "CONST_M1": "the constant −1 (e.g. pre-decrement an index/SP)",
        "CONST_0": "the constant 0",
        "CONST_P1": "the constant +1",
        "CONST_P2": "the constant +2 — e.g. advance a stack pointer past a 16-bit slot",
    },
    "ALU_OP": {
        "PASS_L": "pass the LEFT input straight to Z (a plain move/latch)",
        "PASS_R": "pass the RIGHT input to Z (e.g. load a small constant)",
        "ADD": "Z = LEFT + RIGHT", "SUB": "Z = LEFT − RIGHT",
        "ADC": "Z = LEFT + RIGHT + carry-in (CC.C) — multi-byte/word add chains",
        "SBC": "Z = LEFT − RIGHT − borrow (CC.C) — multi-byte/word subtract chains",
        "AND": "Z = LEFT & RIGHT (bitwise)", "OR": "Z = LEFT | RIGHT (bitwise)",
        "EOR": "Z = LEFT ^ RIGHT (bitwise exclusive-or)",
        "COM": "Z = ~LEFT (one's complement) — unary, RIGHT unused",
        "NEG": "Z = −LEFT (two's complement negate) — unary",
        "SHIFT": "shift/rotate LEFT by one place; ALU_SHIFT selects which",
    },
    "ALU_SHIFT": {
        "ASL": "shift left by 1 — bit0←0, C←old bit7 (×2)",
        "LSR": "logical shift right by 1 — bit7←0, C←old bit0 (unsigned ÷2)",
        "ASR": "arithmetic shift right by 1 — sign bit preserved, C←old bit0 (signed ÷2)",
        "ROL": "rotate left through carry — bit0←C, C←old bit7",
        "ROR": "rotate right through carry — bit7←C, C←old bit0",
    },
    "ALU_CIN": {"ZERO": "carry-in forced to 0 (plain ADD/SUB)",
                "CC_C": "carry-in = CC.C when the op doesn't already imply it"},
    "ALU_WIDTH": {"W8": "operate on 8 bits (the low byte lane)",
                  "W16": "operate on the full 16-bit word (D / X / Y / SP / MAR / PC)"},
    "V_SRC": {"FROM_ALU": "write V from the ALU's signed-overflow output",
              "FORCE_0": "force V to 0 (logical ops, LD/ST clear V)",
              "FORCE_1": "force V to 1"},
    "C_SRC": {"FROM_ALU": "write C from the ALU's carry/borrow output",
              "FORCE_0": "force C to 0 (e.g. CLR)", "FORCE_1": "force C to 1 (e.g. COM)"},
    "Z_ACCUM": {"NO": "Z comes from this cycle's result alone",
                "ACCUM": "AND this lane's zero-result with the previous lane's — forms a true 16-bit "
                         "Z across the two byte cycles of a wide op"},
    "CC_WRITE_SRC": {"ALU_FLAGS": "update individual flags from the ALU (the normal case)",
                     "WHOLE_Z": "load the entire CC register from Z (RTI / PULS CC)",
                     "AND_MASK": "CC = CC AND the immediate mask (ANDCC / CWAI)",
                     "OR_MASK": "CC = CC OR the immediate mask (ORCC)"},
    "CC_MI_LOAD": {"HOLD": "leave the privileged M (mode) and I (IRQ-mask) bits unchanged",
                   "SET_ON_ENTRY": "on trap entry set M (supervisor) and I (mask) — after the old CC is saved",
                   "FROM_Z": "restore M and I from Z (RTI)",
                   "EXPLICIT": "set/clear I explicitly (SEI / CLI)"},
    "Z_DEST": {"NONE": "nothing latches Z (e.g. a compare — only flags update)",
               "D": "latch Z into D (A:B)", "USP": "latch Z into the user SP",
               "SSP": "latch Z into the supervisor SP", "ACTIVE_SP": "latch Z into the active SP (per SP_BANK)",
               "SCR1": "latch Z into scratch 1", "SCR2": "latch Z into scratch 2",
               "MDR": "latch Z into the memory-data register", "IR": "latch Z into IR",
               "CC": "latch Z into the condition-code register"},
    "Z_LANE": {"FULL16": "latch all 16 bits of Z", "LOW": "latch only the low byte (B / .low lane)",
               "HIGH": "latch only the high byte (A / .high lane)"},
    "PC_CTRL": {"HOLD": "PC unchanged", "LOAD": "load PC from Z (a jump/branch target)",
                "COUNT": "PC += 1 via its off-bus counter (ticks alongside an unrelated ALU op)"},
    "MAR_CTRL": {"HOLD": "MAR unchanged", "LOAD": "load MAR from Z (capture an effective address)",
                 "COUNT": "MAR += 1 via its off-bus counter (walk a multi-byte access)"},
    "X_CTRL": {"HOLD": "X unchanged", "LOAD": "load X from Z",
               "COUNT": "X += 1 via its off-bus counter (auto-increment)"},
    "Y_CTRL": {"HOLD": "Y unchanged", "LOAD": "load Y from Z",
               "COUNT": "Y += 1 via its off-bus counter (auto-increment)"},
    "MEM_OP": {"IDLE": "no memory access this cycle",
               "READ": "read a byte at the translated address; the data appears on Z (and MDR)",
               "WRITE": "write the LEFT-bus byte to the translated address"},
    "MMU_ADDR_SRC": {"TRANSLATE_MAR": "translate the address held in MAR (data accesses)",
                     "TRANSLATE_PC": "translate the address in PC — the instruction/operand stream, "
                                     "with no PC→MAR copy",
                     "DIRECT_PHYSICAL": "emit a physical address untranslated (reset, vector fetch)"},
    "MMU_MAP_SEL": {"FOLLOW_M": "use the map set CC.M selects (kernel in supervisor, user in user mode)",
                    "FORCE_KERNEL": "force the kernel map regardless of mode",
                    "FORCE_USER": "force the user map (e.g. copyin/copyout)",
                    "FROM_IMM8": "select the map from an 8-bit immediate (cross-map copy)"},
    "MMU_PT_OP": {"IDLE": "no page-table access", "WRITE_ENTRY": "write an MMU page-table entry (LDMMU)",
                  "READ_ENTRY": "read an MMU page-table entry (STMMU)"},
    "SP_BANK": {"FOLLOW_M": "the active SP follows CC.M (USP in user, SSP in supervisor)",
                "FORCE_SSP": "force the supervisor SP (e.g. while building a trap frame)"},
    "TAS_LOCK": {"OFF": "normal bus cycle",
                 "LOCK": "hold the bus across this read-modify-write so TAS is indivisible"},
    "FLAG_WE": {"H": "half-carry flag (BCD aid)", "N": "negative flag (result's top bit)",
                "Z": "zero flag (result == 0)", "V": "signed-overflow flag",
                "C": "carry / borrow flag"},
}


# Fields whose ZERO code is a real *selection* (FROM_ALU / TRANSLATE_MAR / SCR1 /
# PASS_L / FULL16 / W8 / FOLLOW_M …), not an inert HOLD/IDLE/NONE. For these the
# default is "load-bearing" — the word relies on it — exactly when an enabling
# condition holds. field -> (per-word context flag, why). Everything not listed is
# treated as inert at zero (stays grey when 0).
RELIED = {
    "LEFT_LANE":    ("alu_left",     "ALU has a LEFT operand"),
    "ALU_OP":       ("alu_left",     "ALU drives Z from LEFT (PASS_L)"),
    "ALU_CIN":      ("arith",        "ADD/SUB carry-in = 0"),
    "ALU_WIDTH":    ("alu_left",     "ALU op width"),
    "RIGHT_SRC":    ("binary_op",    "binary ALU op reads RIGHT"),
    "V_SRC":        ("we_v",         "V is written this cycle"),
    "C_SRC":        ("we_c",         "C is written this cycle"),
    "CC_WRITE_SRC": ("writes_flags", "flags written from the ALU"),
    "Z_LANE":       ("z_dest",       "a dest latches Z"),
    "MMU_ADDR_SRC": ("mem",          "memory access this cycle"),
    "MMU_MAP_SEL":  ("mem",          "memory access this cycle"),
    "SP_BANK":      ("uses_sp",      "SP is referenced"),
}


class Model:
    def __init__(self):
        self.fields = uasm.Fields(tomllib.load(open(SPEC, "rb")))
        self.words, self.labels, self.clut, self.entries = uasm.assemble(
            SRC.read_text(), self.fields)
        self.srclines = SRC.read_text().splitlines()
        self.by_name = self.fields.by_name
        # addr -> labels at that address
        self.addr_labels: dict[int, list[str]] = {}
        for name, addr in self.labels.items():
            self.addr_labels.setdefault(addr, []).append(name)
        # routine boundaries: opcode mnemonics + the three internal routines
        rnames = {m for _, _, m in self.entries} | {"FETCH", "PREFIX_P1", "BR_TAKEN"}
        starts = sorted((self.labels[n], n) for n in rnames if n in self.labels)
        self.start_addrs = [a for a, _ in starts]
        self.start_names = [n for _, n in starts]
        self._build_graph()

    # ---- control-flow graph, xrefs, gutter arrows, staging tax ------------
    def _build_graph(self):
        self.xrefs: dict[int, list] = defaultdict(list)   # tgt -> [(src|None, kind)]
        self.inbound: dict[int, int] = defaultdict(int)   # tgt -> # of jump in-edges
        jumps = []                                        # (src, tgt) intra-routine
        for mw in self.words:
            op = self.sym("USEQ_OP", self.code(mw, "USEQ_OP"))
            if op in ("JUMP", "BRANCH", "CALL"):
                tgt = self.code(mw, "NEXT_ADDR")
                self.xrefs[tgt].append((mw.addr, op.lower()))
                self.inbound[tgt] += 1
                if self.routine_of(mw.addr) == self.routine_of(tgt):
                    jumps.append((mw.addr, tgt))
            elif op == "RETURN_FETCH":
                self.xrefs[0].append((mw.addr, "fetch"))
                self.inbound[0] += 1
        for _, byte, mnem in self.entries:                # opcode-LUT in-edges
            self.xrefs[self.labels[mnem]].append((None, f"opcode {byte:#04x} {mnem}"))
        self.arrows = self._lanes(jumps)                  # (src, tgt, lane)
        self.staging = self._staging()                    # {addr} of bus-staging words

    @staticmethod
    def _lanes(jumps):
        """Assign each intra-routine arrow a lane so overlapping spans don't collide
           (shortest spans take the inner lanes, so loops nest neatly)."""
        out, lanes = [], []
        for s, t in sorted(jumps, key=lambda a: abs(a[0] - a[1])):
            lo, hi = min(s, t), max(s, t)
            li = next((i for i, occ in enumerate(lanes)
                       if all(hi < a or lo > b for a, b in occ)), None)
            if li is None:
                li, _ = len(lanes), lanes.append([])
            lanes[li].append((lo, hi))
            out.append((s, t, li))
        return out

    def _staging(self):
        """A word is bus-staging tax if it COPIES a register/MDR value into SCR1/SCR2
           (a non-memory move/lane-steer) only so the next word can read it on the
           RIGHT bus — the asymmetric-bus tax (microcode.md §7.3). Necessary operand
           reads into a scratch (MEM_OP=read) are excluded: the read happens anyway."""
        scr_z = {self.fields.code_of("Z_DEST", "SCR1"): self.fields.code_of("RIGHT_SRC", "SCR1"),
                 self.fields.code_of("Z_DEST", "SCR2"): self.fields.code_of("RIGHT_SRC", "SCR2")}
        binop = ("ADD", "ADC", "SUB", "SBC", "AND", "OR", "EOR")
        out = set()
        for i, mw in enumerate(self.words[:-1]):
            zd = self.code(mw, "Z_DEST")
            nxt = self.words[i + 1]
            if (zd in scr_z and self.code(mw, "MEM_OP") == 0          # a register copy, not a read
                    and self.code(mw, "LEFT_SRC") != 0                # ... of something
                    and self.code(nxt, "RIGHT_SRC") == scr_z[zd]
                    and self.sym("ALU_OP", self.code(nxt, "ALU_OP")) in binop
                    and self.routine_of(i) == self.routine_of(i + 1)):
                out.add(i)
        return out

    def code(self, mw, fname: str) -> int:
        v = mw.fields.get(fname)
        return v[0] if v else 0                 # absent field -> 0 (the inert default)

    def sym(self, fname: str, code: int) -> str:
        f = self.by_name[fname]
        if f.get("enc") == "mask":
            on = [k[3:] for k, pos in f["bits_"].items() if (code >> pos) & 1]
            return "".join(on) if on else "·"
        vals = f.get("values")
        if vals:
            inv = {v: k for k, v in vals.items()}
            return inv.get(code, f"0x{code:x}")
        return f"0x{code:x}" if code else "·"

    def ctx(self, mw) -> dict:
        """Per-word flags that tell whether a default-valued field is load-bearing."""
        fw = self.code(mw, "FLAG_WE")
        b = self.by_name["FLAG_WE"]["bits_"]
        aluop = self.sym("ALU_OP", self.code(mw, "ALU_OP"))
        left = self.code(mw, "LEFT_SRC")
        zdest = self.code(mw, "Z_DEST")
        return {
            "we_v": bool((fw >> b["WE_V"]) & 1),
            "we_c": bool((fw >> b["WE_C"]) & 1),
            "writes_flags": fw != 0,
            "alu_left": left != 0,
            "binary_op": aluop in ("ADD", "ADC", "SUB", "SBC", "AND", "OR", "EOR", "PASS_R"),
            "arith": aluop in ("ADD", "SUB"),
            "mem": self.code(mw, "MEM_OP") != 0,
            "z_dest": zdest != 0,
            "uses_sp": left == self.fields.code_of("LEFT_SRC", "ACTIVE_SP")
                       or zdest == self.fields.code_of("Z_DEST", "ACTIVE_SP"),
        }

    def tip(self, fname: str, code: int, status: str = "") -> str:
        """A semantic tooltip: FIELD[bits] = VALUE (hex), the field's role, status."""
        f = self.by_name[fname]
        msb = f["lsb"] + f["width"] - 1
        t = f"{fname}[{msb}:{f['lsb']}] = {self.sym(fname, code)} ({code:#x})"
        role = f.get("role")
        if role:
            t += "\n" + role
        if status:
            t += "\n" + status
        return t

    def routine_of(self, addr: int) -> str:
        i = bisect_right(self.start_addrs, addr) - 1
        return self.start_names[i] if i >= 0 else ""

    def target_name(self, addr: int) -> str:
        labs = self.addr_labels.get(addr)
        return labs[0] if labs else self.routine_of(addr)


def esc(s) -> str:
    return html.escape(str(s))


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------
def render_lut(m: Model) -> str:
    rows = []
    for page in (0, 1):
        ents = sorted((b, mn) for p, b, mn in m.entries if p == page)
        rows.append(f'<tr class="lutpage"><td colspan="2">PAGE {page}'
                    f' &middot; {len(ents)} opcodes</td></tr>')
        for byte, mnem in ents:
            addr = m.labels[mnem]
            rows.append(
                f'<tr><td class="op">{byte:#04x}</td>'
                f'<td><a href="#" data-goto="{addr}" class="mn">{esc(mnem)}</a>'
                f'<span class="ad">@{addr}</span></td></tr>')
    return "\n".join(rows)


def render_seq_cell(m: Model, mw) -> tuple[str, str, str, str]:
    """Return (op-badge, next-cell, cond-cell, uloop-cell) HTML for a word."""
    code = m.code(mw, "USEQ_OP")
    op = m.sym("USEQ_OP", code)
    color = SEQ_COLOR.get(op, "#6b7280")
    optip = esc(m.tip("USEQ_OP", code, SEQ_DESC.get(op, "")))
    badge = f'<span class="seq" style="background:{color}" title="{optip}">{op}</span>'

    na = m.code(mw, "NEXT_ADDR")
    if op in ("JUMP", "BRANCH", "CALL"):
        tgt = m.target_name(na)
        arrow = {"JUMP": "→", "BRANCH": "?→", "CALL": "call→"}[op]
        ntip = esc(m.tip("NEXT_ADDR", na, f"{op} target → {tgt} @ {na:#05x}"))
        nxt = (f'<a href="#" data-goto="{na}" class="next" title="{ntip}">'
               f'{arrow} {na:#05x}</a> <span class="tn">{esc(tgt)}</span>')
    elif op == "DISPATCH_IR":
        pg = m.code(mw, "DISPATCH_PAGE")
        ptip = esc(f"DISPATCH_IR — µPC ← opcode-LUT[{{page{pg}, IR}}]")
        nxt = f'<span class="dim" title="{ptip}">LUT[IR{" page1" if pg else ""}]</span>'
    elif op == "RETURN_FETCH":
        nxt = (f'<a href="#" data-goto="0" class="next" title="{esc(SEQ_DESC[op])}">'
               f'→ FETCH</a>')
    elif op == "RETURN":
        nxt = f'<span class="dim" title="{esc(SEQ_DESC[op])}">→ µSR</span>'
    elif op == "WAIT":
        nxt = f'<span class="dim" title="{esc(SEQ_DESC[op])}">hold</span>'
    else:
        nxt = f'<span class="dim" title="{esc(SEQ_DESC[op])}">+1</span>'

    cond = ""
    if op == "BRANCH":
        sc = m.code(mw, "UCOND_SEL")
        pol = m.code(mw, "UCOND_POL")
        ctext = ("¬" if pol else "") + COND_SYM.get(m.sym("UCOND_SEL", sc), "")
        ctip = esc(m.tip("UCOND_SEL", sc,
                   f"polarity {'NEGATE' if pol else 'ASSERT'} — branch taken when {ctext}"))
        cond = f'<span class="cond" title="{ctip}">{esc(ctext)}</span>'

    ul = m.code(mw, "ULOOP_CTRL")
    ulc = "" if ul == 0 else (
        f'<span class="ulp" title="{esc(m.tip("ULOOP_CTRL", ul))}">'
        f'{m.sym("ULOOP_CTRL", ul)}</span>')
    return badge, nxt, cond, ulc


def render_rows(m: Model) -> str:
    hue = {f: field_hue(i) for i, f in enumerate(DP_FIELDS)}
    out = []
    prev_rtn = None
    for mw in m.words:
        a = mw.addr
        rtn = m.routine_of(a)
        op = m.sym("USEQ_OP", m.code(mw, "USEQ_OP"))
        jumpish = op in ("JUMP", "BRANCH", "CALL")     # an explicit NEXT_ADDR redirect

        # routine separator + label badges
        sep = ""
        if rtn != prev_rtn:
            sep = ' rstart'
            prev_rtn = rtn
        labs = m.addr_labels.get(a, [])
        labhtml = " ".join(f'<span class="lab">{esc(x)}</span>' for x in labs)
        inb = m.inbound.get(a, 0)
        inbadge = (f'<span class="xin" title="{inb} inbound jump(s) — click the row to list them">'
                   f'↳{inb}</span>') if inb else ""

        badge, nxt, cond, ulc = render_seq_cell(m, mw)

        # raw 88-bit word, byte 10..0 (MSB first)
        w = uasm.pack(mw, m.fields)
        wbytes = " ".join(f"{(w >> (8 * k)) & 0xff:02x}" for k in range(10, -1, -1))

        # datapath field cells. A cell is "active" (coloured + tinted, identically)
        # when it is explicitly set OR a load-bearing default; otherwise idle (grey).
        # The set-vs-relied distinction lives only in the tooltip.
        # The full semantic tooltip is built lazily in JS on hover (from FINFO),
        # so the per-cell payload is just data-c (the code) — keeping the file small.
        # `rel` marks a load-bearing default (code 0 the word relies on) so JS can
        # render it identically to a set cell but explain the dependency.
        dp = []
        cx = m.ctx(mw)
        for f in DP_FIELDS:
            c = m.code(mw, f)
            s = esc(m.sym(f, c))
            h = hue[f]
            rel = RELIED.get(f)
            cc = f"c-{f}"                       # column class (column lenses)
            if c != 0:
                dp.append(f'<td class="dp on {cc}" style="color:hsl({h},85%,72%);'
                          f'background:hsla({h},80%,55%,.13)" data-c="{c:x}">'
                          f'{s}<sub>{c:x}</sub></td>')
            elif rel and cx[rel[0]]:
                dp.append(f'<td class="dp on rel {cc}" style="color:hsl({h},85%,72%);'
                          f'background:hsla({h},80%,55%,.13)" data-c="{c:x}">'
                          f'{s}<sub>{c:x}</sub></td>')
            else:
                dp.append(f'<td class="dp dim {cc}" data-c="{c:x}">{s}</td>')

        rawnote = m.srclines[mw.lineno - 1].strip() if mw.lineno - 1 < len(m.srclines) else ""
        note = esc(rawnote)
        datatxt = esc(" ".join([rtn, " ".join(labs), op, rawnote]))

        atip = f"microaddress {a:#05x}" + (f" — in routine {rtn}" if rtn else "")
        rtip = esc((f"routine {rtn}" if rtn else "") +
                   (" · labels here: " + ", ".join(labs) if labs else ""))
        wtip = "88-bit control word — shown as bytes b10→b0 (MSB→LSB)"
        ntip = f"register-transfer source (blip.uc line {mw.lineno})"

        cls = "row" + sep + (" jumpish" if jumpish else "") + (" staging" if a in m.staging else "")
        out.append(
            f'<tr id="a{a}" class="{cls}" data-op="{op}" data-rtn="{esc(rtn)}" data-txt="{datatxt}">'
            f'<td class="addr" title="{esc(atip)}">{a:#05x}</td>'
            f'<td class="rtn" title="{rtip}">{inbadge}{esc(rtn)} {labhtml}</td>'
            f'<td class="c-op">{badge}</td>'
            f'<td class="c-next">{nxt}</td>'
            f'<td class="c-cond">{cond}</td>'
            f'<td class="c-ulp">{ulc}</td>'
            f'<td class="word" title="{esc(wtip)}">{wbytes}</td>'
            + "".join(dp)
            + f'<td class="note" title="{esc(ntip)}">{note}</td>'
            "</tr>")
    return "\n".join(out)


def render_header(m: Model) -> str:
    hue = {f: field_hue(i) for i, f in enumerate(DP_FIELDS)}
    fixed = ['<th class="addr">addr</th>', '<th class="rtn">routine</th>',
             '<th>seq op</th>', '<th>next</th>', '<th>cond</th>', '<th>µloop</th>',
             '<th class="word">88-bit word (b10..b0)</th>']
    dp = []
    for f in DP_FIELDS:
        h = hue[f]
        short = f.replace("_", "<br>")
        dp.append(f'<th class="dph c-{f}" style="background:hsla({h},70%,45%,.9)" '
                  f'title="{f}">{short}</th>')
    return "<tr>" + "".join(fixed) + "".join(dp) + '<th class="note">notes (source)</th></tr>'


CSS = """
:root{--bg:#0d1117;--fg:#c9d1d9;--mut:#6e7681;--line:#21262d;--panel:#161b22;}
*{box-sizing:border-box}
html,body{margin:0;height:100%;overflow:hidden;background:var(--bg);color:var(--fg);
  font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
body{display:flex;flex-direction:column}
#bar{flex:0 0 auto;z-index:30;display:flex;gap:10px;align-items:center;
  padding:8px 12px;background:var(--panel);border-bottom:1px solid var(--line)}
#bar b{color:#58a6ff;font-size:13px}
#bar input{background:#0d1117;border:1px solid var(--line);color:var(--fg);
  padding:4px 8px;border-radius:6px;width:280px;font:inherit}
#bar .leg{margin-left:auto;display:flex;gap:6px;flex-wrap:wrap}
#bar .leg span{padding:1px 7px;border-radius:10px;color:#08111e;font-weight:700}
#wrap{flex:1 1 auto;min-height:0;display:flex}
#lut{flex:0 0 240px;min-height:0;overflow:auto;border-right:1px solid var(--line);background:var(--panel)}
#lut table{border-collapse:collapse;width:100%}
#lut td{padding:2px 6px;border-bottom:1px solid var(--line);white-space:nowrap}
#lut .lutpage td{position:sticky;top:0;background:#1f2937;color:#9ca3af;
  font-weight:700;border-bottom:1px solid var(--line)}
#lut .op{color:#f59e0b;text-align:right}
#lut .mn{color:#79c0ff;text-decoration:none}
#lut .mn:hover{text-decoration:underline}
#lut .ad{color:var(--mut);margin-left:6px}
#store{flex:1 1 auto;min-width:0;min-height:0;overflow:auto}
table.mc{border-collapse:separate;border-spacing:0;white-space:nowrap}
table.mc thead th{position:sticky;top:0;z-index:10;background:#0f141b;
  border-bottom:2px solid #30363d;padding:4px 6px;text-align:left;
  color:#c9d1d9;vertical-align:bottom;font-size:10px}
table.mc th.dph{color:#0d1117;font-weight:700;text-align:center;line-height:1.05}
table.mc td{padding:2px 6px;border-bottom:1px solid var(--line)}
table.mc td.addr{position:sticky;left:0;z-index:5;background:#0d1117}
table.mc thead th.addr{left:0;z-index:15}
.row:hover td{background:#161b2233}
.row:hover td.addr{background:#12161d}
.row.rstart td{border-top:2px solid #30363d}
.row.jumpish .addr{box-shadow:inset 3px 0 0 #a855f7}
.addr{color:#8b949e;font-weight:700}
.rtn{color:#e3b341;max-width:230px;overflow:hidden;text-overflow:ellipsis}
.lab{color:#6e7681;background:#1f2530;border-radius:4px;padding:0 4px;margin-left:4px}
.seq{color:#08111e;font-weight:800;padding:1px 8px;border-radius:10px;font-size:11px}
.next{color:#79c0ff;text-decoration:none}
.next:hover{text-decoration:underline}
.tn{color:var(--mut)}
.cond{color:#d2a8ff;font-weight:700}
.ulp{color:#f0883e}
.word{color:#56707f;letter-spacing:.5px}
.dp{text-align:center}
.dp.dim{color:#3b424d}
.dp.on{cursor:help}
.dp sub{color:#8b949e;font-size:8px;margin-left:1px}
.cellleg{color:var(--mut)}
.cellleg i{font-style:normal;margin-left:7px}
.cl-on{color:hsl(210,85%,72%);background:hsla(210,80%,55%,.13);padding:0 5px;border-radius:3px}
.cl-idle{color:#3b424d}
.note{color:#8b949e;white-space:nowrap;padding-left:10px;border-left:1px solid var(--line)}
.dim{color:#566}
tr.hide{display:none}
@keyframes fl{0%{background:#bb8009}100%{background:transparent}}
.flash td{animation:fl 1.2s ease-out}
#tip{position:fixed;z-index:100;display:none;pointer-events:none;width:380px;max-width:44vw;
  background:#0b0f16;border:1px solid #30363d;border-radius:9px;padding:10px 12px;
  box-shadow:0 10px 34px #000b;color:#c9d1d9;font-size:11px;line-height:1.5}
#tip .tt-h{font-weight:700;color:#e6edf3;font-size:12.5px}
#tip .tt-bits{color:#8b949e;font-weight:400;margin-left:7px}
#tip .tt-enc{color:#6e7681;float:right;text-transform:uppercase;font-size:9px;letter-spacing:.5px;padding-top:3px}
#tip .tt-role{color:#adbac7;margin:5px 0 8px;padding-bottom:7px;border-bottom:1px solid #21262d}
#tip .tt-status{font-weight:700;margin-bottom:8px;padding:3px 8px;border-radius:5px;display:inline-block}
#tip .tt-set{color:#3fb950;background:#2ea04322}
#tip .tt-rel{color:#e0a82e;background:#bb800922}
#tip .tt-idle{color:#909dab;background:#6e768122}
#tip .tt-vh{color:#6e7681;text-transform:uppercase;font-size:9px;letter-spacing:.6px;margin:2px 0 4px}
#tip .tt-val{display:flex;gap:9px;padding:3px 5px;border-radius:5px}
#tip .tt-val.cur{background:#1f6feb22}
#tip .tt-code{flex:0 0 38px;color:#79c0ff;font-weight:600}
#tip .tt-val.cur .tt-code{color:#a5d6ff}
#tip .tt-vb{flex:1;min-width:0}
#tip .tt-name{color:#adbac7;font-weight:600}
#tip .tt-val.cur .tt-name{color:#e6edf3}
#tip .tt-vdoc{color:#7d8590;font-size:10px;margin-top:1px}
#tip .tt-def{color:#6e7681;font-style:italic;font-weight:400;margin-left:5px}
#tip .tt-cur{color:#58a6ff;font-weight:400;margin-left:5px}
/* toolbar controls */
#bar{flex-wrap:wrap}
.lenses{color:var(--mut)}
.lensbtn,.tglbtn{background:#0d1117;border:1px solid var(--line);color:#adbac7;
  padding:3px 8px;border-radius:6px;font:inherit;cursor:pointer;margin-left:3px}
.lensbtn:hover,.tglbtn:hover{border-color:#3b475a}
.lensbtn.on{background:#1f6feb33;border-color:#1f6feb;color:#cae0ff}
.tglbtn.on{background:#bb800933;border-color:#d29922;color:#ffd479}
/* inbound-xref badge + frozen-addr gutter space + overlays */
.xin{color:#3fb6c0;background:#16323566;border-radius:4px;padding:0 4px;margin-right:5px;cursor:pointer;font-size:10px}
table.mc .addr{padding-left:22px}
body.stage .row.staging td.addr{box-shadow:inset 3px 0 0 #d29922;background:#241c08}
body.stage .row.staging td.rtn,body.stage .row.staging td.note{background:hsla(38,90%,50%,.10)}
.row.sel td{background:#1f6feb26}
.row.sel td.addr{background:#17233d}
#gutter{position:fixed;z-index:6;pointer-events:none;overflow:visible}
/* inspector panel */
#insp{flex:0 0 250px;min-height:0;overflow:auto;background:#0b0f16;
  border-top:2px solid #30363d;padding:10px 14px;display:none}
body.insp #insp{display:block}
.ix-top{display:flex;align-items:center;gap:12px;margin-bottom:5px}
.ix-addr{color:#8b949e;font-weight:700;font-size:13px}
.ix-rtn{color:#e3b341;font-weight:700}
.ix-close{margin-left:auto;background:none;border:1px solid var(--line);color:#8b949e;
  border-radius:6px;cursor:pointer;padding:2px 9px}
.ix-src{color:#adbac7;margin-bottom:9px;padding:4px 8px;background:#0d1117;border-radius:6px;white-space:pre-wrap}
.ix-sec{margin-bottom:9px}
.ix-h{color:#6e7681;text-transform:uppercase;font-size:9px;letter-spacing:.6px;margin-bottom:3px}
.ix-seq{display:flex;gap:16px;align-items:center;flex-wrap:wrap}
.ix-xrefs{display:flex;gap:6px;flex-wrap:wrap}
.ix-x{color:#79c0ff;text-decoration:none;background:#16203566;border:1px solid var(--line);
  border-radius:5px;padding:1px 7px}
.ix-x:hover{border-color:#1f6feb}
.ix-xo{color:#8b949e}
.ix-f{display:flex;gap:10px;align-items:baseline;padding:2px 0;flex-wrap:wrap}
.ix-fn{font-weight:700;min-width:112px}
.ix-set{color:#79c0ff}
.ix-rel{color:#e0a82e}
.ix-fv{color:#e6edf3}
.ix-fv sub{color:#8b949e;font-size:8px}
.ix-fd{color:#7d8590;flex:1;min-width:220px}
.ix-idle{color:#586069;margin-top:6px;font-size:10px}
"""

JS = """
const store=document.getElementById('store');
function goto(addr){
  const r=document.getElementById('a'+addr); if(!r) return;
  document.querySelectorAll('.flash').forEach(e=>e.classList.remove('flash'));
  r.scrollIntoView({behavior:'smooth',block:'center'});
  r.classList.add('flash'); setTimeout(()=>r.classList.remove('flash'),1300);
}
document.addEventListener('click',e=>{
  const t=e.target.closest('[data-goto]');
  if(t){e.preventDefault();goto(t.dataset.goto);}
});
const q=document.getElementById('q');
q.addEventListener('input',()=>{
  const v=q.value.trim().toLowerCase();
  document.querySelectorAll('#store tbody tr').forEach(tr=>{
    tr.classList.toggle('hide', v && !(tr.dataset.txt||'').toLowerCase().includes(v));
  });
});
// rich, educational, styled tooltip for datapath cells (a floating panel)
const tip=document.getElementById('tip');
const FIXED=7;  // addr, routine, seq op, next, cond, uloop, word
function esc(s){return (s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function valRow(codeStr,name,doc,cur,badge){
  return `<div class="tt-val${cur?' cur':''}"><span class="tt-code">${codeStr}</span>`
    +`<div class="tt-vb"><span class="tt-name">${name}${badge}</span>`
    +(doc?`<div class="tt-vdoc">${esc(doc)}</div>`:'')+`</div></div>`;
}
function tipHTML(field,code,status){
  const fi=FINFO[field]; if(!fi) return '';
  let h=`<div class="tt-h">${field}<span class="tt-bits">[${fi.bits}]</span><span class="tt-enc">${fi.enc}</span></div>`;
  if(fi.role) h+=`<div class="tt-role">${esc(fi.role)}</div>`;
  if(status) h+=`<div class="tt-status tt-${status.cls}">${status.text}</div>`;
  if(fi.mask){
    h+=`<div class="tt-vh">flag write-enables</div>`;
    for(const [pos,name,doc] of fi.mask){const on=(code>>pos)&1;
      h+=valRow('bit'+pos,name,doc,!!on,on?' <span class="tt-cur">◀ written</span>':'');}
  } else if(fi.vals){
    h+=`<div class="tt-vh">possible values</div>`;
    for(const [c,name,doc] of fi.vals){const cur=c===code;
      const badge=(c===fi.def?' <span class="tt-def">default</span>':'')
                 +(cur?' <span class="tt-cur">◀ this word</span>':'');
      h+=valRow('0x'+c.toString(16),name,doc,cur,badge);}
  }
  return h;
}
function showTip(el,html){
  if(!html){tip.style.display='none';return;}
  tip.innerHTML=html; tip.style.display='block';
  const r=el.getBoundingClientRect(), tw=tip.offsetWidth, th=tip.offsetHeight;
  let x=r.right+10; if(x+tw>innerWidth-8) x=r.left-tw-10; if(x<8) x=8;
  let y=r.top; if(y+th>innerHeight-8) y=innerHeight-th-8;
  tip.style.left=x+'px'; tip.style.top=Math.max(8,y)+'px';
}
store.addEventListener('mouseover',e=>{
  const td=e.target.closest('td.dp');
  if(!td){tip.style.display='none';return;}
  const field=DPF[td.cellIndex-FIXED]; if(!field){tip.style.display='none';return;}
  const code=parseInt(td.dataset.c||'0',16)||0;
  let status;
  if(td.classList.contains('dim')) status={cls:'idle',text:'idle — default this cycle, not relied on'};
  else if(td.classList.contains('rel')) status={cls:'rel',text:'load-bearing default — relied on because '+esc(RELIEDJS[field]||'')};
  else status={cls:'set',text:'actively set this cycle'};
  showTip(td,tipHTML(field,code,status));
});
store.addEventListener('mouseleave',()=>{tip.style.display='none';});

// ---- column lenses ----
const lensStyle=document.getElementById('lensStyle');
document.querySelectorAll('.lensbtn').forEach(b=>b.addEventListener('click',()=>{
  document.querySelectorAll('.lensbtn').forEach(x=>x.classList.remove('on'));
  b.classList.add('on');
  lensStyle.textContent=LENSCSS[b.dataset.lens]||'';
  scheduleArrows();
}));

// ---- bus-staging-tax overlay ----
document.getElementById('stageBtn').addEventListener('click',function(){
  document.body.classList.toggle('stage'); this.classList.toggle('on');
});

// ---- inspector panel (click a row) ----
const insp=document.getElementById('insp');
let selRow=null;
function fieldDoc(field,code){const fi=FINFO[field];
  if(fi&&fi.vals){const v=fi.vals.find(x=>x[0]===code); return v?v[2]:'';} return '';}
function selectRow(tr){
  if(selRow) selRow.classList.remove('sel');
  selRow=tr; tr.classList.add('sel');
  const addr=+tr.id.slice(1);
  const seq=['c-op','c-next','c-cond','c-ulp'].map(c=>{const el=tr.querySelector('.'+c);
    return el?el.innerHTML:'';}).join(' ');
  let active='', idle=[];
  tr.querySelectorAll('td.dp').forEach(td=>{
    const field=DPF[td.cellIndex-FIXED]; if(!field) return;
    const code=parseInt(td.dataset.c||'0',16)||0;
    const name=(td.childNodes[0]?td.childNodes[0].nodeValue:'').trim();
    if(td.classList.contains('on')){
      const doc=fieldDoc(field,code);
      active+=`<div class="ix-f"><span class="ix-fn ${td.classList.contains('rel')?'ix-rel':'ix-set'}">${field}</span>`
        +`<span class="ix-fv">${name}<sub>${code.toString(16)}</sub></span>`
        +(doc?`<span class="ix-fd">${esc(doc)}</span>`:'')+`</div>`;
    } else idle.push(field+'='+name);
  });
  const xr=XREFS[addr]||[], XCAP=50;
  let xh=xr.slice(0,XCAP).map(([s,kind])=> s===null
    ? `<span class="ix-x ix-xo">${esc(kind)}</span>`
    : `<a class="ix-x" href="#" data-goto="${s}">${esc(kind)} ← 0x${s.toString(16)}</a>`).join(' ');
  if(xr.length>XCAP) xh+=` <span class="dim">+${xr.length-XCAP} more</span>`;
  if(!xh) xh='<span class="dim">nothing jumps here</span>';
  insp.innerHTML=
    `<div class="ix-top"><span class="ix-addr">0x${addr.toString(16).padStart(3,'0')}</span>`
    +`<span class="ix-rtn">${esc(tr.dataset.rtn||'')}</span>`
    +`<button class="ix-close" id="ixClose">✕ esc</button></div>`
    +`<div class="ix-src">${esc(tr.querySelector('.note').textContent)}</div>`
    +`<div class="ix-sec"><div class="ix-h">sequencer</div><div class="ix-seq">${seq}</div></div>`
    +`<div class="ix-sec"><div class="ix-h">referenced by (${xr.length})</div><div class="ix-xrefs">${xh}</div></div>`
    +`<div class="ix-sec"><div class="ix-h">datapath — driven this cycle</div>${active||'<span class="dim">none (pure sequencer step)</span>'}`
    +(idle.length?`<div class="ix-idle">idle: ${esc(idle.join('   '))}</div>`:'')+`</div>`;
  document.body.classList.add('insp');
  document.getElementById('ixClose').addEventListener('click',closeInsp);
  scheduleArrows();
}
function closeInsp(){document.body.classList.remove('insp');
  if(selRow) selRow.classList.remove('sel'); selRow=null; scheduleArrows();}
store.addEventListener('click',e=>{
  if(e.target.closest('[data-goto]')) return;
  const tr=e.target.closest('#store tbody tr'); if(tr) selectRow(tr);
});
addEventListener('keydown',e=>{if(e.key==='Escape')closeInsp();});

// ---- gutter jump arrows (intra-routine; redrawn from live row rects) ----
const gutter=document.getElementById('gutter'), GW=22;
let rafA=false;
function scheduleArrows(){if(rafA)return; rafA=true;
  requestAnimationFrame(()=>{rafA=false; drawArrows();});}
function midY(el){const b=el.getBoundingClientRect(); return b.top+b.height/2;}
function drawArrows(){
  const r=store.getBoundingClientRect();
  gutter.style.left=r.left+'px'; gutter.style.top=r.top+'px';
  gutter.style.width=GW+'px'; gutter.style.height=r.height+'px';
  gutter.setAttribute('viewBox',`0 0 ${GW} ${r.height}`);
  const headH=store.querySelector('thead').getBoundingClientRect().height;
  const minY=headH+1, maxY=r.height-1, top=r.top;
  const selA=selRow?+selRow.id.slice(1):-1;
  let p='';
  for(const [s,t,lane] of ARROWS){
    const se=document.getElementById('a'+s), te=document.getElementById('a'+t);
    if(!se||!te||se.offsetParent===null||te.offsetParent===null) continue;
    const sy=midY(se)-top, ty=midY(te)-top;
    if((sy<minY&&ty<minY)||(sy>maxY&&ty>maxY)) continue;
    const csy=Math.max(minY,Math.min(maxY,sy)), cty=Math.max(minY,Math.min(maxY,ty));
    const x=GW-3-lane*4, hot=(s===selA||t===selA), col=hot?'#58a6ff':'#5b6675';
    if(s===t){                                  // 1-word self-loop — small back-curl
      p+=`<path d="M ${GW-1} ${csy-4} C ${x-3} ${csy-7}, ${x-3} ${csy+7}, ${GW-1} ${csy+4}" `
        +`fill="none" stroke="${col}" stroke-width="${hot?1.6:1}"/>`;
      p+=`<path d="M ${GW-1} ${csy+4} l -5 -2 l 1 5 z" fill="${col}"/>`;
      continue;
    }
    p+=`<path d="M ${GW-1} ${csy} H ${x} V ${cty} H ${GW-6}" fill="none" stroke="${col}" stroke-width="${hot?1.6:1}"/>`;
    p+=`<path d="M ${GW-1} ${cty} l -5 -3 v6 z" fill="${col}"/>`;
    p+=`<circle cx="${GW-1}" cy="${csy}" r="1.5" fill="${col}"/>`;
  }
  gutter.innerHTML=p;
}
store.addEventListener('scroll',scheduleArrows,{passive:true});
addEventListener('resize',scheduleArrows);
q.addEventListener('input',scheduleArrows);
drawArrows();
"""


def build(m: Model) -> str:
    legend = "".join(
        f'<span style="background:{c}">{op}</span>' for op, c in SEQ_COLOR.items())
    # per-field info for the JS tooltip: bits, encoding, role, and the full value
    # set (so the tooltip can list every alternative with the current one marked).
    def fi(f):
        fd = m.by_name[f]
        msb = fd["lsb"] + fd["width"] - 1
        vd = VALUE_DOC.get(f, {})
        d = {"bits": f"{msb}:{fd['lsb']}", "enc": fd.get("enc", ""), "role": fd.get("role", "")}
        if fd.get("enc") == "mask":
            d["mask"] = sorted([p, n[3:], vd.get(n[3:], "")] for n, p in fd["bits_"].items())
        else:
            if fd.get("values"):
                d["vals"] = sorted([c, n, vd.get(n, "")] for n, c in fd["values"].items())
            d["def"] = m.fields.code_of(f, fd["default"]) if "default" in fd else 0
        return d
    finfo = {f: fi(f) for f in DP_FIELDS}
    # per-lens CSS that hides the datapath columns the lens drops
    def lens_css(groups):
        hidden = [f for f in DP_FIELDS if LENS_GROUP[f] not in groups]
        return (",".join(f".c-{f}" for f in hidden) + "{display:none}") if hidden else ""
    lenscss = {name: lens_css(groups) for name, groups in LENSES.items()}
    data_js = ("const DPF=" + json.dumps(DP_FIELDS) + ";"
               "const FINFO=" + json.dumps(finfo) + ";"
               "const RELIEDJS=" + json.dumps({k: v[1] for k, v in RELIED.items()}) + ";"
               "const ARROWS=" + json.dumps(m.arrows) + ";"
               "const XREFS=" + json.dumps({t: v for t, v in m.xrefs.items()}) + ";"
               "const LENSCSS=" + json.dumps(lenscss) + ";\n")
    lensbtns = "".join(
        f'<button class="lensbtn{" on" if name == "all" else ""}" data-lens="{name}">'
        f'{name}</button>' for name in LENSES)
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>BLIP microcode browser</title><style>{CSS}</style><style id="lensStyle"></style></head><body>
<div id="bar"><b>BLIP microcode</b>
  <span class="dim">{len(m.words)} words &middot; {len(m.entries)} opcodes</span>
  <input id="q" placeholder="filter: opcode / routine / seq op / source…">
  <span class="lenses">cols: {lensbtns}</span>
  <button id="stageBtn" class="tglbtn" title="highlight bus-staging-tax words — a value moved into SCR1/SCR2 only so the next word can use it on the RIGHT bus (the asymmetric-bus tax)">⟂ staging ({len(m.staging)})</button>
  <span class="cellleg">cell: <i class="cl-on">load-bearing</i> <i class="cl-idle">idle</i></span>
  <div class="leg">{legend}</div>
</div>
<div id="wrap">
  <div id="lut"><table>{render_lut(m)}</table></div>
  <div id="store"><table class="mc">
    <thead>{render_header(m)}</thead>
    <tbody>{render_rows(m)}</tbody>
  </table></div>
</div>
<div id="insp" class="hidden"></div>
<div id="tip"></div>
<svg id="gutter" xmlns="http://www.w3.org/2000/svg"></svg>
<script>{data_js}{JS}</script>
</body></html>"""


def main() -> int:
    m = Model()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(m))
    kb = OUT.stat().st_size // 1024
    print(f"wrote {OUT}  ({len(m.words)} words, {len(m.entries)} opcodes, {kb} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
