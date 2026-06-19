# BLIP — Microcode & Control-Word Format

> **Tier 3 spec.** How the control unit realizes the instruction set. For the
> datapath this word drives see [hardware.md](hardware.md) §2; for the engine in
> outline see [hardware.md](hardware.md) §4; for the programmer's contract see
> [isa.md](isa.md); for *why* see [goals.md](goals.md).
>
> **Status:** v0 design direction (D-38). The **80-bit, fully horizontal** word and its
> field set are settled in outline; a few sub-field widths (`WIDE_TARGET`, the near-branch
> range) firm up once the writable-control-store depth is fixed. Cycle counts here are
> approximate, to be confirmed in simulation (D-10). *(Narrower words — a 64-bit
> format-overlay word, and 48/56-bit — were evaluated and rejected; see decision log D-38.)*

---

## 1. Principles

The control unit is a **horizontal**, **registered** microsequencer driving a
single fixed-width control word out of a **writable control store** (WCS). The word
exposes *every* datapath primitive directly, so an instruction's whole behaviour —
decode, operand fetch, execution, flags — is the microcode that drives these fields,
with no instruction-specific fixed logic (R-CTRL-1, R-CTRL-4).

Three properties shape the format:

- **Horizontal, one action per microcycle, self-describing.** Each datapath field
  gates one resource and means one fixed thing — no field is re-read under a mode bit —
  so a step does its work in one microcycle and the lit control word reads directly on
  the front-panel LED bank (G5/G6). This keeps the C-critical addressing paths short
  (G2) and the cycle count honest (G9).
- **Registered output.** The whole word is latched at the WCS output, so the lookup
  for microstep *n+1* overlaps the execution of step *n* and the SRAM access stays
  off the critical path (R-CLK-2, R-CTRL-2, G9). Field decoders are spent in the
  execute phase, where their delay overlaps the next fetch.
- **Encoding (D-38).** Mutually-exclusive *selects* are binary-encoded behind a small
  decoder (the LEFT-bus mux, the ALU function inputs, the condition and trap-entry
  indices, the register destination); the bits that *are* a gate or strobe stay direct
  and one-hot (the five per-flag write-enables, the four counter controls, `Z_ACCUM`,
  `TAS_LOCK`). The one field whose meaning depends on context is the 9-bit
  **wide-operand window**, typed by `USEQ_OP` (a far-branch target or a privileged
  special) — a sequencing operand, never a datapath control, so the datapath stays
  fully self-describing.

The word is **80 bits (10 bytes)** — ten 8-bit-wide WCS SRAMs in parallel. Part count
is an explicit non-goal, so the width is chosen to serve the ranked goals rather than to
minimise chips: 80 bits is the narrowest *fully self-describing* word (no field re-read
under a mode bit, per-flag visibility intact) that also leaves headroom — a `TAS` bus-lock
and spare `SPECIAL` codes — for adding privileged primitives by reflashing, not a respin
(G8). Narrower words (a 64-bit format-overlay word; 48/56-bit) were evaluated and rejected
because they spend G5/G6 legibility, hot-path/loop speed, or both — see decision log D-38
and §3.2.

---

## 2. The microsequencer

Next-microaddress selection forms the address from instruction bits — there is **no
mapping PROM and no explicit next-address field per word** (D-24). The straight-line
case is a free counter increment, so it consumes no address field.

```
   IR (opcode / postbyte)   CC flags        microconditions
        |                      |                   |
        |               +------v-------------------v---+
        |               |   condition mux (UCOND_SEL)  |
        |               +--------------+---------------+
        |                              | taken?
   +----v----+   +---------------------v-----------------------+
   |  high   |   |   next-uPC mux  (selected by USEQ_OP)        |
   |  uPC <- |-->|  uPC+1 | uPC+UBR_NEAR | WIDE_TARGET           |
   |  IR     |   |        | IR-formed | postbyte-base | ENTRY    |
   +---------+   +----------------------+----------------------+
                                        |
                                  +-----v-----+   registered
                                  |  uPC reg  |--> control word --> datapath
                                  +-----------+
```

- **`uPC`** is a loadable synchronous up-counter; a combinational next-address mux
  feeds its load input. Default = `uPC+1` (count-enable), so straight-line microcode
  needs no branch-target field.
