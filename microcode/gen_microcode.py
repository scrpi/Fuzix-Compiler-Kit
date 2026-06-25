#!/usr/bin/env python3
"""Generate microcode/src/blip.uc — the full BLIP microcode source.

Hand-designed register-transfer templates (per addressing mode and per
operation class) expanded over every opcode in isa/opcodes.toml, the single
source of truth for the instruction set. Output is the .uc register-transfer
notation of docs/microcode-source.md; one statement = one microword = one cycle.

The generator errors on any opcode it cannot classify, so coverage of all 462
opcodes is guaranteed (nothing is silently skipped).
"""
from __future__ import annotations
import re, tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]          # microcode/ -> repo root
OPS = tomllib.load(open(REPO / 'isa/opcodes.toml', 'rb'))['op']


class Unhandled(Exception):
    pass


# ---------------------------------------------------------------------------
# operand / addressing-mode parsing
# ---------------------------------------------------------------------------
def parse_mem(operand):
    """('mode', base) for a parenthesised memory operand, else None."""
    if operand is None:
        return None
    m = re.fullmatch(r'\((.*)\)', operand)
    if not m:
        return None
    inner = m.group(1)
    if inner == '$nnnn':
        return ('abs', None)
    if inner.startswith('--'):
        return ('predec2', inner[2:])
    if inner.startswith('-'):
        return ('predec1', inner[1:])
    mm = re.fullmatch(r'(X|Y|SP|PC)(\+\+|\+[ABD]|\+n8|\+n16|\+|)', inner)
    if not mm:
        raise Unhandled(f"mem operand {operand!r}")
    base, suf = mm.group(1), mm.group(2)
    mode = {'': 'zero', '+': 'postinc1', '++': 'postinc2',
            '+n8': 'off8', '+n16': 'off16',
            '+A': 'accA', '+B': 'accB', '+D': 'accD'}[suf]
    return (mode, base)


def split_mnem(mnem):
    parts = mnem.split(None, 1)
    verb = parts[0]
    rest = parts[1] if len(parts) > 1 else ''
    if ',' in rest:
        tgt, operand = rest.split(',', 1)
        return verb, tgt.strip(), operand.strip()
    return verb, rest.strip() or None, None


# ---------------------------------------------------------------------------
# EA computation -> leaves the effective address in MAR.
# Returns (lines, concurrent, post):
#   lines      : microwords that compute the EA into MAR
#   concurrent : a clause to ride along on the (first) access word, or ''
#   post       : (modreg, line) emitted after the access (auto-inc by 2), or None
# `base` token is X/Y/SP/PC (SP -> active SP).
# ---------------------------------------------------------------------------
def ea(mode, base):
    if mode == 'zero':
        return ([f"MAR  <- {base}"], '', None)
    if mode == 'postinc1':                         # (R+) byte post-inc by 1
        return ([f"MAR  <- {base}"], f"{base}++", None)
    if mode == 'postinc2':                         # (R++) 16-bit post-inc by 2
        return ([f"MAR  <- {base}"], '', (base, f"{base} <- MAR"))
    if mode == 'predec1':                          # (-R) pre-dec by 1
        return ([f"MAR  <- {base} - 1 ; {base} <- {base} - 1"], '', None)
    if mode == 'predec2':                          # (--R) pre-dec by 2
        return ([f"MAR  <- {base} - 2 ; {base} <- {base} - 2"], '', None)
    if mode == 'off8':
        return ([f"MDR  <- [PC]; PC++",
                 f"SCR1 <- sext(MDR)",
                 f"MAR  <- {base} + SCR1"], '', None)
    if mode == 'off16':
        return ([f"SCR1.low  <- [PC]; PC++",
                 f"SCR1.high <- [PC]; PC++",
                 f"MAR  <- {base} + SCR1"], '', None)
    if mode == 'abs':
        return ([f"SCR1.low  <- [PC]; PC++",
                 f"SCR1.high <- [PC]; PC++",
                 f"MAR  <- SCR1"], '', None)
    if mode == 'accA':
        return ([f"SCR1 <- sext(A)", f"MAR  <- {base} + SCR1"], '', None)
    if mode == 'accB':
        return ([f"SCR1 <- sext(B)", f"MAR  <- {base} + SCR1"], '', None)
    if mode == 'accD':
        return ([f"SCR1 <- D", f"MAR  <- {base} + SCR1"], '', None)
    raise Unhandled(f"ea mode {mode}")


