# BLIP — Microcode Source Language (register-transfer notation)

> **Tier-3 spec — PROPOSED, for review.** This defines the human-readable source
> language the microcode assembler ([toolchain.md](toolchain.md) §3) compiles into
> the 88-bit control word ([microcode.md](microcode.md) §3). It is **not yet
> ratified**: review this document, then it is locked in as decision **D-44** and
> [toolchain.md §3.2](toolchain.md) (which currently mandates a `field=value`
> notation) is updated to point here.
>
> Answers to **`R-BUILD-3`** (a microcode toolchain compiles the microcode from a
> human-readable source). Serves **G5/G6** (a legible machine you can read and
> single-step) and **R-CLK-1** (timing is a per-cycle property): the language is
> built so the source reads like register transfers *and* stays transparent about
> cycles. The bit-level field definition ([control_word.toml](../microcode/control_word.toml))
> remains the single source of truth underneath; this language is a front-end over it.

---

## 1. Principles

- **P1 — Register transfers, not field assignments.** A step is written as what it
  *does* — `MAR <- X + SCR1` — not as the control bits that achieve it
  (`LEFT_SRC=X RIGHT_SRC=SCR1 ALU_OP=ADD MAR_CTRL=load`). The assembler derives the
  fields from the datapath model already encoded in the field definition. The
  worked-routine comments in [microcode.md §5](microcode.md) are already in this form;
  this promotes the comment to *be* the source.
- **P2 — One statement is exactly one microword is exactly one cycle.** There is no
  hidden expansion: every source statement compiles to one 88-bit control word, so
  **counting lines counts cycles** (R-CLK-1, and the §5 cycle annotations stay
  meaningful). Reuse comes from named `CALL`/`RETURN` routines (D-42), never from
  invisible macro expansion.
- **P3 — The hardware's limits are the language's limits (honesty).** If a transfer
  cannot be done in one microword — e.g. an immediate on the RIGHT bus, or two LEFT
  sources — the assembler **rejects it** and you write the staging step explicitly.
  The language never silently inserts a cycle. This is what keeps P2 true and makes
  the bus-staging tax ([microcode.md §7.3](microcode.md)) visible where it is paid.
- **P4 — Generated from the field definition.** The operand and operator vocabularies
  below are bindings onto `control_word.toml` fields; adding a field value there makes
  it available here. The doc table and the assembler's binder derive from the one file
  (toolchain.md §3.1).

---

## 2. The one-microword model

A microword drives several independent "lanes" of the horizontal control word at once
([microcode.md §3](microcode.md)): an ALU/bus transfer, the four address counters, a
memory cycle, the flags, and one sequencer action. A source **statement** mirrors that
structure — a primary transfer plus optional concurrent clauses, all landing in the
**same** word:

```
[label:]  [ transfer ]  [ ; effect ]…  [ : flags ]  [ ; control ]   # comment
```

- **transfer** — the LEFT⊕RIGHT→ALU→Z→dest datapath path (or a memory access). May be
  omitted (a pure sequencer step, or a bare counter tick).
- **effect** — a concurrent secondary action the same word also performs: a counter
  tick (`PC++`), a second latch, a memory access.
- **flags** — which flags this word writes and from where.
- **control** — the sequencer action (default: fall through to the next line).

Clauses are order-free; `;` separates concurrent clauses, `:` introduces the flag
clause, `#` starts a comment. Every clause maps to a disjoint set of control-word
fields, so a legal line is exactly the set of fields one word can assert.

---

## 3. Lexical

- **Comments:** `#` to end of line.
- **Numbers:** `$1a2b` (hex, BLIP house style), `0x1a2b`, or decimal `42`.
- **Identifiers / labels:** `[A-Za-z_][A-Za-z0-9_]*`; a label is `name:` binding the
  next microword's address.
- **Registers and keywords** are case-insensitive; canonical form is upper-case for
  registers (`X`, `MDR`) and lower-case for verbs/conditions (`goto`, `if`, `not`).

---

## 4. Operand vocabulary  → datapath fields

Sources (right of `<-`) and destinations (left of `<-`) bind to `control_word.toml`:

| Source token                                    | Binds to                              | Notes                                    |
|-------------------------------------------------|---------------------------------------|------------------------------------------|
| `D` `X` `Y` `PC` `MAR` `SCR1` `SCR2` `MDR` `CC` | `LEFT_SRC`                            | full-16 on the LEFT bus                  |
| `A` / `B`                                       | `LEFT_SRC=D` + `LEFT_LANE=low`/`high` | the byte halves of `D`                   |
| `USP` `SSP`                                     | `LEFT_SRC`                            | explicit stack pointer                   |
| `SP`                                            | `LEFT_SRC=ACTIVE_SP`                  | active SP; `SP_BANK` picks `USP`/`SSP`   |
| `SCR1` `SCR2`                                   | `RIGHT_SRC`                           | the **only** registers on the RIGHT bus  |
| `-2 -1 0 +1 +2`                                 | `RIGHT_SRC=CONST_*`                   | the const generator (D-36)               |
| `[addr]`                                        | `MEM_OP=read`                         | a memory read (see §6)                   |
| `imm8` / `imm16`                                | fetch idiom                           | sugar for `MDR <- [PC]; PC++` (see §13)  |