- **`USEQ_OP`** is the *only* field on the next-address combinational path, so its
  decode is the shortest possible (R-CLK-2, R-CTRL-2). Eight codes: `INC` (default) ·
  `JUMP` (far, to `WIDE_TARGET`) · `DISPATCH_IR` · `DISPATCH_POSTBYTE` · `BRANCH_COND`
  (near, to `uPC+UBR_NEAR`) · `RETURN_FETCH` · `WAIT` · `SPECIAL`.
- **Near vs far.** A conditional micro-branch (`BRANCH_COND`) targets `uPC+UBR_NEAR`, a
  common 5-bit signed displacement that rides the *same word* as a full ALU op + a
  `ULOOP` decrement — so loop bodies stay one cycle. The rare far target uses an
  unconditional `JUMP` to `WIDE_TARGET`; a far *conditional* branch is the standard
  "near `BRANCH_COND` over a `JUMP`" idiom.
- **`SPECIAL`** increments `uPC` like `INC` but types the wide-operand window as the
  privileged `SPECIAL` fields (§4) — used by the `CC`/MMU/mode steps of exceptions,
  `RTI`, and `LDMMU`/`STMMU`.
- **`DISPATCH_IR`** wires the opcode (from `IR`) into the high `uPC` bits — each
  opcode owns a fixed WCS block; pure address wiring, no lookup (D-24).
- **`DISPATCH_POSTBYTE`** ORs the postbyte mode field into the EA-routine base address
  to land on the one **shared** effective-address sub-routine, while `PB_RR_MUX` carries
  the postbyte's register-select field as a datapath mux setting — so one EA routine
  serves every index register (D-24, isa.md §8.3).
- **`BRANCH_COND`** routes the selected condition through `UCOND_POL`: branch to
  `uPC+UBR_NEAR` if it holds, else `uPC+1`. The 16 `Bcc`/`LBcc` conditions come from the
  `IR` low nibble (isa.md §8.6); `UCOND_SEL` selects among the internal microconditions
  (postbyte indirect bit, loop terminal-zero, pending `IRQ`/`NMI`, `/WAIT`-ready,
  multi-byte-last, privilege / illegal-opcode).
- **`RETURN_FETCH`** lands on a fixed entry chosen by `FETCH_ENTRY_SEL` — normal
  `FETCH`, or a trap entry (`IRQ`/`NMI`/`SWI`/`SWI2`/`SWI3`/illegal/privilege), with
  the boundary microconditions gating which one fires. `RESET` is the hardwired
  exception (no slot — isa.md §6, D-30).
- **`WAIT`** holds `uPC` for a `/WAIT`-stretched bus cycle or a panel single-step
  (R-DBG-4).

---

## 3. The control word — 80 bits, fully horizontal

Eighty bits / ten parallel WCS SRAMs. Every datapath field has one fixed meaning; the
only context-typed field is the 9-bit **wide-operand window** (§3.1), selected by
`USEQ_OP`, which is a sequencing operand rather than a datapath control. **Enc** =
`bin` binary-encoded (one decoder) · `lit` literal / direct (one-hot or a value).