# flag clauses per operation class -----------------------------------------
F_LDST = "nz, v=0"
F_ADD8 = "nzvch"
F_SUB8 = "nzvc"
F_LOGIC = "nz, v=0"
F_ADD16 = "nzvc"
F_INCDEC = "nzv"
F_SHIFT = "nzvc"

WIDE = {'D', 'X', 'Y', 'SP'}

BYTE_ALU = {                       # verb -> (alu symbol, flags, writes_dest)
    'ADD': ('+', F_ADD8, True), 'ADC': ('+c', F_ADD8, True),
    'SUB': ('-', F_SUB8, True), 'SBC': ('-c', F_SUB8, True),
    'AND': ('&', F_LOGIC, True), 'OR': ('|', F_LOGIC, True),
    'EOR': ('^', F_LOGIC, True), 'CMP': ('-', F_SUB8, False),
    'BIT': ('&', F_LOGIC, False),
}
WIDE_ALU = {
    'ADD': ('+', F_ADD16, True), 'ADC': ('+c', F_ADD16, True),
    'SUB': ('-', F_ADD16, True), 'SBC': ('-c', F_ADD16, True),
    'CMP': ('-', F_ADD16, False),
}


# ---------------------------------------------------------------------------
# read / write a wide (16-bit) value at MAR
# ---------------------------------------------------------------------------
def read16_to_scr(conc=''):
    c = f" ; {conc}" if conc else ""
    return [f"SCR1.low  <- [MAR]; MAR++{c}",
            f"SCR1.high <- [MAR]; MAR++"]


def load16_reg(tgt, conc=''):
    if tgt == 'D':
        c = f" ; {conc}" if conc else ""
        return [f"D.low  <- [MAR]; MAR++{c} : z",
                f"D.high <- [MAR]; MAR++ : nz, v=0, z+"]
    return read16_to_scr(conc) + [f"{tgt} <- SCR1 : nz, v=0"]


def store16_reg(tgt, conc=''):
    c = f" ; {conc}" if conc else ""
    return [f"[MAR] <- low({tgt}); MAR++{c} : z",
            f"[MAR] <- high({tgt}); MAR++ : nz, v=0, z+"]


# ---------------------------------------------------------------------------
# data movement & ALU with target,operand
# ---------------------------------------------------------------------------
def build_load_byte(tgt, operand, mem):
    if operand and operand.startswith('$'):
        return [f"{tgt} <- [PC]; PC++ : {F_LDST}"]
    mode, base = mem
    lines, conc, post = ea(mode, base)
    c = f" ; {conc} " if conc else " "
    lines.append(f"{tgt}  <- [MAR]{c}: {F_LDST}")
    if post:
        lines.append(post[1])
    return lines


def build_store_byte(tgt, operand, mem):
    mode, base = mem
    lines, conc, post = ea(mode, base)
    c = f" ; {conc} " if conc else " "
    lines.append(f"[MAR] <- {tgt}{c}: {F_LDST}")
    if post:
        lines.append(post[1])
    return lines


def build_load_wide(tgt, operand, mem):
    if operand and operand.startswith('$'):
        if tgt == 'D':
            return ["D.low  <- [PC]; PC++ : z",
                    "D.high <- [PC]; PC++ : nz, v=0, z+"]
        return ["SCR1.low  <- [PC]; PC++",
                "SCR1.high <- [PC]; PC++",
                f"{tgt} <- SCR1 : nz, v=0"]
    mode, base = mem
    lines, conc, post = ea(mode, base)
    lines += load16_reg(tgt, conc)
    if post and post[0] != tgt:        # self-load (LD X,(X++)) keeps the loaded value
        lines.append(post[1])
    return lines


def build_store_wide(tgt, operand, mem):
    mode, base = mem
    lines, conc, post = ea(mode, base)
    lines += store16_reg(tgt, conc)
    if post:
        lines.append(post[1])
    return lines


def build_alu_byte(verb, tgt, operand, mem):
    sym, flags, writes = BYTE_ALU[verb]
    dst = tgt if writes else '_'
    if operand and operand.startswith('$'):
        return ["SCR1 <- [PC]; PC++",
                f"{dst} <- {tgt} {sym} SCR1 : {flags}"]
    mode, base = mem
    lines, conc, post = ea(mode, base)
    c = f" ; {conc}" if conc else ""
    lines.append(f"SCR1 <- [MAR]{c}")
    lines.append(f"{dst} <- {tgt} {sym} SCR1 : {flags}")
    if post:
        lines.append(post[1])
    return lines


