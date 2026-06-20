# BLIP — Microcode & Control-Word Format

> **Tier 3 spec.** How the control unit realizes the instruction set. For the
> datapath this word drives see [hardware.md](hardware.md) §2; for the engine in
> outline see [hardware.md](hardware.md) §4; for the programmer's contract see
> [isa.md](isa.md); for *why* see [goals.md](goals.md).
>
> **Status:** v0 design direction (D-39, refining D-38). The **88-bit control word is
> split into two clean, chip-aligned sections** — a 3-SRAM **sequencer section** and an
> 8-SRAM **datapath section**, with **no field shared between them**. Settled in outline;
> a few sub-field widths firm up in simulation (D-10); cycle counts here are approximate.
> *(D-38 was an 80-bit word with a format-overlaid window and a near/far branch pair;
> D-39 separates sequencing from datapath into dedicated sections and replaces the
> near/far pair with one 12-bit next-address — see decision log D-39.)*

---

## 1. Principles

The control unit is a **horizontal**, **registered** microsequencer driving a single
fixed-width control word out of a **writable control store** (WCS). The word realizes the
whole ISA — decode, operand fetch, execution, flags — with no instruction-specific fixed
logic (R-CTRL-1, R-CTRL-4).

- **Two clean sections, no shared fields (D-39).** The word divides into a **sequencer
  section** — the only bits that compute the next microaddress — and a **datapath
  section** — the only bits that drive registers, buses, the ALU, memory, flags, and the
  MMU. No field serves both jobs, and there is **no overlay**: every bit means one fixed
  thing. The split falls on a chip boundary (sequencer = WCS SRAMs 0–2, datapath = SRAMs
  3–10), so the two concerns are physically separable on the board and on the LED bank.
- **Horizontal, one action per microcycle, self-describing.** Each field gates one
  resource and is directly readable on the front-panel LED bank (G5/G6); a step does its
  work in one microcycle (G2, G9).
- **Registered output.** The whole word is latched at the WCS output, so the lookup for
  step *n+1* overlaps execution of step *n* and the SRAM access stays off the critical
  path (R-CLK-2, R-CTRL-2, G9).

The word is **88 bits (11 bytes / 11 WCS SRAMs)**: **sequencer section = 24 bits (3
SRAMs)**, **datapath section = 64 bits (8 SRAMs)**. Because the sequencer and datapath
sections are both always present and independent, **any branch co-occurs with a full
datapath op** — loop bodies and conditional-compute stay one cycle (§5).

---

## 2. The microsequencer

The sequencer section's four fields *fully* determine the next µPC; nothing in the
datapath section touches it. The straight-line case is a free counter increment; opcode
dispatch indexes a boot-loaded **opcode→start-address map** SRAM (D-40, superseding D-24's
direct microaddress formation).

```
   IR (opcode/postbyte)   CC flags + microconditions
        |                          |
        |                 +--------v---------+
        |                 | condition mux    | <- UCOND_SEL (4)
        |                 | 16:1 -> XOR pol  | <- UCOND_POL (1)
        |                 +--------+---------+
        |                          | taken?
   +----v----+   +-----------------v---------------------+
   | opcode  |   |  next-uPC mux  (selected by USEQ_OP)  |
   | map SRAM|-->|  uPC+1 | NEXT_ADDR | map[IR] |         |
   | [IR]    |   |        | NEXT_ADDR|postbyte | trap-ent |
   +---------+   +-------------------+-------------------+
                                     |
                               +-----v-----+   registered
                               |  uPC reg  |--> control word --> datapath
                               +-----------+
```

- **`uPC`** is a loadable synchronous up-counter; default `uPC+1` (count-enable) needs no
  address field.