| Dest token                                    | Binds to                         | Notes                                                           |
|-----------------------------------------------|----------------------------------|-----------------------------------------------------------------|
| `D` `SCR1` `SCR2` `MDR` `IR` `CC` `USP` `SSP` | `Z_DEST`                         | latch the Z result                                              |
| `A` / `B`                                     | `Z_DEST=D` + `Z_LANE=low`/`high` | byte-lane write                                                 |
| `SP`                                          | `Z_DEST=ACTIVE_SP`               | active SP (SP_BANK)                                             |
| `PC` `MAR` `X` `Y`                            | `*_CTRL=load`                    | counters load **from Z** (their own latch, not a `Z_DEST` code) |
| `[addr]`                                      | `MEM_OP=write`                   | a memory write (LEFT drives the data)                           |

A **byte lane** of a wide dest is addressed with a `.low`/`.high` suffix (`SCR1.low`) →
`Z_LANE=low`/`high`; `A`/`B` are the pre-named low/high lanes of `D`. To *read* a lane, use
`low(x)`/`high(x)` (§5).

A non-counter dest and a counter may latch the **same** Z in one word (the stack-frame
move, microcode.md §3.2): `MAR <- SP; SP <- SP`.

---

## 5. Operators  → ALU

The operator between LEFT and RIGHT selects `ALU_OP` (and `ALU_SHIFT`/`ALU_CIN`):

| Source                               | `ALU_OP`              |                     |
|--------------------------------------|-----------------------|---------------------|
| `a` (just a source)                  | `PASS_L`              | move/latch          |
| `a + b` / `a - b`                    | `ADD` / `SUB`         |                     |
| `a +c b` / `a -c b`                  | `ADC` / `SBC`         | carry-in = `CC.C`   |
| `a & b` / `a \| b` / `a ^ b`         | `AND` / `OR` / `EOR`  |                     |
| `~a` / `-a`                          | `COM` / `NEG`         | unary               |
| `asl(a) lsr(a) asr(a) rol(a) ror(a)` | `SHIFT` + `ALU_SHIFT` |                     |
| `sext(a) low(a) high(a)`             | `LEFT_LANE` steer     | lane, not an ALU op |

RIGHT-bus restriction is enforced: in `a OP b`, `b` must be `SCR1`/`SCR2`/a constant
(§4). `MAR <- MDR + X` is **rejected** (neither `MDR` nor `X` can drive RIGHT) — stage
first: `SCR1 <- MDR` then `MAR <- X + SCR1`.

---

## 6. Memory & MMU

- `dst <- [PC]` — read, address from `PC` (`MMU_ADDR_SRC=translate-PC`).
- `dst <- [MAR]` — read, address from `MAR` (`translate-MAR`).
- `[MAR] <- src` — write; `src` drives the LEFT bus onto the data bus.
- `phys[addr]` — `MMU_ADDR_SRC=direct-physical` (reset, vector fetch).
- A read whose `dst` is a register routes the data to that Z dest in the same cycle; a
  read with no `dst` lands in `MDR`. (Depends on the datapath read→Z path; see §13.)
- Map selection (`MMU_MAP_SEL`) and page-table ops (`MMU_PT_OP`, `LDMMU`/`STMMU`) get a
  `map(kernel|user|imm8)` / `pt(read|write)` clause — **open** (§14).

---

## 7. Counters & concurrent effects

`PC++` `MAR++` `X++` `Y++` are the off-bus `+1` counters (D-36) → `*_CTRL=count`. They
ride along in the same word as a transfer: `IR <- [PC]; PC++`. A counter **load** is
written as a normal transfer to the counter (`MAR <- X + SCR1`) → `*_CTRL=load`.

---

## 8. Flags

The flag clause `: …` selects `FLAG_WE` and the forced-source fields:

- `: nz` — write N,Z from the ALU. `: nzvc` — write all four. Letters ∈ `h n z v c`.
- `v=0` `v=1` `c=0` `c=1` — force that flag (`V_SRC`/`C_SRC`); the letter still implies
  its write-enable.
- `z+` — accumulate Z across a 16-bit op's two byte cycles (`Z_ACCUM`).
- Whole/masked `CC` writes (`RTI`, `ANDCC`/`ORCC`, `PULS CC`) and the privileged M/I
  bits use `cc(...)` / `mi(...)` clauses → `CC_WRITE_SRC` / `CC_MI_LOAD` — **open** (§14).