def build_alu_wide(verb, tgt, operand, mem):
    sym, flags, writes = WIDE_ALU[verb]
    dst = tgt if writes else '_'
    if operand and operand.startswith('$'):
        return ["SCR1.low  <- [PC]; PC++",
                "SCR1.high <- [PC]; PC++",
                f"{dst} <- {tgt} {sym} SCR1 : {flags}"]
    mode, base = mem
    lines, conc, post = ea(mode, base)
    lines += read16_to_scr(conc)
    lines.append(f"{dst} <- {tgt} {sym} SCR1 : {flags}")
    if post:
        lines.append(post[1])
    return lines


# unary register-direct -----------------------------------------------------
UNARY_REG = {
    'INC': lambda r: [f"{r} <- {r} + 1 : {F_INCDEC}"],
    'DEC': lambda r: [f"{r} <- {r} - 1 : {F_INCDEC}"],
    'CLR': lambda r: [f"{r} <- 0 : nz, v=0, c=0"],
    'TST': lambda r: [f"_ <- {r} : nz, v=0"],
    'NEG': lambda r: [f"{r} <- -{r} : nzvc"],
    'COM': lambda r: [f"{r} <- ~{r} : nz, v=0, c=1"],
    'ASL': lambda r: [f"{r} <- asl({r}) : {F_SHIFT}"],
    'ASR': lambda r: [f"{r} <- asr({r}) : {F_SHIFT}"],
    'LSR': lambda r: [f"{r} <- lsr({r}) : {F_SHIFT}"],
    'ROL': lambda r: [f"{r} <- rol({r}) : {F_SHIFT}"],
    'ROR': lambda r: [f"{r} <- ror({r}) : {F_SHIFT}"],
}


def build_unary_mem(verb, mem):
    mode, base = mem
    lines, conc, post = ea(mode, base)
    c = f" ; {conc}" if conc else ""
    if verb == 'CLR':
        lines.append("SCR1 <- 0")
        lines.append(f"[MAR] <- SCR1{c} : nz, v=0, c=0")
    elif verb == 'TST':
        lines.append(f"_ <- [MAR]{c} : nz, v=0")
    elif verb in ('INC', 'DEC'):
        op = '+ 1' if verb == 'INC' else '- 1'
        lines.append(f"SCR1 <- [MAR]{c}")
        lines.append(f"SCR1 <- SCR1 {op} : {F_INCDEC}")
        lines.append("[MAR] <- SCR1")
    else:
        raise Unhandled(f"unary mem {verb}")
    if post:
        lines.append(post[1])
    return lines


# 16-bit shift-by-count on D ------------------------------------------------
def build_dshift(verb):
    op = {'ASL': 'asl', 'LSR': 'lsr', 'ASR': 'asr'}[verb]
    lbl = f"{op}d_loop"
    return [
        "SCR1 <- [PC]; PC++                # shift count n",
        "count -> uloop                    # uloop <- n  (n in 0..16; n>16 wraps, undefined per C)",
        f"{lbl}:",
        f"D <- {op}(D) : nzvc ; uloop-- ; if not uloop.zero goto {lbl}",
        "return to fetch",
    ]


# branches ------------------------------------------------------------------
BCC_COND = {
    'BRA': 'always', 'BRN': 'never',
    'BHI': 'not c|z', 'BLS': 'c|z', 'BCC': 'not c', 'BCS': 'c',
    'BNE': 'not z', 'BEQ': 'z', 'BVC': 'not v', 'BVS': 'v',
    'BPL': 'not n', 'BMI': 'n', 'BGE': 'not n^v', 'BLT': 'n^v',
    'BGT': 'not z|(n^v)', 'BLE': 'z|(n^v)',
}


def build_branch(verb, wide):
    base = verb[1:] if wide else verb            # LBEQ -> BEQ
    cond = BCC_COND[base]
    if not wide:
        fetch = ["MDR  <- [PC]; PC++                # rel8 displacement",
                 "SCR1 <- sext(MDR)"]
    else:
        fetch = ["SCR1.low  <- [PC]; PC++            # rel16 displacement low",
                 "SCR1.high <- [PC]; PC++"]
    if cond == 'always':
        return fetch + ["PC <- PC + SCR1 ; return to fetch"]
    if cond == 'never':
        return fetch[:1] + ["return to fetch"]     # consume the displacement, no branch
    last = fetch[-1]
    return fetch[:-1] + [f"{last} ; if {cond} goto BR_TAKEN",
                         "return to fetch"]