| Field | Bits | Enc | Drives / notes |
|-------|------|-----|----------------|
| **Sequencing — 16** |||
| `USEQ_OP` | 3 | bin | next-µPC select (§2); sole field on the next-address path |
| `UCOND_SEL` | 4 | bin | `BRANCH_COND` condition (internal microconditions; the 16 ISA `Bcc` conds come from the `IR` low nibble) |
| `UCOND_POL` | 1 | lit | branch test polarity (true / false) |
| `UBR_NEAR` | 5 | lit | signed **near** micro-branch displacement (`uPC+UBR_NEAR`); rides the same word as an ALU op + `ULOOP` decrement |
| `FETCH_ENTRY_SEL` | 3 | bin | entry `RETURN_FETCH`/traps land on (FETCH/IRQ/NMI/SWI/SWI2-3/illegal/priv) |
| **Wide-operand window — 9** *(typed by `USEQ_OP`; never a datapath control)* |||
| `WIDE_TARGET` \| `SPECIAL` | 9 | — | `JUMP` → `WIDE_TARGET` far microaddress; `SPECIAL` → the privileged `CC`/MMU sub-fields (§4); else don't-care |
| **Fetch / dispatch — 3** |||
| `IR_LOAD` | 2 | bin | hold / latch opcode→`IR` / latch postbyte |
| `PB_RR_MUX` | 1 | lit | EA register select: microcode literal / postbyte `RR` at runtime (one shared EA routine, D-24) |
| **LEFT bus — 6** |||
| `LEFT_SRC` | 4 | bin | LEFT driver → ALU left: `D X Y USP SSP PC MAR SCR1 SCR2 MDR IR-imm MMU-entry CC NONE` |
| `LEFT_LANE` | 2 | bin | lane steer (8-bit bus): full16 / low / sign-ext / high→low |
| **RIGHT + ALU — 12  *(dedicated; never aliased)*** |||
| `RIGHT_SRC` | 3 | bin | RIGHT driver → ALU right: `SCR1 SCR2` + const `{-2,-1,0,+1,+2}` (const-gen, D-36) |
| `ALU_OP` | 4 | bin | function: `PASS_L PASS_R ADD ADC SUB SBC AND OR EOR COM NEG SHIFT` (`ADC`/`SBC` bake cin=`CC.C`) |
| `ALU_SHIFT` | 3 | bin | qualifies `SHIFT`: `ASL LSR ASR ROL ROR` |
| `ALU_CIN` | 1 | lit | residual carry-in not implied by the op: `0` / `CC.C` (rotate-through-carry; 16-bit byte-chain) |
| `ALU_WIDTH` | 1 | lit | 8-bit low lane / 16-bit full (carry gate, V/sign position) |
| **Flags / CC — 10  *(per-flag, no PLA)*** |||
| `FLAG_WE` | 5 | lit | per-flag write-enables `WE_H WE_N WE_Z WE_V WE_C` — one-hot, each clocks one CC flop directly (isa.md §8.5) |
| `V_SRC` | 2 | bin | V source when `WE_V`: from-ALU / force-0 / force-1 |
| `C_SRC` | 2 | bin | C source when `WE_C`: from-ALU / force-0 / force-1 |
| `Z_ACCUM` | 1 | lit | latch this lane's Z / AND with prior lane (correct 16-bit `Z` over two byte cycles) |
| **Z result — 6** |||
| `Z_DEST` | 4 | bin | latch-from-Z (non-counter dests): `NONE D USP SSP ACTIVE_SP SCR1 SCR2 MDR IR CC`; the decoder strobe also clocks the panel shadow (R-DBG-1, D-13) |
| `Z_LANE` | 2 | bin | which lane the dest latches: full16 / low (B) / high (A) |
| **Off-bus counters — 8 (D-36)** |||
| `PC_CTRL` | 2 | bin | hold / load-from-Z / count+1 |
| `MAR_CTRL` | 2 | bin | hold / load-from-Z (capture EA) / count+1 |
| `X_CTRL` | 2 | bin | hold / load-from-Z / count+1 |
| `Y_CTRL` | 2 | bin | hold / load-from-Z / count+1 |
| **Memory / MMU — 6** |||
| `MEM_OP` | 2 | bin | idle / read / write (direction implies `MDR` source + `/RD`÷`/WR`; never co-assert, R-IF-2) |
| `MMU_ADDR_SRC` | 2 | bin | translate `MAR` / translate `PC` (off-bus stream fetch, no `PC→MAR` copy) / emit direct physical (reset, forced vectors) / spare |
| `MMU_MAP_SEL` | 2 | bin | active map: follow-`CC.M` / force-kernel / force-user / from-imm8 (cross-map copy) (R-MEM-3/4/5, D-16) |
| **SP / loop / atomic — 4** |||
| `SP_BANK` | 1 | lit | implicit-`SP` alias: follow-`CC.M` / force-SSP (USP reached as an explicit `LEFT_SRC`/`Z_DEST` code) |
| `ULOOP_CTRL` | 2 | bin | micro-loop counter: hold / load / decrement (terminal-zero → a `UCOND_SEL` microcondition) |
| `TAS_LOCK` | 1 | lit | hold the bus across an RMW (test-and-set indivisible) — for the atomicity primitive (isa.md §9) |