Example: `A <- [MAR] : nz, v=0`  → `FLAG_WE=N,Z  V_SRC=force-0`.

---

## 9. Sequencer & control flow

Default control is fall-through (`USEQ_OP=INC`). Otherwise a trailing control clause:

| Source              | `USEQ_OP`           |                                             |
|---------------------|---------------------|---------------------------------------------|
| `dispatch`          | `DISPATCH_IR`       | jump via the opcode map `{page,IR}`         |
| `dispatch page1`    | + `DISPATCH_PAGE=1` | the `0x80`-prefixed cold page               |
| `goto L`            | `JUMP`              | `NEXT_ADDR = L`                             |
| `if cond goto L`    | `BRANCH`            | `NEXT_ADDR=L`, `UCOND_SEL/POL` from `cond`  |
| `call R` / `return` | `CALL` / `RETURN`   | one-level `µSR` (D-42)                      |
| `return to fetch`   | `RETURN_FETCH`      | trap-intercepted instruction boundary       |
| `wait`              | `WAIT`              | `/WAIT`-stretched cycle / panel single-step |

**Conditions** (`cond`) name the 16 base conditions + polarity (`UCOND_SEL`/`UCOND_POL`):
`z c n v` , `c|z` , `n^v` , `z|(n^v)` , `true`, and the microconditions
`uloop n irq nmi wait-ready multibyte-last priv illegal`; prefix `not` inverts.

**Loops** use the dedicated loop counter (`ULOOP_CTRL`). Two forms (choose in review §14):
```
# explicit — fully transparent, the branch shares the body word
  count -> uloop                       # uloop <- count
Lbody:
  D <- asl(D) : nzc ; uloop-- ; if not uloop.zero goto Lbody

# structured sugar — still strict 1:1 (the test folds into the body word)
  repeat uloop = count:
      D <- asl(D) : nzc
```

---

## 10. Routine & entry declarations

```
.fetch FETCH                      # marks the fetch entry (must resolve to address 0)
.opcode page0 LD A,(X+n8)         # bind this routine as opcode "LD A,(X+n8)"'s entry
routine LD A,(X+n8):              # a named routine; lines below are its microwords
```

Opcodes are named by their **mnemonic** (the byte value is assigned later — D-41), so the
map binds to the routine label and the mnemonic→byte table is applied at the
opcode-assignment pass. Routines are placed densely; the D-40 map decouples opcode number
from location.

---

## 11. Realizability rules (what the assembler rejects)

Strict 1:1 (P2/P3) is enforced before any bits are emitted:

1. **One source per bus** — at most one `LEFT_SRC`, one `RIGHT_SRC` per word.
2. **RIGHT-bus membership** — the right operand must be `SCR1`/`SCR2`/const (§5).
3. **One ALU op, one Z result** — a word computes one value; two independent transfers
   are two words.
4. **`read` and `write` never coexist** (automatic — `MEM_OP` is one field).
5. **`DISPATCH_PAGE=0` off dispatch**, **`NEXT_ADDR=0` unless BRANCH/JUMP/CALL** (the
   field-definition rules, control_word.toml).
6. **One sequencer action** per word.