# JMP / JSR -----------------------------------------------------------------
PUSH_PC = [
    "SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot",
    "[MAR] <- low(PC); MAR++           # push return PC low",
    "[MAR] <- high(PC)                 # push return PC high",
]


def jump_target_to_scr(arg, mem):
    """Leave the target address in SCR1.  bare reg/imm => the operand IS the
       target; (mem) => jump THROUGH memory (load the pointer there)."""
    if arg in ('X', 'Y'):
        return [f"SCR1 <- {arg}"]
    if arg and arg.startswith('$') and mem is None:        # JMP $nnnn absolute target
        return ["SCR1.low  <- [PC]; PC++", "SCR1.high <- [PC]; PC++"]
    mode, base = mem                                       # through memory
    lines, conc, post = ea(mode, base)
    return lines + read16_to_scr(conc)


def build_jmp(arg, mem):
    if arg in ('X', 'Y'):
        return [f"PC <- {arg} ; return to fetch"]
    return jump_target_to_scr(arg, mem) + ["PC <- SCR1 ; return to fetch"]


def build_jsr(arg, mem):
    if arg in ('X', 'Y'):
        return PUSH_PC + [f"PC <- {arg} ; return to fetch"]
    return jump_target_to_scr(arg, mem) + PUSH_PC + ["PC <- SCR1 ; return to fetch"]


# LEA -----------------------------------------------------------------------
def build_lea(tgt, operand):
    flags = "" if tgt == 'SP' else " : z"
    if operand.startswith('--'):
        return [f"{tgt} <- {operand[2:]} - 2{flags}"]
    if operand.startswith('-'):
        return [f"{tgt} <- {operand[1:]} - 1{flags}"]
    m = re.fullmatch(r'(X|Y|SP|PC)(\+\+|\+[ABD]|\+n8|\+n16|\+|)', operand)
    base, suf = m.group(1), m.group(2)
    if suf == '':
        return [f"{tgt} <- {base}{flags}"]
    if suf == '+':
        return [f"{tgt} <- {base} + 1{flags}"]
    if suf == '++':
        return [f"{tgt} <- {base} + 2{flags}"]
    if suf == '+n8':
        return ["MDR  <- [PC]; PC++                # 8-bit displacement",
                "SCR1 <- sext(MDR)", f"{tgt} <- {base} + SCR1{flags}"]
    if suf == '+n16':
        return ["SCR1.low  <- [PC]; PC++            # 16-bit displacement",
                "SCR1.high <- [PC]; PC++", f"{tgt} <- {base} + SCR1{flags}"]
    if suf == '+A':
        return ["SCR1 <- sext(A)", f"{tgt} <- {base} + SCR1{flags}"]
    if suf == '+B':
        return ["SCR1 <- sext(B)", f"{tgt} <- {base} + SCR1{flags}"]
    if suf == '+D':
        return ["SCR1 <- D", f"{tgt} <- {base} + SCR1{flags}"]
    raise Unhandled(f"lea {operand}")


# TAS -----------------------------------------------------------------------
def build_tas(arg, mem):
    mode, base = mem
    lines, conc, post = ea(mode, base)
    return lines + [
        "SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus",
        "SCR2 <- 0",
        "SCR2 <- ~SCR2                     # the set value (all-ones)",
        "[MAR] <- SCR2 ; unlock            # set: store, release the bus lock",
    ]


# register-register & USP-banking moves -------------------------------------
def build_reg_move(verb):
    if verb == 'LD':
        return [
            "SCR2 <- [PC]; PC++                # src|dst register-select byte",
            "# the selector nibbles drive the register-file read/write ports",
            "# (a datapath mux fed by SCR2, not a control-word field):",
            "reg[dst] <- reg[src] ; return to fetch",
        ]
    return [
        "SCR2 <- [PC]; PC++                # the two register-select nibbles",
        "SCR1 <- reg[dst]                  # selector-driven (see LD reg,reg)",
        "reg[dst] <- reg[src]",
        "reg[src] <- SCR1 ; return to fetch",
    ]


def build_usp_move(verb, tgt, operand):
    if verb == 'LD':
        return [f"{tgt} <- {operand} ; return to fetch"]
    return [f"SCR1 <- {tgt}", f"{tgt} <- {operand}",
            f"{operand} <- SCR1 ; return to fetch"]