**Total = 80 bits.** The counter `*_CTRL` fields *own* the `PC`/`MAR`/`X`/`Y` load (the
"load-from-Z" op is that register's latch — **not** also a `Z_DEST` code — so a counter
load and a non-counter `Z_DEST` can latch the same Z in one cycle, the stack-frame
`SP-1`+`MAR←newSP` move), and `ULOOP_CTRL` is a dedicated loop counter so data-dependent
loops (`MUL`, the variable `D` shifts, multi-byte walks) never steal a scratch.

### 3.1 The wide-operand window

The single 9-bit window is the only field whose meaning depends on context, and that
context is `USEQ_OP` (always visible), so it reads like any opcode-typed operand field:

- **`WIDE_TARGET`** (when `USEQ_OP=JUMP`) — a full-µPC-width far-branch/jump target, for
  the rare destination `UBR_NEAR`'s ±range can't reach (9 bits ⇒ a 512-word reach
  placeholder; sizes to the store depth, §7).
- **`SPECIAL`** (when `USEQ_OP=SPECIAL`) — the rarely-combined privileged controls:
  `CC_WRITE_SRC` (2: ALU-flags / whole-Z / AND-mask / OR-mask) + `CC_MI_LOAD` (2: hold /
  set-on-entry / from-Z (RTI) / explicit) + `MMU_PT_OP` (2: idle / write a page-table
  entry / read one back) + **3 spare** (headroom for a future privileged primitive,
  added by reflash — G8). The `LDMMU`/`STMMU` slot comes from the instruction imm8;
  user-mode `M`/`I` write-protection is wired in hardware (no control bit).

Crucially the window **does not** alias the ALU-operand bits (it has its own 9 bits), so
a far `JUMP` or a `SPECIAL` step can still drive a full ALU op, set flags, advance
counters, and touch memory in the same cycle. The only thing it can't do is be a far
target *and* a privileged special at once — which never arises (`JUMP` ⊕ `SPECIAL`).
Because no datapath field is ever re-read, the whole datapath stays self-describing on
the LED bank.

### 3.2 Why 80 bits (and not narrower)

Part count is a non-goal, so width answers to the ranked goals. The datapath stayed
horizontal throughout; only the *packing* was in question:

- **48 / 56 bits** need a multi-format vertical overlay that splits the kernel's copy
  loops ~2–3× and loses the self-describing word — rejected (G2/G3/G5/G6).
- **64 bits / 8 SRAMs** is the minimum-compromise point: a single `FORMAT`-overlaid window
  (re-reading the idle ALU-operand bits as the far-branch/special) plus a 4-bit flag-class
  PLA hold every hot path and loop at baseline speed in 8 chips — but they spend two things
  on legibility (the dual-use window and the PLA) and leave zero slack, so a new control
  primitive would need hardware, not a reflash.
- **80 bits / 10 SRAMs** removes both concessions: the ALU-operand region is dedicated (no
  overlay; a far branch or special co-occurs with an ALU op), per-flag flag control is
  direct (no PLA), the `PC`-direct fetch path is baked into `MMU_ADDR_SRC`, and a
  `TAS_LOCK` bit plus spare `SPECIAL` codes give G8 headroom — for two SRAMs the priority
  order does not penalise. The tightenings that cost nothing are kept (`MEM_OP` merge,
  `ALU_CIN` folding carry-in into `ADC`/`SBC`, imm8-only MMU slot, hardware-wired `M`/`I`
  protection and bus-grant tri-state).

Full rationale and the rejected alternatives are in decision log D-38.

---

## 4. Flag control

The five ALU flags each have an independent one-hot write-enable (`FLAG_WE`), so each
is set/forced/held per op class exactly as isa.md §8.5 requires (`LD`: N,Z; logic:
N,Z,V=0; 8-bit `ADD`: all five; `ADD D`: N,Z,V,C; `CLR`: N=0,Z=1,V=0,C=0; `COM`: …,C=1;
`MUL`: Z,C; `LEA X`/`Y`: Z only). `V_SRC`/`C_SRC` choose from-ALU vs force-0/force-1 for
the two flags that get forced. `Z_ACCUM` AND-accumulates `Z` across the two byte cycles
of a 16-bit operation. Each flag write-enable is its own lit bit on the panel — no decode
hides it.

