# BLIP — ISA Refinement (D-41)

> **Tier-3 supplement** to [isa.md](isa.md), expanding decision
> [D-41](decision-log.md). The normative decision is D-41; this document records
> (1) the **prioritisation criteria** used to triage the instruction space, (2) the
> instructions **removed or relegated** when the indexed postbyte was dropped, and
> (3) the criteria for placing a surviving instruction on **page 0 (base) vs page 1
> (prefixed)**, with the resulting **full two-page inventory** (§5). Per
> [AGENTS.md](../AGENTS.md) it justifies in BLIP's own terms (requirement IDs) and names no
> external architecture.

---

## 1. Background

Removing the indexed postbyte (D-41) turns every addressing mode the postbyte used to
select into a **distinct opcode**. The indexed-capable opcodes therefore stop being a
handful of byte-pairs and become a flat set of *(operation × register × mode)* opcodes.
Expanding every `opcode × RR × TTTT` combination — with indirect dropped, since it is now
programmer-explicit (D-41) — yields **2,640** candidates, far beyond the 256-entry page.
Two triage questions follow:

1. **Which combinations earn an opcode at all** (§2–§3)?
2. **Of those, which sit on the fast base page vs the prefixed page** (§4–§5)?

---

## 2. Prioritisation criteria (the rubric)

Each candidate is rated by **how essential it is to meeting BLIP's requirements** and **how
often the toolchain or kernel must emit or execute it**:

| Tier | Definition (in requirement terms) |
|------|-----------------------------------|
| **Mandatory** | Its absence leaves a requirement unmet: stack-relative locals (R-ISA-1, R-ISA-2), pointer load/store and `*p++`/`*--p` (R-ISA-5), address computation / `&local` (R-ISA-4), the calling convention's call/return/save (R-ABI-1…4), the privilege/trap/interrupt machinery (R-CPU-1…7), MMU control and map switch (R-MEM-3, R-MEM-5). |
| **Crucial** | Omittable without breaking a requirement, but its absence makes the compiler emit materially worse code, violating R-BUILD-1 ("efficient code for the common C constructs"): struct-field and indexed access (R-ISA-3, R-ISA-5), 16-bit arithmetic and compare (R-ISA-6). |
| **Common-P1 / P2 / P3** | Regularly emitted, supporting R-BUILD-1 efficiency or a FUZIX pattern (e.g. the auto-increment copy loops of R-MEM-4), but synthesizable from cheaper instructions. **P1** is hottest (synthesis would hurt inner loops); **P3** is the most easily synthesized. The sub-tiers exist so the budget line can fall *inside* "Common". |
| **Sometimes / Rarely** | Legal and occasionally useful, but required by no requirement and cheaply synthesized; the compiler rarely selects it. |
| **Never** | Structurally meaningless — no real use even with the postbyte. |

The rubric collapses the 2,640-candidate space sharply: the Mandatory and Crucial tiers are
a small fraction of it, and the budget cut for a competitive set falls **inside the Common
band** — close enough to the page boundaries that the Common sub-tiers (P1/P2/P3) decide
exactly what is hot, cold, or dropped. The resulting assignment is §5.

---

## 3. Instructions removed or relegated

With the two pages (D-41) the budget is not a single hard 256-line: most "below-the-line"
instructions are **relegated to page 1** (still reachable, at +1 byte / +1 cycle), and only a
few are **truly removed**.

### 3.1 Truly removed (no opcode on either page)

- **Indirect addressing** (`((…))`). The extra level of dereference becomes an explicit
  second `LD`. R-ISA-5 (pointer access) is still met; pointer-to-pointer and
  through-memory jumps cost one more instruction — rare in C/FUZIX. (Note: single-paren
  extended/absolute `($nnnn)` is **kept** — it is the required ALU-against-globals mode,
  R-BUILD-1; only double-paren `(($nnnn))` indirect is removed.)
- **The 5-bit Form-A offset.** A constant offset is operand data and cannot fold into the
  opcode regardless; with no postbyte to pack a 5-bit field, `(R+n)` simply uses the 8-bit
  (or 16-bit) offset. A code-density loss only, on small-frame locals.
- **Structurally meaningless combinations.** Auto-increment/decrement on `PC`,
  accumulator-offset with `PC` as a data base, store to a `PC`-relative target
  (self-modifying), auto-modify on a compare/branch/jump/call target (a non-destructive
  inspect or a control-transfer target must not have a write-back side effect), and
  auto-inc/dec or accumulator-offset on `SP` as a data base (corrupts the live stack
  pointer; the stack-adjust role is `PSHS`/`PULS`/`LEA SP`). These never carried real use.

### 3.2 Relegated to page 1 (cold, prefix-accessed)

The useful-but-cold tail keeps an opcode, on page 1: long branches `LBcc`; exotic addressing
combos (accumulator-offset on `Y`, 16-bit `PC`-relative, `(R+n16)`, the auto-inc/dec stragglers);
cold ALU-with-memory (`ADC`/`SBC`/`EOR`/`BIT`); wide compares against memory in cold modes;
read-modify-write on globals via the less-common operations; the rarely-executed control /
privileged operations (§4.3); and `DAA`. The genuine *Rarely/Never* overflow beyond page 1's
256 is dropped (synthesizable, requirement-free).