# PSHS / PULS ---------------------------------------------------------------
# mask bits (isa.md §8.4): 0 CC,1 A,2 B,3 reserved,4 X,5 Y,6 SP(banked image),7 PC.
# push high-address-first -> push PC(bit7) down to CC(bit0); pull is the reverse.
def build_pshs():
    out = ["SCR2 <- [PC]; PC++                # push mask"]
    order = [('PC', 2), ('SP', 2), ('Y', 2), ('X', 2),
             (None, 0), ('B', 1), ('A', 1), ('CC', 1)]
    for i, (reg, w) in enumerate(order):
        out.append("SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C")
        if reg is None:
            continue
        lbl = f"pshs_skip{i}"
        out.append(f"if not c goto {lbl}             # {reg} not in mask")
        if w == 2:
            out += [f"SP <- SP - 2 ; MAR <- SP - 2",
                    f"[MAR] <- low({reg}); MAR++",
                    f"[MAR] <- high({reg})"]
        else:
            out += [f"SP <- SP - 1 ; MAR <- SP - 1",
                    f"[MAR] <- {reg}"]
        out.append(f"{lbl}:")
    out.append("return to fetch")
    return out


def build_puls():
    out = ["SCR2 <- [PC]; PC++                # pull mask",
           "MAR <- SP                          # walk the frame upward from SP"]
    order = [('CC', 1), ('A', 1), ('B', 1), (None, 0),
             ('X', 2), ('Y', 2), ('SP', 2), ('PC', 2)]
    for i, (reg, w) in enumerate(order):
        out.append("SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C")
        if reg is None:
            continue
        lbl = f"puls_skip{i}"
        out.append(f"if not c goto {lbl}             # {reg} not in mask")
        if reg == 'CC':
            # CC pull drives the CC write controls: cc(whole) loads H/N/Z/V/C from the stack
            # byte, and (privilege-gated) M/I too — held in user mode (isa.md §8.7).
            out += ["CC <- [MAR]; MAR++ ; cc(whole)    # restore CC (M/I priv-gated)"]
        elif reg == 'PC':
            out += ["SCR1.low  <- [MAR]; MAR++",
                    "SCR1.high <- [MAR]; MAR++",
                    "SP <- MAR                          # commit SP (LEFT = MAR)",
                    "PC <- SCR1 ; return to fetch       # then set PC (LEFT = SCR1)"]
        elif w == 2:
            out += ["SCR1.low  <- [MAR]; MAR++",
                    "SCR1.high <- [MAR]; MAR++",
                    f"{reg} <- SCR1"]
        else:
            out += [f"{reg} <- [MAR]; MAR++"]
        out.append(f"{lbl}:")
    out.append("SP <- MAR ; return to fetch        # commit the advanced SP")
    return out


# fully hand-written irregular routines -------------------------------------
HAND = {
 'NOP': ["return to fetch"],
 'RTS': [
    "MAR  <- SP                         # frame top = return-addr low byte",
    "SCR1.low  <- [MAR]; MAR++          # pull return addr low",
    "SCR1.high <- [MAR]; MAR++          # pull return addr high",
    "SP   <- MAR                        # SP += 2",
    "PC   <- SCR1 ; return to fetch     # resume at the caller",
 ],
 'ABX': [
    "SCR1 <- low(D)                     # zero-extend B (D low byte)",
    "X <- X + SCR1 ; return to fetch    # X += B  (unsigned)",
 ],
 'SEX': ["D <- sext(B) : nz, v=0 ; return to fetch    # sign-extend B into A:B"],
 'SEI': ["mi(set_i) ; return to fetch       # privileged: set the IRQ mask"],
 'CLI': ["mi(clr_i) ; return to fetch       # privileged: clear the IRQ mask"],
 'SYNC': [
    "sync_wait:",
    "if not irq goto sync_wait          # privileged: spin until an interrupt is pending",
    "return to fetch",
 ],
 'HALT': [
    "halt_spin:",
    "goto halt_spin                     # privileged: stop until RESET",
 ],
 'RTI': [
    "MAR <- SP                                       # supervisor frame: CC on top",
    "CC  <- [MAR]; MAR++ ; cc(whole)                 # restore CC (incl. M, I — supervisor, so priv-gated load takes)",
    "SCR1.low  <- [MAR]; MAR++                       # pull PC low",
    "SCR1.high <- [MAR]; MAR++                       # pull PC high",
    "SP  <- MAR                                      # SP += 3",
    "PC  <- SCR1 ; return to fetch                   # resume interrupted context",
 ],
 'MUL': [
    "# unsigned 8x8 -> 16: A*B -> D.  shift-add over the uloop counter.",
    "SCR1 <- high(D)                    # multiplicand A (zero-extended to 16)",
    "SCR2 <- low(D)                     # multiplier   B",
    "D <- 0                             # clear the running product",
    "8 -> uloop",
    "mul_loop:",
    "SCR2 <- lsr(SCR2) : c              # next multiplier bit -> C",
    "if not c goto mul_noadd",
    "D <- D + SCR1                      # add the (shifted) multiplicand",
    "mul_noadd:",
    "SCR1 <- asl(SCR1)                  # multiplicand <<= 1",
    "uloop-- ; if not uloop.zero goto mul_loop",
    "_ <- D : z                         # Z from the 16-bit product  (REVIEW: MUL also sets C)",
    "return to fetch",
 ],
 'DAA': [
    "# decimal-adjust A after a BCD add.  REVIEW: full conditional +$06/+$60",
    "# correction on the H flag and the two nibble ranges needs simulation.",
    "SCR1 <- A",
    "A <- A + SCR1 : nzvc ; return to fetch",
 ],
}