Whole-register and masked `CC` writes (`RTI`, `PULS CC`, `ANDCC`/`ORCC`/`CWAI`, `LD CC`)
use `CC_WRITE_SRC`, and the privileged `M`/`I` bits use `CC_MI_LOAD` — both live in the
`SPECIAL` wide-operand window (`USEQ_OP=SPECIAL`), since they only appear on privileged /
exception / `RTI` steps. User-mode `M`/`I` write-protection is wired in hardware off
`CC.M`, with no control bit (R-CPU-4, R-CPU-6, isa.md §8.7). Because `CC` is also a
`LEFT_SRC`, it can be driven onto Z/`MDR` to save an exception frame or for `PSHS CC`.

---

## 5. Worked microroutines

Representative routines, each step written as its salient control-word settings. These
exercised the field set; the indexed-EA, `JSR`, and `IRQ`-entry routines are what settle
the field count and the scratch question (§6). The stream fetches below use
`MMU_ADDR_SRC=translate-PC`, so `PC` (a stable off-bus counter) feeds the MMU directly
and there is no `PC→MAR` copy.

> **Cycle counts are approximate and depend on a pipeline/timing model not yet pinned
> (simulation will settle them — D-10).** Two timing rules constrain every routine:
> (a) because the registered `MAR` feeds the MMU, a `MAR` load and the read that
> consumes it are **always separate cycles**; and (b) the LEFT bus carries **one source
> per cycle**.

**FETCH** (≈1–2 cycles; `translate-PC` removes the address-setup cycle):
```
F0  MMU_ADDR_SRC=translate-PC MEM_OP=read
    IR_LOAD=opcode PC_CTRL=count USEQ_OP=DISPATCH_IR          ; read opcode @ PC -> IR, PC+1, dispatch
```

**LD A,(X+n)**, 8-bit signed offset — the field-set stress test (≈5 cycles):
```
L0  MMU_ADDR_SRC=translate-PC MEM_OP=read IR_LOAD=postbyte
    PC_CTRL=count                                             ; postbyte @ PC -> decode, USEQ_OP=DISPATCH_POSTBYTE
L1  MMU_ADDR_SRC=translate-PC MEM_OP=read PC_CTRL=count       ; offset @ PC -> MDR
L2  LEFT_SRC=MDR LEFT_LANE=sign-ext Z_DEST=SCR1              ; SCR1 <- sign-extend(offset)   (only live scratch)
L3  LEFT_SRC=X(via PB_RR_MUX) RIGHT_SRC=SCR1 ALU_OP=ADD
    MAR_CTRL=load                                            ; MAR <- X + offset (EA)
L4  MMU_ADDR_SRC=translate-MAR MEM_OP=read
    Z_DEST=D Z_LANE=low FLAG_WE=N,Z V_SRC=force-0            ; A <- (EA), set N/Z, V=0
```

**JSR** (extended target) — stack the return `PC`; uses one scratch (`SCR1`, for the
target); `SP±` is const-gen. The SP-decrement/address step and the push are separate
cycles because the push needs LEFT for `PC`:
```
J*   ... fetch 16-bit target into SCR1 (two byte cycles, Z_LANE low/high) ...
Jn   LEFT_SRC=SP RIGHT_SRC=const(-1) ALU_OP=ADD SP_BANK=follow-M
     Z_DEST=ACTIVE_SP MAR_CTRL=load                          ; SP <- SP-1, MAR <- new SP (one Z, two latches)
Jn+1 LEFT_SRC=PC LEFT_LANE=high MEM_OP=write                 ; push PC high (LEFT->Z->MDR; LEFT now carries PC)
Jn+2 LEFT_SRC=SP RIGHT_SRC=const(-1) ALU_OP=ADD Z_DEST=ACTIVE_SP MAR_CTRL=load  ; SP <- SP-1, MAR <- new SP
Jn+3 LEFT_SRC=PC LEFT_LANE=low MEM_OP=write                  ; push PC low
Jn+4 LEFT_SRC=SCR1 ALU_OP=PASS_L PC_CTRL=load                ; PC <- target
```
The `SP-1`/`MAR<-newSP` step shows the dual Z-latch the word affords: one Z value
latched into `ACTIVE_SP` *and* loaded into the `MAR` counter in one cycle.