- **`USEQ_OP`** (3 bits, the *microsequencer opcode*) is the sole field on the
  next-address combinational path (R-CLK-2). Seven codes:
  - **`INC`** — `uPC+1` (default).
  - **`BRANCH`** — if `(UCOND_SEL condition) ⊕ UCOND_POL` then `uPC ← NEXT_ADDR`, else
    `uPC+1`.
  - **`JUMP`** — unconditional `uPC ← NEXT_ADDR` (= `BRANCH` on the always-true condition;
    kept as its own code for clarity).
  - **`DISPATCH_IR`** — `uPC ← map[IR]`: the opcode in `IR` indexes a boot-loaded
    **opcode→start-address map** SRAM whose output is the routine's start microaddress
    (D-40, superseding D-24's direct formation). Routines are placed freely/densely — no
    fixed per-opcode block — and the map read is pipelined into the fetch cycle (~10 ns
    SRAM), adding no steady-state cycle. `NEXT_ADDR` is unused.
  - **`DISPATCH_POSTBYTE`** — `uPC ← NEXT_ADDR` with the postbyte mode field OR'd into its
    low bits, so `NEXT_ADDR` is the **EA-routine base** and one shared routine serves every
    index register (`PB_RR_MUX`, in the datapath section, carries the register select).
  - **`RETURN_FETCH`** — return to the fetch entry, **except** a hardware **trap-vector
    priority encoder** intercepts it: when an exception is pending (NMI > IRQ > SWI >
    illegal > privilege) it redirects µPC to that trap's fixed entry instead of FETCH.
    The entry addresses are hardwired; **no control-word field selects them** (this fixed
    priority logic replaces D-38's `FETCH_ENTRY_SEL` field, §3.1).
  - **`WAIT`** — hold `uPC` (disable load/count) for a `/WAIT`-stretched bus cycle or a
    panel single-step (R-DBG-4).
- **Condition (`UCOND_SEL` 4 + `UCOND_POL` 1).** `UCOND_SEL` selects one of **16 base
  conditions**; `UCOND_POL` inverts it, so both senses of each are reachable (32 in all —
  covering the ISA's 16 `Bcc` conditions and their complements):
  - **8 CC-derived:** `Z`, `C`, `N`, `V`, `C∨Z`, `N⊻V`, `Z∨(N⊻V)`, `true`.
  - **8 internal microconditions:** loop-terminal-zero (`ULOOP`), pending-`IRQ` (with
    `CC.I` clear), pending-`NMI`, `/WAIT`-ready, multi-byte-last, privilege-violation,
    illegal-opcode, postbyte-indirect.
  This is a single self-contained condition field — it does not borrow the `IR` nibble.

---

## 3. The control word — 88 bits, two sections

Every field belongs to exactly one section; **no field is shared and no bit is re-read
under a mode/format selector.** **Enc** = `bin` binary-encoded (one decoder) · `lit`
literal/direct (one-hot or a value).

### 3.1 Sequencer section — 3 SRAMs (24 bits)

| Field | Bits | Enc | Role |
|-------|------|-----|------|
| `USEQ_OP` | 3 | bin | microsequencer opcode (§2): INC / BRANCH / JUMP / DISPATCH_IR / DISPATCH_POSTBYTE / RETURN_FETCH / WAIT |
| `NEXT_ADDR` | 12 | lit | the single next-microaddress (4096-deep store); also the base `DISPATCH_POSTBYTE` ORs the postbyte mode into |
| `UCOND_SEL` | 4 | bin | condition select — 16 base conditions (8 CC-derived + 8 internal, §2) |
| `UCOND_POL` | 1 | lit | condition polarity (both senses of each condition) |
| `ULOOP_CTRL` | 2 | bin | micro-loop counter: hold / load / decrement; its terminal-zero is the `loop-zero` condition `UCOND_SEL` reads (a sequencing aux, not a datapath resource) |
| *(spare)* | 2 | — | sequencer-section headroom |

These are the **only** bits that sequence the microprogram — next-address selection plus
the loop counter whose terminal-zero feeds the `loop-zero` condition. Their inputs — `IR` contents,
`CC` flags, the microcondition lines — are *signals*, not shared control-word fields. Trap
entry is hardware-vectored (the priority encoder above), so even `RETURN_FETCH` needs no
field. This is the clean separation D-38's overlay prevented; a bonus is that one 12-bit
`NEXT_ADDR` — always present — lets **any** branch co-occur with a full datapath op (no
near/far distinction; the near/far pair only existed because D-38's far target shared the
ALU-operand bits).

### 3.2 Datapath section — 8 SRAMs (64 bits)

Everything that drives a register / bus / ALU / memory / flag / MMU, always present.

| Field | Bits | Enc | Drives / notes |
|-------|------|-----|----------------|
| `IR_LOAD` | 2 | bin | hold / latch opcode→`IR` / latch postbyte |
| `PB_RR_MUX` | 1 | lit | EA register select: microcode literal / postbyte `RR` at runtime (one shared EA routine, D-24) |
| `LEFT_SRC` | 4 | bin | LEFT driver → ALU left: `D X Y USP SSP PC MAR SCR1 SCR2 MDR IR-imm MMU-entry CC NONE` |
| `LEFT_LANE` | 2 | bin | lane steer (8-bit bus): full16 / low / sign-ext / high→low |
| `RIGHT_SRC` | 3 | bin | RIGHT driver → ALU right: `SCR1 SCR2` + const `{-2..+2}` (const-gen, D-36) |
| `ALU_OP` | 4 | bin | `PASS_L PASS_R ADD ADC SUB SBC AND OR EOR COM NEG SHIFT` (`ADC`/`SBC` bake cin=`CC.C`) |
| `ALU_SHIFT` | 3 | bin | qualifies `SHIFT`: `ASL LSR ASR ROL ROR` |
| `ALU_CIN` | 1 | lit | residual carry-in not implied by the op: `0` / `CC.C` |
| `ALU_WIDTH` | 1 | lit | 8-bit low lane / 16-bit full |
| `FLAG_WE` | 5 | lit | per-flag one-hot write-enables `WE_H WE_N WE_Z WE_V WE_C` (isa.md §8.5) |
| `V_SRC` | 2 | bin | V source when `WE_V`: from-ALU / force-0 / force-1 |
| `C_SRC` | 2 | bin | C source when `WE_C`: from-ALU / force-0 / force-1 |
| `Z_ACCUM` | 1 | lit | latch this lane's Z / AND with prior lane (16-bit `Z` over two byte cycles) |
| `CC_WRITE_SRC` | 2 | bin | whole/masked `CC` write: ALU-flags / whole-Z / AND-mask / OR-mask (`RTI`,`PULS CC`,`ANDCC`/`ORCC`) |
| `CC_MI_LOAD` | 2 | bin | privileged `M`/`I`: hold / set-on-entry / from-Z (RTI) / explicit (SEI/CLI) |
| `Z_DEST` | 4 | bin | latch-from-Z dest: `NONE D USP SSP ACTIVE_SP SCR1 SCR2 MDR IR CC`; the strobe also clocks the panel shadow (R-DBG-1, D-13) |
| `Z_LANE` | 2 | bin | which lane the dest latches: full16 / low (B) / high (A) |
| `PC_CTRL` | 2 | bin | hold / load-from-Z / count+1 (D-36) |
| `MAR_CTRL` | 2 | bin | hold / load-from-Z (capture EA) / count+1 |
| `X_CTRL` | 2 | bin | hold / load-from-Z / count+1 |
| `Y_CTRL` | 2 | bin | hold / load-from-Z / count+1 |
| `MEM_OP` | 2 | bin | idle / read / write (direction implies `MDR` source + `/RD`÷`/WR`; never co-assert, R-IF-2) |
| `MMU_ADDR_SRC` | 2 | bin | translate `MAR` / translate `PC` (off-bus stream fetch) / emit direct physical (reset, vectors) / spare |
| `MMU_MAP_SEL` | 2 | bin | active map: follow-`CC.M` / force-kernel / force-user / from-imm8 (cross-map copy) |
| `MMU_PT_OP` | 2 | bin | page-table access: idle / write entry (`LDMMU`) / read entry (`STMMU`) |
| `SP_BANK` | 1 | lit | implicit-`SP` alias: follow-`CC.M` / force-SSP (USP reached as an explicit `LEFT_SRC`/`Z_DEST` code) |
| `TAS_LOCK` | 1 | lit | hold the bus across an RMW (test-and-set indivisible) — atomicity primitive (isa.md §9) |
| *(spare)* | 5 | — | datapath-section headroom |

**Total = 88 bits (81 used + 7 spare), 11 SRAMs.** The counter `*_CTRL` fields own the
`PC`/`MAR`/`X`/`Y` load (the "load-from-Z" op *is* that register's latch — **not** also a
`Z_DEST` code — so a counter and a non-counter can latch the same Z in one cycle, the
stack-frame move). The dedicated loop counter `ULOOP_CTRL` (sequencer section, §3.1) means
data-dependent loops never steal a scratch.

### 3.3 Why two sections / 88 bits (D-39, superseding D-38)

- **D-38 (80-bit)** packed sequencing and datapath bits together, with a `FORMAT`-overlaid
  9-bit window (far-branch `WIDE_TARGET` vs the `CC`/MMU `SPECIAL` controls, typed by
  `USEQ_OP`) and a **near/far branch pair** (`UBR_NEAR` + the overlaid `WIDE_TARGET`). The
  near/far split existed *only* because the far target shared the ALU-operand bits.
- **D-39** gives each concern a dedicated, chip-aligned section with no shared field. The
  near/far pair collapses to **one 12-bit `NEXT_ADDR`** (a 4096-deep store, R-CTRL); the
  former `SPECIAL` controls (`CC_WRITE_SRC`, `CC_MI_LOAD`, `MMU_PT_OP`) become plain
  always-present datapath fields; trap-entry selection moves from a control-word field
  (`FETCH_ENTRY_SEL`) to a fixed hardware priority encoder.
- **Cost:** 11 SRAMs vs D-38's 10 (~+3 ICs: one SRAM + one pipeline `'574` + one boot
  plane). Accepted for the clean sequencer/datapath separation, the uniform single
  next-address, and 4096-word depth. Part count is a non-goal, so this spends nothing the
  priority order rewards.

---

## 4. Flag control

The five ALU flags each have an independent one-hot write-enable (`FLAG_WE`), set/forced/
held per op class exactly as isa.md §8.5 requires; `V_SRC`/`C_SRC` choose from-ALU vs
force-0/force-1 for the two forced flags; `Z_ACCUM` AND-accumulates `Z` across the two
byte cycles of a 16-bit op. Each write-enable is its own lit bit on the panel — no decode
hides it. Whole-register and masked `CC` writes (`RTI`, `PULS CC`, `ANDCC`/`ORCC`/`CWAI`,
`LD CC`) use `CC_WRITE_SRC`; the privileged `M`/`I` bits use `CC_MI_LOAD` — both now plain
datapath-section fields (D-39 removed the overlay). User-mode `M`/`I` write-protection is
wired in hardware off `CC.M` (R-CPU-4, R-CPU-6, isa.md §8.7). Because `CC` is also a
`LEFT_SRC`, it can be driven onto Z/`MDR` to save an exception frame or for `PSHS CC`.

---

## 5. Worked microroutines

Each step is its salient control-word settings, split by section: **`SEQ{…}`** =
sequencer fields, the rest are datapath fields. Stream fetches use
`MMU_ADDR_SRC=translate-PC` (PC, a stable off-bus counter, feeds the MMU directly — no
`PC→MAR` copy).

> **Cycle counts are approximate** (simulation settles them — D-10). Two timing rules:
> a `MAR` load and the read that uses it are separate cycles; the LEFT bus carries one
> source per cycle.

**FETCH** (≈1–2 cycles):
```
F0  SEQ{USEQ_OP=DISPATCH_IR}  MMU_ADDR_SRC=translate-PC MEM_OP=read
    IR_LOAD=opcode PC_CTRL=count                 ; read opcode @ PC -> IR, PC+1, dispatch
```

**LD A,(X+n)**, 8-bit signed offset (≈5 cycles):
```
L0  SEQ{USEQ_OP=DISPATCH_POSTBYTE, NEXT_ADDR=EA-base}
    MMU_ADDR_SRC=translate-PC MEM_OP=read IR_LOAD=postbyte PC_CTRL=count   ; postbyte -> dispatch
L1  MMU_ADDR_SRC=translate-PC MEM_OP=read PC_CTRL=count                    ; offset @ PC -> MDR
L2  LEFT_SRC=MDR LEFT_LANE=sign-ext Z_DEST=SCR1                            ; SCR1 <- sign-extend(offset)
L3  LEFT_SRC=X(via PB_RR_MUX) RIGHT_SRC=SCR1 ALU_OP=ADD MAR_CTRL=load      ; MAR <- X + offset (EA)
L4  MMU_ADDR_SRC=translate-MAR MEM_OP=read
    Z_DEST=D Z_LANE=low FLAG_WE=N,Z V_SRC=force-0                          ; A <- (EA), set N/Z, V=0
```

**A micro-loop body** (e.g. `ASL D,$n` / multi-byte walk) — **one cycle/iteration**, the
branch and the datapath op share the word (the whole point of the two-section split):
```
Ln  ALU_OP=SHIFT ALU_SHIFT=ASL ALU_WIDTH=16 Z_DEST=D
    SEQ{USEQ_OP=BRANCH, NEXT_ADDR=Ln, UCOND_SEL=loop-zero, UCOND_POL=branch-if-not-zero, ULOOP_CTRL=decrement}
```

**JSR** (extended target) — one scratch (`SCR1`, the target); `SP±` is const-gen:
```
J*   ... fetch 16-bit target into SCR1 (two byte cycles, Z_LANE low/high) ...
Jn   LEFT_SRC=SP RIGHT_SRC=const(-1) ALU_OP=ADD SP_BANK=follow-M
     Z_DEST=ACTIVE_SP MAR_CTRL=load                ; SP <- SP-1, MAR <- new SP (one Z, two latches)
Jn+1 LEFT_SRC=PC LEFT_LANE=high MEM_OP=write       ; push PC high
Jn+2 LEFT_SRC=SP RIGHT_SRC=const(-1) ALU_OP=ADD Z_DEST=ACTIVE_SP MAR_CTRL=load
Jn+3 LEFT_SRC=PC LEFT_LANE=low MEM_OP=write        ; push PC low
Jn+4 LEFT_SRC=SCR1 ALU_OP=PASS_L PC_CTRL=load      ; PC <- target
```

**IRQ entry** — the hardware trap-vector encoder steers `RETURN_FETCH` here; the
microcode is ordinary:
```
I0  SP_BANK=force-SSP MMU_MAP_SEL=force-kernel               ; supervisor environment, pre-commit
I1  push PC (two bytes) and CC onto SSP   (CC via LEFT_SRC=CC)
I2  CC_MI_LOAD=set-on-entry                                  ; set M, set I AFTER the CC push,
                                                            ;   so the saved CC is the interrupted context
I3  MMU_ADDR_SRC=direct-physical fetch handler addr from the IRQ vector slot -> PC
```

---

## 6. Scratch registers: one suffices for the ISA core; two retained

Across the validated set — FETCH, `ADD A,$nn`, `LD A,(X+n)`, `ST A,(X+n)`,
`Bcc rel8` (taken/not), `JSR`, `IRQ` entry, `LDMMU` — the **maximum number of scratch
registers simultaneously live is one**; `SCR2` is never asserted. Three structural
reasons: the constant generator supplies `SP±1`/`±2` on RIGHT with no register tied up;
`ULOOP_CTRL` is a dedicated loop counter; and a 16-bit operand assembles low/high into one
scratch via `Z_LANE` while the indexed-EA lands in `MAR` (a counter destination), leaving
only the sign-extended offset in `SCR1`.

**Decision (D-38):** keep **two** scratch registers in the substrate but treat the second
as provisional. The canonical set omits the routines that classically force two live
operands — `anyreg OP anyreg` staging, `MUL`'s partial-product + multiplier, and the
cross-map block copy. The second scratch is cheap (one `RIGHT_SRC` code, one `Z_DEST`
code, one register) and removing it later is free while adding it later is not — so it
stays until those routines are hand-assembled.

---

## 7. Open questions

1. **Final scratch count** — confirm one vs two after `MUL` / variable-`D`-shift /
   cross-map-copy microcode is written (§6).
2. **Atomicity primitive.** `TAS_LOCK` is wired but its exact RMW semantics depend on the
   still-open isa.md §9 test-and-set decision.
3. **Asymmetric-bus staging tax.** `anyreg`/immediate/`MDR` cannot drive RIGHT, so every
   immediate and signed-offset add stages `MDR→SCR1` first (step L2). A datapath
   consequence (hardware.md §2), not a control-word defect; a future `RIGHT_SRC=MDR` option
   is the fix if profiling shows it dominates. Flagged, not required.
4. **Trap-vector priority encoder** (hardware, replaces D-38's `FETCH_ENTRY_SEL`): confirm
   the exception priority order and entry-address placement when the front-panel / debug
   and interrupt-controller details are specified.

*Settled by D-39:* `NEXT_ADDR` is 12 bits (4096-word store); the sequencer and datapath
sections are cleanly separated (no shared field, no overlay); and a single next-address
replaces the near/far branch pair, so any branch co-occurs with a datapath op.