def build(op):
    mnem = op['mnem']
    verb, tgt, operand = split_mnem(mnem)
    mem = parse_mem(operand)

    if mnem in HAND:
        return HAND[mnem]

    if mnem == 'LD reg,reg':
        return build_reg_move('LD')
    if mnem == 'XCHG reg,reg':
        return build_reg_move('XCHG')
    if verb in ('LD', 'XCHG') and (tgt == 'USP' or operand == 'USP'):
        return build_usp_move(verb, tgt, operand)

    if verb in BCC_COND:
        return build_branch(verb, wide=False)
    if verb.startswith('LB') and verb[1:] in BCC_COND:
        return build_branch(verb, wide=True)
    if verb == 'BSR':
        return ["MDR  <- [PC]; PC++                # rel8; PC -> return address",
                "SCR1 <- sext(MDR)", *PUSH_PC,
                "PC <- PC + SCR1 ; return to fetch # take the call"]
    if verb == 'LBSR':
        return ["SCR1.low  <- [PC]; PC++           # rel16; PC -> return address",
                "SCR1.high <- [PC]; PC++", *PUSH_PC,
                "PC <- PC + SCR1 ; return to fetch # take the call"]

    if verb == 'JMP':
        return build_jmp(tgt, parse_mem(tgt))
    if verb == 'JSR':
        return build_jsr(tgt, parse_mem(tgt))
    if verb == 'LEA':
        return tail(build_lea(tgt, operand))
    if verb == 'TAS':
        return tail(build_tas(tgt, parse_mem(tgt)))
    if verb == 'PSHS':
        return build_pshs()
    if verb == 'PULS':
        return build_puls()

    # ANDCC/ORCC/CWAI stage the immediate mask on Z; the CC register itself ANDs/ORs it with CC
    # (cc(and)/cc(or)) across all bits, so M/I are masked too in supervisor and held in user
    # (isa.md §8.7) — no CC-on-LEFT read needed.
    if verb == 'ANDCC':
        return ["SCR1 <- [PC]; PC++                # AND-mask",
                "_ <- SCR1 ; cc(and) ; return to fetch    # CC <- CC & mask (M/I priv-gated)"]
    if verb == 'ORCC':
        return ["SCR1 <- [PC]; PC++                # OR-mask",
                "_ <- SCR1 ; cc(or) ; return to fetch     # CC <- CC | mask (M/I priv-gated)"]
    if verb == 'CWAI':
        return ["SCR1 <- [PC]; PC++                # AND-mask",
                "_ <- SCR1 ; cc(and)              # CC <- CC & mask (M/I priv-gated)",
                "cwai_wait:",
                "if not irq goto cwai_wait         # wait for an interrupt (REVIEW: CWAI should pre-stack the full register frame for a fast interruptible entry)",
                "return to fetch"]
    if verb == 'LDMMU':
        return ["SCR1 <- [PC]; PC++                # page-table slot selector",
                "MMU_ENTRY <- D ; pt(write) ; map(imm8) ; return to fetch   # REVIEW: entry source/format"]
    if verb == 'STMMU':
        return ["SCR1 <- [PC]; PC++                # page-table slot selector",
                "D <- MMU_ENTRY ; pt(read) ; map(imm8) ; return to fetch    # REVIEW: entry dest/format"]

    if verb in ('SWI', 'SWI2', 'SWI3'):
        return [
            "SSP <- SSP - 2 ; MAR <- SSP - 2 ; map(kernel)   # reserve 2 bytes for PC on the supervisor stack",
            "[MAR] <- low(PC); MAR++ ; map(kernel)           # push return PC low",
            "[MAR] <- high(PC) ; map(kernel)                 # push return PC high",
            "SSP <- SSP - 1 ; MAR <- SSP - 1 ; map(kernel)   # reserve 1 byte for CC (top of frame)",
            "[MAR] <- CC ; map(kernel)                       # push interrupted CC",
            "mi(enter)                                       # enter supervisor mode, set I",
            f"MAR <- vector({verb}) ; map(kernel)             # hardwired {verb} vector slot",
            "SCR1.low  <- [MAR]; MAR++ ; map(kernel)         # handler address low",
            "SCR1.high <- [MAR] ; map(kernel)                # handler address high",
            "PC <- SCR1 ; return to fetch                    # enter the handler",
        ]

    if verb in ('ASL', 'LSR', 'ASR') and tgt == 'D':
        return build_dshift(verb)

    if verb in UNARY_REG and operand is None:
        if tgt in ('A', 'B'):
            return tail(UNARY_REG[verb](tgt))
        m2 = parse_mem(tgt)
        if m2:
            return tail(build_unary_mem(verb, m2))
        raise Unhandled(mnem)

    if verb == 'LD':
        return tail(build_load_wide(tgt, operand, mem) if tgt in WIDE
                    else build_load_byte(tgt, operand, mem))
    if verb == 'ST':
        return tail(build_store_wide(tgt, operand, mem) if tgt in WIDE
                    else build_store_byte(tgt, operand, mem))
    if verb in BYTE_ALU and tgt in ('A', 'B'):
        return tail(build_alu_byte(verb, tgt, operand, mem))
    if verb in WIDE_ALU and tgt in WIDE:
        return tail(build_alu_wide(verb, tgt, operand, mem))

    raise Unhandled(mnem)