A violation is a compile error naming the offending line and the fix (usually "stage to
`SCR1` first").

---

## 12. Worked examples

Each line is one microword; the compiled fields are shown to the right.

**FETCH** (the fetch entry, address 0):
```
.fetch FETCH
routine FETCH:
  IR <- [PC]; PC++; dispatch          # IR_LOAD=opcode MEM_OP=read MMU=translate-PC
                                       #   PC_CTRL=count USEQ_OP=DISPATCH_IR
```

**LD A,(X+n8)** (≈4 cycles) — cf. the field-soup version in [blip.uasm](../microcode/blip.uasm):
```
.opcode page0 LD A,(X+n8)
routine LD A,(X+n8):
  MDR  <- [PC]; PC++                  # MEM_OP=read MMU=translate-PC PC_CTRL=count
  SCR1 <- sext(MDR)                   # LEFT_SRC=MDR LEFT_LANE=sign-ext Z_DEST=SCR1
  MAR  <- X + SCR1                    # LEFT_SRC=X RIGHT_SRC=SCR1 ALU_OP=ADD MAR_CTRL=load
  A    <- [MAR] : nz, v=0             # MMU=translate-MAR MEM_OP=read Z_DEST=D Z_LANE=low
                                       #   FLAG_WE=N,Z V_SRC=force-0
```

**ADD A,$nn** — the staging step (P3) is **visible**, because immediates can't drive RIGHT:
```
routine ADD A,$nn:
  MDR  <- [PC]; PC++                  # fetch immediate
  SCR1 <- MDR                         # stage: MDR -> SCR1 (RIGHT can't take MDR)
  A    <- A + SCR1 : nzvc             # add, set flags  (3 cycles, plainly)
```

**ADD D,$nnnn** (16-bit immediate) — the immediate is **assembled** into a scratch by two
lane-steered byte fetches (little-endian, D-09: low byte first), then one 16-bit add. The
width is **inferred** from `D` being 16-bit (`ALU_WIDTH=16`, `Z_LANE=full16`); a byte lane
of a scratch is written with a `.low`/`.high` suffix (§4):
```
routine ADD D,$nnnn:
  SCR1.low  <- [PC]; PC++             # fetch imm low  -> SCR1[7:0]   (Z_DEST=SCR1 Z_LANE=low)
  SCR1.high <- [PC]; PC++             # fetch imm high -> SCR1[15:8]  (Z_DEST=SCR1 Z_LANE=high)
  D <- D + SCR1 : nzvc                # LEFT_SRC=D RIGHT_SRC=SCR1 ALU_OP=ADD ALU_WIDTH=16
                                       #   Z_DEST=D Z_LANE=full16 FLAG_WE=N,Z,V,C
```
The staging into `SCR1` is forced (P3 — immediates can't drive RIGHT) and here doubles as
the 16-bit assembly. The byte fetches use the read→Z path, confirmed by hardware.md §2
(§13 #1) — one cycle each, no `MDR` hop.

**ASL D,$n** — one cycle per iteration; the branch shares the body word:
```
routine ASL D,$n:
  count -> uloop
Lbody:
  D <- asl(D) : nzc ; uloop-- ; if not uloop.zero goto Lbody
```

---

## 13. Datapath dependencies (settled)

Two datapath behaviours the language relies on, both now pinned:

1. **Read → Z in one cycle — confirmed (hardware.md §2).** A memory read posts its data on
   the Z bus *during* the read, so a named `Z_DEST` and the flags capture it in the same
   word (`A <- [MAR] : nz` is one cycle, microcode.md §5 L3). This is forced by the
   front-panel shadow rule — the shadows track only what appears on Z (hardware.md §6), so
   `MDR`'s read-capture must itself be on Z. `MDR` is therefore a **parallel** capture, not
   a serial stage; it is a required hop only when the value must reach the **RIGHT** bus
   later (the §7.3 staging tax). *Residual:* the gate-level read→Z mechanism (a dedicated
   mux vs a transparent-`MDR` path — note L3 routes to Z with no `LEFT_SRC`) is a
   datapath-build detail, not microcode-visible.
2. **`SP` on the LEFT bus — resolved: `ACTIVE_SP` is a `LEFT_SRC` code.** `LEFT` now has an
   `ACTIVE_SP` driver (code 14, symmetric with the existing `Z_DEST=ACTIVE_SP`), so reads
   and writes of `SP` both use it; `SP_BANK` still selects which physical SP (`USP`/`SSP`)
   is active. The §5 `LEFT_SRC=SP` shorthand is exactly `LEFT_SRC=ACTIVE_SP`.

---

## 14. Open questions (decide in review, before D-44)

1. **Transfer arrow:** `<-` (used here) vs `:=` vs `=`.
2. **Flag-clause syntax:** `: nz, v=0` (here) vs `flags(nz, v=0)` vs trailing `!nzvc`.
3. **Loop form:** explicit `if not uloop.zero goto` vs structured `repeat uloop = n:` —
   or support both (sugar compiling 1:1).
4. **MMU / CC clauses:** spelling of `map(...)`, `pt(...)`, `cc(...)`, `mi(...)`.
5. **Immediate sugar:** is `imm8`/`imm16` worth it, given it hides a fetch line (mild P2
   tension), or always write `MDR <- [PC]; PC++` explicitly?
6. **Opcode binding:** `.opcode page0 LD A,(X+n8)` vs a separate mnemonic→routine table
   file; and how page-1 (`0x80` prefix) entries are declared.
7. **File extension:** keep `.uasm`, or rename (`.uc` / `.ucode` / `.urtl`) now that the
   source is not assembly.
8. **Lane notation:** write-lane suffix `SCR1.low` (§4) vs read-lane function `low(SCR1)`
   (§5) are asymmetric — unify on one, or keep the split (suffix = dest, function = source)?

*(The §13 datapath dependencies are now settled — read→Z confirmed, `ACTIVE_SP` added — so
they are no longer open.)*

---

## 15. Influences (non-normative)

Register-transfer (RTL) notation for microassembly is long-standing practice; the strict
one-statement-per-microword rule is BLIP's own, chosen to keep cycle counts and
front-panel state legible (G5/G6). No external architecture informs the normative content
above.