**IRQ entry** (accept → frame → enter kernel) — note the commit ordering:
```
I0  (accepted: UCOND_SEL=pending-IRQ & CC.I clear)
    SP_BANK=force-SSP MMU_MAP_SEL=force-kernel               ; supervisor environment, pre-commit
I1  push PC (two bytes) and CC onto SSP   (CC via LEFT_SRC=CC)
I2  USEQ_OP=SPECIAL CC_MI_LOAD=set-on-entry                  ; set M, set I -- AFTER the CC push,
                                                            ;   so the saved CC is the interrupted context
I3  MMU_ADDR_SRC=direct-physical fetch handler addr from the IRQ vector slot -> PC  ; FETCH_ENTRY_SEL routing
```

---

## 6. Scratch registers: one suffices for the ISA core; two retained

Across the validated set — FETCH, `ADD A,$nn`, `LD A,(X+n)`, `ST A,(X+n)`,
`Bcc rel8` (taken/not), `JSR`, `IRQ` entry, `LDMMU` — the **maximum number of scratch
registers simultaneously live is one**; `SCR2` is never asserted. Three structural
reasons make one enough for these:

1. the constant generator supplies `SP±1`/`±2` on RIGHT with no register tied up, so
   the *stack arithmetic* on `JSR`/`IRQ` needs no scratch (a `JSR` still uses one,
   `SCR1`, to hold the target — but only one is ever live at once);
2. `ULOOP_CTRL` is a dedicated loop counter, so loops never steal a scratch;
3. a 16-bit operand assembles low/high into one scratch via `Z_LANE`, and on the
   indexed-EA path the index register streams onto LEFT unstaged while the EA lands in
   `MAR` (a counter destination), so only the sign-extended offset occupies `SCR1`.

**Decision (D-38):** keep **two** scratch registers in the substrate
but treat the second as provisional. The canonical set deliberately omits the routines
that classically force two live operands — `anyreg OP anyreg` staging, `MUL`'s
partial-product + multiplier, and the cross-map block copy. The second scratch is cheap
(one `RIGHT_SRC` code, one `Z_DEST` code, one register) and **removing it later is free
while adding it later is not**, so it stays until those routines are hand-assembled.

---

## 7. Open questions

1. **WCS depth → `WIDE_TARGET` / `UBR_NEAR` range.** `WIDE_TARGET` is a 9-bit
   placeholder and `UBR_NEAR` a 5-bit signed displacement; the final store depth (the
   on-hand part is 8K×8 = 4096 words) fixes both and decides what fraction of
   micro-branches are "near" (the common, free case). Keep `WIDE_TARGET` sized to the
   actually-placed microcode rather than the full part.
2. **Final scratch count** — confirm one vs two after `MUL` / variable-`D`-shift /
   cross-map-copy microcode is written (§6).
3. **Atomicity primitive.** `TAS_LOCK` is wired but its exact RMW semantics depend on
   the still-open isa.md §9 test-and-set decision; the 3 spare `SPECIAL` codes are the
   home for any further privileged primitive that decision needs.
4. **Asymmetric-bus staging tax.** `anyreg`/immediate/`MDR` cannot drive RIGHT, so
   every immediate and signed-offset add stages `MDR→SCR1` first (step L2). A datapath
   consequence (hardware.md §2), not a control-word defect; a future `RIGHT_SRC=MDR`
   option is the fix if profiling shows it dominates the hot paths. Flagged, not required.

*Settled by the final 80-bit design (and open only in the narrower drafts):* the
`PC`-direct fetch path is baked (`MMU_ADDR_SRC=translate-PC`); the word is not zero-slack
(the `SPECIAL` window has spare codes and `TAS_LOCK` is provisioned); and there is no
overlay, so a far branch or special never conflicts with an ALU op (the ALU-operand region
is dedicated, §3.1).