ENDERS = ('return to fetch', 'dispatch', 'goto ', 'return')


def tail(lines):
    """Fold `; return to fetch` into the last datapath word (saves a cycle),
       respecting any trailing # comment; append a standalone word only if the
       last line cannot carry it."""
    if not lines:
        return ["return to fetch"]
    last = lines[-1]
    code, _, comment = last.partition('#')
    if any(e in code for e in ENDERS):
        return lines
    code = code.rstrip()
    newlast = f"{code} ; return to fetch"
    if comment:
        newlast += "   #" + comment
    return lines[:-1] + [newlast]


# ---------------------------------------------------------------------------
# emit the full blip.uc
# ---------------------------------------------------------------------------
HEADER = '''\
# ===========================================================================
# BLIP microcode source — the complete instruction set (all 462 opcodes).
#
# Register-transfer notation of docs/microcode-source.md; assembled by
# tools/uasm/uasm.py against microcode/control_word.toml.  EACH STATEMENT IS
# ONE MICROWORD = ONE CYCLE (strict 1:1, P2) — so counting the lines of a
# routine counts its cycles.
#
# This file is GENERATED from isa/opcodes.toml (the single source of truth for
# the instruction set) by microcode/gen_microcode.py, the same way isa.md's
# opcode table is generated.  The per-mode and per-operation cycle sequences are
# hand-designed in that generator; the expansion over every opcode and the
# opcode->routine bindings are mechanical, so coverage is complete and uniform.
#
# Notation used here (docs/microcode-source.md §14 left some glyphs open; these
# are the choices this source commits to):
#   <-            register transfer            : nz, v=0   flag write clause
#   [PC] / [MAR]  memory read at PC / MAR       [MAR] <-   memory write (LEFT drives data)
#   R++           off-bus +1 counter tick       R - 1      ALU add of a -2..+2 const-gen value
#   low(r)/high(r)/sext(r)   lane steer         a +c b / a -c b   ADC / SBC (carry-in = CC.C)
#   _ <- expr     compute for flags only (Z_DEST = none — CMP/BIT/TST)
#   R <- 0        load a const-gen value via PASS_R (CLR / clears)
#   goto L / if <cond> goto L / call R / return / return to fetch / dispatch [page1]
#   count -> uloop ; uloop-- ; if not uloop.zero goto L      the dedicated loop counter
#   cc(whole|and|or) / mi(enter|set_i|clr_i) / map(kernel|user|imm8) / pt(read|write)
#   lock / unlock   hold the bus across an RMW (TAS_LOCK)
#   vector(NAME)    the hardwired trap-vector slot address (materialized by the trap logic)
#   reg[src]/reg[dst]   the register-move selector nibbles drive the register-file ports
#
# Conditions (§9): z c n v, c|z, n^v, z|(n^v), true, and the microconditions
# uloop irq nmi …; prefix `not` inverts.  Every routine ends by RETURN-to-FETCH
# (trap-intercepted instruction boundary), DISPATCH, or a JUMP — never by
# falling into the next routine.
#
# A handful of genuinely under-specified routines carry a `REVIEW:` note (MUL
# flags, DAA correction, LDMMU/STMMU entry format, CWAI framing, the selector-
# driven register moves): the datapath capability they assume is called out so
# simulation can settle it.
# ===========================================================================
'''