---

## 4. Page-0 vs page-1 placement criteria

### 4.1 The cost model

A page-1 instruction carries the `0x80` prefix and incurs an extra fetch-and-dispatch
microcycle — **+1 byte and +1 cycle**, unavoidable on an 8-bit bus. A page-0 instruction
pays nothing (the page bit idles at 0, in parallel with the map address). So the placement
question is purely: **is this instruction executed often enough that the tax matters?**

### 4.2 The axis: execution frequency

Page placement is decided by **runtime hotness**, grounded in R-CLK-1 / R-CLK-2 (keep the
frequently-travelled path fast) and R-BUILD-1 (code density for the common constructs).
Anything that can appear in an inner loop — the load/store/ALU workhorses, short branches,
calls and returns, increment/decrement, address computation — must be on page 0. Hotness is
judged by **mode**, applied to **both** index registers: `X` is the primary pointer and `Y`
is the callee-saved loop-carried pointer (R-ABI-4), so the hot modes of *each* (`(R)`,
`(R+n8)`, `(R+)`, the `(X+)` accumulate, `(X+D)` index) earn page 0 — not "X on page 0, Y on
page 1".

### 4.3 The refinement: hotness ≠ rubric rank

Execution frequency mostly tracks the rubric, but **diverges for the Mandatory-but-rarely-
executed control and privileged operations**. `RTI`, `SWI`/`SWI2`/`SWI3`, `SEI`/`CLI`,
`LDMMU`/`STMMU`, `HALT`, `SYNC`, `CWAI`, and the USP-banking moves are top-rubric (FUZIX is
unbuildable without them) yet execute once per interrupt, system call, or context switch —
each already inside hundreds of cycles of kernel work, so a +1-cycle prefix is statistically
free. Relegating them to page 1 **frees page-0 slots for genuinely hot operations**. The
inverse case is instructive: `RTS` (every function return) stays page 0, while `RTI` (every
interrupt return) goes to page 1 — same shape, opposite frequency.

`SEI`/`CLI` are the one borderline pair — critical-section guards that may sit in moderately
hot kernel paths; placed on page 1 on the judgement that critical sections are short and the
+1 cycle is immaterial.

### 4.4 Page-0 headroom is residual, not a forced reserve

Page 0 holds **every** instruction the criteria call hot — no slots are held back
artificially. With the hot set placed it lands at **232 of 255** usable opcodes (`0x80`
reserved as the page-1 prefix), leaving **23 free** (D-48 promoted `JSR X` to page 0). That remainder is genuine re-carve
headroom (R-CTRL-1) — profiling can later promote a page-1 instruction without demoting one —
but it is the *residue* of placing the legitimate hot set, not a quota the hot set was
squeezed to meet.

---

## 5. The two-page split (summary)

The full per-opcode inventory is the canonical [isa.md](isa.md) §8.2; this section keeps
only the page-level shape and the placement notes. **Page 0 = 232 opcodes** (23 free of the
255 usable after `0x80` is reserved as the page-1 prefix); **page 1 = 230 opcodes** (26 free
of 256). Verified for budget, hot/cold placement, and requirement coverage (D-41 build pass).
The set is a flat list — no opcode grids (the D-40 map decouples opcode number from routine) —
so concrete byte values are a mechanical sequential assignment (isa.md §8).

Two hot groups a first cut had stranded on page 1 sit on page 0, both because they are
inner-loop bodies on the ABI's live pointers: the **`(X+)` accumulate** forms (`acc op=
*p++`, R-MEM-4) and the **`(Y)` byte-ALU** forms (arithmetic/compare through the
callee-saved loop pointer, R-ABI-4).

| Family | Page 0 | Page 1 |
|--------|-------:|-------:|
| Byte load/store (A, B) | 38 | 36 |
| 16-bit load/store (D, X, Y, SP) | 28 | 42 |
| Byte ALU (page 1 also has ADC/SBC/EOR/BIT) | 67 | 46 |
| 16-bit ALU, wide compare, D shifts | 18 | 22 |
| RMW & register-direct unary | 26 | 14 |
| Control flow (branches, JMP/JSR, calls) | 30 | 39 |
| System / privileged / inherent / LEA / moves | 25 | 31 |
| **Total** | **232** | **230** |

The per-instruction list for each family-and-page cell is [isa.md](isa.md) §8.2.

---

## 6. Status & follow-up

The page split and its rationale are settled; the canonical per-opcode list is
[isa.md](isa.md) §8.2 and the control-word changes are applied ([microcode.md](microcode.md),
[hardware.md](hardware.md), D-41). The set is a **flat list** — no opcode grids — so concrete
byte values are a mechanical sequential assignment, not a design step. The split is reflashable
(R-CTRL-1): page 0 keeps 23 free slots and page 1 keeps 26, so profiling can promote a cold
instruction (e.g. the symmetric `(Y+)` accumulate forms, currently in the synthesizable tail)
without a hardware change. D-48 ratified the set — promoting `JSR X` to page 0 and assigning
the concrete opcode bytes in `isa/opcodes.toml` — so the page totals are now 232 / 230.