def is_label(line):
    s = line.strip()
    return s.endswith(':') and '<-' not in s and ' ' not in s.rstrip(':')


def cycles(lines):
    n = 0
    for ln in lines:
        s = ln.strip()
        if not s or s.startswith('#') or is_label(s):
            continue
        n += 1
    return n


def fmt_routine(lines):
    out = []
    for ln in lines:
        s = ln.rstrip()
        out.append(f"{s}" if is_label(s) else f"  {s}")   # labels at column 0
    return out


def emit():
    L = [HEADER, ""]

    # --- FETCH (microaddress 0) --------------------------------------------
    L += [
        "# ---------------------------------------------------------------------------",
        "# FETCH — the fixed fetch entry (microaddress 0).  RESET and every routine's",
        "# `return to fetch` land here (a pending trap is vectored away by hardware).",
        "# ---------------------------------------------------------------------------",
        ".fetch FETCH",
        "routine FETCH:",
        "  IR <- [PC]; PC++; dispatch          # read opcode @PC -> IR, PC+1, dispatch via the LUT",
        "",
        "# 0x80 — the page-1 prefix: a one-step routine that re-fetches the real",
        "# opcode and re-dispatches on page 1 (isa.md §5.1).  page0[0x80] in the",
        "# opcode LUT points here (0x80 is reserved as the prefix, not an opcode).",
        ".opcode page0 0x80 PREFIX_P1",
        "routine PREFIX_P1:",
        "  IR <- [PC]; PC++; dispatch page1    # second opcode byte -> IR, dispatch on page 1",
        "",
        "# Shared tail for taken Bcc/LBcc: apply the sign-extended displacement.",
        "routine BR_TAKEN:",
        "  PC <- PC + SCR1 ; return to fetch",
        "",
    ]

    by_pb = sorted(OPS, key=lambda o: (o['page'], o['byte']))
    last_group = None
    for op in by_pb:
        grp = (op['page'], op.get('group', ''))
        if grp != last_group:
            page = op['page']
            L.append("# ===========================================================================")
            L.append(f"# PAGE {page} · {op.get('group','')}")
            L.append("# ===========================================================================")
            last_group = grp
        lines = build(op)
        nc = cycles(lines)
        priv = " · privileged" if op.get('priv') else ""
        review = " · REVIEW" if any('REVIEW' in ln for ln in lines) else ""
        note = f"# {op['byte']:#04x} {op['mnem']}   ({nc} cyc{priv}{review})"
        L.append(note)
        L.append(f".opcode page{op['page']} {op['byte']:#04x} {op['mnem']}")
        L.append(f"routine {op['mnem']}:")
        L += fmt_routine(lines)
        L.append("")

    return "\n".join(L) + "\n"


if __name__ == '__main__':
    # coverage self-check
    bad = []
    for op in OPS:
        try:
            assert build(op)
        except Unhandled as e:
            bad.append((op['mnem'], str(e)))
    if bad:
        print("UNHANDLED:")
        for m, e in bad:
            print(f"  {m:24s} {e}")
        raise SystemExit(1)
    text = emit()
    out = REPO / 'microcode/src/blip.uc'
    out.write_text(text)
    print(f"wrote {out}  ({len(text.splitlines())} lines, {len(OPS)} opcodes)")
