# BLIP — Decision Log

> **Non-normative.** This is the running record of design decisions and *why* we
> made them. Specifications justify themselves by citing requirement IDs, not this
> log (see [AGENTS.md](../AGENTS.md)); the log explains how the specs came to be.
> It is also the sanctioned home for **alternatives weighed** and **outside designs
> that informed a choice** — kept here so the normative docs stay
> architecture-name-free.
>
> Each entry: a stable ID, status, the question at stake, the decision, the
> requirement-grounded rationale, and (where relevant) alternatives/influences.

## Index

| ID | Decision | Status |
|----|----------|--------|
| D-01 | 10 MHz is an aspiration, not a hard gate | Decided |
| D-02 | Logic family: 74AHCT | Decided |
| D-03 | Microcode in a writable control store, ROM-loaded at boot | Decided |
| D-04 | Extend memory by paged translation, flat per-process view | Decided |
| D-05 | ISA shape: register-memory, stack-relative + indexed | Decided |
| D-06 | Toolchain: a new SDCC backend | Decided |
| D-07 | Register model: `A B D X Y SP PC CC`; no `U`, no `DP` | Decided |
| D-08 | Privilege: supervisor/user with banked `SSP`/`USP` | Decided |
| D-09 | Byte order: little-endian | Decided |
| D-10 | Realization: simulation-first, then hardware | Decided |
| D-11 | MMU sizing: 8 KB pages, 24-bit physical (16 MB) | Decided |
| D-12 | Add goal G8: a fixed external CPU/system interface | Decided |
| D-13 | Two interfaces: functional + privileged debug | Decided |
| D-14 | MMU is internal to the CPU (external bus is physical) | Decided |
| D-15 | Reset state: identity map + deterministic CPU state | Decided |
| D-16 | MMU control via privileged `LDMMU`/`STMMU` | Decided |
| D-17 | Documentation method: three-tier model + AGENTS.md | Decided |
| D-18 | Protection: map-isolation + privileged instructions; per-page is a non-goal | Decided |
| D-19 | Calling convention: register args, `Y` callee-saved | Decided |
| D-20 | Instruction encoding & the full 256-entry opcode table | Decided |
| D-21 | Single opcode page (no prefix pages) | Decided |
| D-22 | Drop FIRQ; mode bit in CC; minimal interrupt frame | Decided |
| D-23 | Adopt `ADCD`/`SBCD` and `D` multi-bit shifts (`ASLD`/`LSRD`/`ASRD`) | Decided |
| D-24 | Dispatch by microaddress formation (no mapping PROM) | Decided |

---

## D-01 — 10 MHz is an aspiration, not a hard gate
**Status:** Decided (2026-06-17)
**Context:** G6 sets a 10 MHz target; we needed to know how binding it is when it
collides with other goals.
**Decision:** Treat 10 MHz as an aspiration; the achievable clock is whatever the
critical path supports, and it yields to higher-priority goals.
**Why:** It forces a lean, registered microarchitecture (R-CLK-2) without letting
raw speed override correctness or C-friendliness (the priority order in goals §2;
R-CLK-1).

## D-02 — Logic family: 74AHCT
**Status:** Decided (2026-06-17)
**Context:** The core must be one discrete-logic family (R-HW-1), fast enough for
the clock target and level-compatible across the machine (R-HW-2).
**Decision:** Build the core from 74AHCT.
**Why:** Fast enough to chase R-CLK-1, with TTL-compatible input levels so it
interoperates with slower glue and memory (R-HW-2).

## D-03 — Microcode in a writable control store, ROM-loaded at boot
**Status:** Decided (2026-06-17)
**Context:** Control must be developable/correctable (R-CTRL-1, R-CTRL-3) yet fast
at runtime (R-CTRL-2).
**Decision:** Microcode runs from fast SRAM (a writable control store); a small
boot circuit copies the image from non-volatile ROM into that SRAM at power-on.
**Why:** The SRAM read keeps the control path off the timing budget (R-CTRL-2);
RAM is patchable at the bench (R-CTRL-3); the ROM copy makes it retained and
boots unattended (R-CTRL-3).

## D-04 — Extend memory by paged translation, flat per-process view
**Status:** Decided (2026-06-17) — supersedes an initial "accept window-banking
with near/far pointers" idea.
**Context:** Going past 64 KB (R-MEM-2) must not corrupt the C pointer model
(R-MEM-1, R-ISA-*).
**Decision:** Use paged address translation so each process sees a flat 16-bit
logical space; physical memory is the union of many pages.
**Why:** User pointers stay plain 16-bit "near" pointers (R-MEM-1) and each
process is isolated (R-MEM-3). Crude window-banking would expose near/far pointers
to the compiler and break R-MEM-1.

## D-05 — ISA shape: register-memory, stack-relative + indexed
**Status:** Decided (2026-06-17)
**Context:** Be a genuine C target (G2 → R-ISA-1…8).
**Decision:** A small register file with a 16-bit accumulator and index registers;
stack-relative displacement addressing for locals; indexed / auto-inc / accumulator-
offset modes for pointers; a hardware stack for reentrancy.
**Why:** R-ISA-1 (one-instruction locals), R-ISA-3/4/5 (live pointers, address
computation, pointer-access modes), R-ISA-8 (reentrancy).
**Influences (non-normative):** the 6809's stack-relative/indexed addressing; the
STM8 register shape.

## D-06 — Toolchain: a new SDCC backend
**Status:** Decided (2026-06-17) — reworded goal #3 from "SDCC" to "a real
optimizing C compiler; plan: SDCC".
**Context:** Need an optimizing C compiler that targets BLIP and can build the OS
(R-BUILD-1); BLIP is a clean-sheet ISA, so *some* backend must be written.
**Decision:** Write a new SDCC backend; document GCC as the heavier alternative.
**Why:** SDCC is purpose-built to retarget to constrained 8-bit machines and is the
most realistic effort, with a stable documented ABI (R-BUILD-1, R-ABI-1).
**Influences:** SDCC's STM8 backend is the closest relative to clone. (The fact
that FUZIX builds its 6809 targets with GCC is an availability accident — no SDCC
6809 port exists — not evidence SDCC is unsuited to this ISA style.)

## D-07 — Register model: `A B D X Y SP PC CC`; no `U`, no `DP`
**Status:** Decided (2026-06-17)
**Context:** Choose the register file for the C target (R-ISA-3/6/7).
**Decision:** Two 8-bit accumulators `A`/`B` pairing into a 16-bit `D`; two 16-bit
index registers `X`/`Y`; a stack pointer `SP`; `PC`; `CC`. No second user stack
(`U`), no direct-page register (`DP`).
**Why:** `D = A:B` makes char/int conversion cheap (R-ISA-7); `X`/`Y` plus `n,SP`
cover pointers and locals (R-ISA-1/3). A third live pointer is a luxury, and `DP`
pays off little for C because locals live on the stack, not in a fixed global page.
A 16-bit `SP` displacement removes any need for a frame-pointer register (R-ISA-2).
**Influences:** matches the STM8 register shape (`X`, `Y`, `SP`).

## D-08 — Privilege: supervisor/user with banked `SSP`/`USP`
**Status:** Decided (2026-06-17)
**Context:** Two motivations: (1) a clear separation between kernel and user-space
execution, and (2) clean, robust plumbing for interrupts and system calls.
**Decision:** Two CPU modes (a `CC.M` mode bit); the stack pointer is banked
(`USP` in user, `SSP` in supervisor); a trap or interrupt switches to supervisor
mode and the supervisor stack automatically, and `RTI` restores the prior mode.
**Why:** On a trap/interrupt the CPU saves return state onto the **known-good
kernel stack** regardless of the user stack's state, so entry cannot be corrupted
by a bad user `SP` — the primary motivation (R-CPU-5). The mode bit also cleanly
separates kernel and user execution and selects the active map set (R-MEM-5).
Enforcement of isolation is handled cheaply via privileged instructions (D-18),
not per-page protection.

## D-09 — Byte order: little-endian
**Status:** Decided (2026-06-17)
**Context:** Byte order is arbitrary but has toolchain consequences (R-BUILD-1).
**Decision:** Little-endian.
**Why:** Minimizes friction in the C backend (R-BUILD-1).

## D-10 — Realization: simulation-first, then hardware
**Status:** Decided (2026-06-17)
**Context:** Validate the ISA and microcode before committing to hardware.
**Decision:** Prove v1 in a logic simulator, then build hardware against the sim
as a reference model.
**Why:** Cheap microcode/ISA debugging; in simulation 10 MHz is "free," so
correctness leads and the real clock is measured later (R-CLK-1).

## D-11 — MMU sizing: 8 KB pages, 24-bit physical (16 MB)
**Status:** Decided (2026-06-17)
**Context:** Pick translation granularity and physical size (R-MEM-2, R-MEM-6).
**Decision:** 8 KB pages; 24-bit physical address = 16 MB (2048 pages). A 16-bit
logical address therefore has 8 page slots.
**Why:** Megabytes of physical hold a kernel plus several processes without
swapping (R-MEM-2); 8 KB balances internal waste against translation-table size
(R-MEM-6).

## D-12 — Add goal G8: a fixed external CPU/system interface
**Status:** Decided (2026-06-17)
**Context:** We wanted the CPU to be a self-contained module with a stable
boundary to the rest of the system.
**Decision:** Added goal G8 — functional peripherals attach only through a fixed,
documented external interface; the CPU is revised *within* that boundary.
**Why:** Modularity — internals can change without disturbing peripherals, and
memory/I/O/panel get one well-understood place to attach.

## D-13 — Two interfaces: functional + privileged debug
**Status:** Decided (2026-06-17)
**Context:** Displaying internal registers (R-DBG-1) needs more than the functional
interface exposes, but R-IF-1 forbids functional peripherals from touching CPU
internals.
**Decision:** A separate, privileged **debug interface** exposes internal state to
the **front panel only** (R-DBG-5); the front panel is the sole exception to R-IF-1.
**Why:** Exactly one privileged observer, with its own channel; the functional
contract stays clean.

## D-14 — MMU is internal to the CPU (external bus is physical)
**Status:** Decided (2026-06-17) — supersedes an earlier lean toward an external
MMU.
**Context:** Where does the translation unit sit relative to the G8 boundary? It
affects timing, the interface, and the front panel.
**Decision:** Translation and protection are inside the CPU; the external bus
carries the 24-bit physical address; the functional interface carries no privilege
or fault line.
**Why:** Translation can overlap address generation, keeping it off the memory
critical path (R-CLK-1); the external fault/abort path disappears; the front panel
reaches physical memory directly for bootstrap (R-DBG-3). Software still sees a flat
16-bit logical model (R-MEM-1), the external interface stays fixed (G8), and it is
all discrete logic plus a small SRAM (R-HW-1).
**Alternatives/notes:** External MMU (CPU emits logical address + privilege line)
was the earlier recommendation. Reversed after weighing the above: the 8 extra
address lines are a minor cost, and "welded to the CPU" is *not* a G8 violation,
since G8 fixes the *external* interface, which an internal MMU keeps stable (just
physical).

## D-15 — Reset state: identity map + deterministic CPU state
**Status:** Decided (2026-06-17)
**Context:** The machine must be runnable before software configures translation
(R-DBG-3, first bring-up), and reset must be deterministic.
**Decision:** On reset, translation defaults to a transparent identity map of the
low 64 KB (logical = physical); the CPU enters supervisor mode, interrupts masked,
at a fixed reset vector.
**Why:** R-MEM-7 (run before translation is configured), R-CPU-7 (deterministic
startup), R-DBG-3 (front-panel bootstrap into known physical locations). Also
restores easy "MMU-less" bring-up that an internal MMU (D-14) would otherwise lose.

## D-16 — MMU control via privileged `LDMMU`/`STMMU`
**Status:** Decided (2026-06-17)
**Context:** How does software program the now-internal translation (R-CPU-4,
R-MEM-5)?
**Decision:** The page table is an internal privileged register file, written by
dedicated privileged instructions `LDMMU`/`STMMU`.
**Why:** With the MMU internal, dedicated instructions are the clean mechanism;
writes are supervisor-only so user code cannot remap itself (R-CPU-4); the active
map set follows the privilege mode (R-MEM-5).

## D-17 — Documentation method: three-tier model + AGENTS.md
**Status:** Decided (2026-06-17)
**Context:** We wanted self-justifying, traceable rationale rather than appeals to
authority or cargo-culting.
**Decision:** Goals → requirements (stable IDs, each `⟸` a goal) → specs (which
cite requirement IDs). No external architecture in normative text; alternatives and
influences are quarantined (e.g. to this log). Recorded in [AGENTS.md](../AGENTS.md).
**Why:** Legible, traceable design whose rationale stands on its own.

## D-18 — Protection: map-isolation + privileged instructions; per-page is a non-goal
**Status:** Decided (2026-06-17)
**Context:** Given D-08's mode bit, how much protection to *enforce* in hardware.
Three layers were on the table: (A) banked stacks + mode bit [D-08], (B)
instruction-level privilege, (C) per-page access protection (read-only/no-access
bits with a fault).
**Decision:** Keep (A) and (B); **(C) is a non-goal.** Isolation rests on the
per-process address map — a process can only address its own pages (R-MEM-3) —
plus privileged map-control instructions (`LDMMU`/`STMMU`, and `RTI`,
interrupt-mask, `HALT`) that trap if attempted in user mode. `SWI` stays
unprivileged as the syscall gateway; a privilege-violation trap handles user-mode
attempts.
**Why:** Map isolation + privileged map-control already satisfy R-CPU-4 (user code
cannot reach or alter anything outside its space, including the translation
config), and (B) is nearly free once D-08's mode bit exists — a clean trap at
instruction dispatch. (C) is the only part that adds real cost: a check in the
memory critical path (against R-CLK-1) and fiddly mid-access instruction aborts —
and it is not needed for isolation.

## D-19 — Calling convention: register args, `Y` callee-saved
**Status:** Decided (2026-06-17)
**Context:** Fix the one stable ABI (R-ABI-1) and resolve the R-ABI-2 ↔ R-ABI-4
tension over a finite register file.
**Decision:** Reentrant, stack-based locals (`n,SP`, no frame pointer). Leading
scalar args in registers — first 8-bit in `B`, first 16-bit in `X` — the rest on
the stack right-to-left; the **caller** cleans up. Returns: 8-bit `B`, 16-bit `X`,
32-bit/aggregate via a hidden pointer. **`Y` is callee-saved (preserved);
`A`/`B`/`D`/`X`/`CC` are caller-saved.** Full spec in [isa.md](isa.md) §7.
**Why:** Register args make small/leaf calls cheap (R-ABI-2); `B` is the low half
of `D`, so char↔int promotion is nearly free (R-ISA-7); 16-bit values returned in
`X` are immediately usable as pointers (R-ABI-3); and a preserved `Y` keeps a
loop-carried pointer live across calls without spilling (R-ABI-4). Reserving `Y`
(rather than making it a second arg register) is what lets the convention satisfy
R-ABI-2 *and* R-ABI-4 at once — affordable because the 16-bit `SP` displacement
removes any need for `Y` as a frame pointer (R-ISA-2).
**Alternatives/notes:** `Y` caller-saved (a second 16-bit argument register) was
the other option — more register-arg throughput, but nothing preserved across a
call, failing R-ABI-4; rejected. Costs of the chosen path: the backend must be
taught a callee-saved register (the cloned base has none), and 32-bit returns use
the hidden-pointer path so `Y` stays unambiguously preserved.

## D-20 — Instruction encoding & the full 256-entry opcode table
**Status:** Decided (2026-06-17)
**Context:** With the register model (D-07), addressing modes, and calling
convention (D-19) settled, freeze the full opcode table.
**Decision:** A single 256-opcode page (no prefix pages — see D-21): regular
nibble-aligned grids (high nibble = band, low nibble = operation) for the RMW, A/D,
B/wide, and branch blocks, with the remaining ops packed into holes. Full table,
indexed postbyte, register/flag encoding, relocations, and reserved slots in
[isa.md](isa.md) §8. The supervisor/user mode bit, the `CC` layout, and the
interrupt model were revised in **D-22** (mode moved into `CC`; `FIRQ` dropped).
**Why:** Regular grids keep decode/microcode and the assembler simple and make
collisions structurally unlikely (R-CTRL-1); the table realizes the C-target
addressing and ABI needs (R-ISA-\*, R-ABI-\*) and the privileged system/MMU set
(R-CPU-1/4, R-MEM-5).
**Process / verification:** Generated exhaustively and checked by independent
adversarial passes (collisions/coverage, flag-effect consistency,
addressing/operand lengths, completeness); coverage verified 256/256 collision-free
with nothing lost in re-packing. Fixes applied across the runs: added the missing
**`JMP`**; removed redundant duplicate encodings; made **`LDMMU`/`STMMU`** consistent
(no flags); corrected **`CWAI`** flags to per-mask; resolved three **dual-mode ops**
(`TAS` → indexed; `LDMMU`/`STMMU` → `#imm8` entry-selector); normalized indexed
byte-lengths; and closed the **user-mode `CC` mask** privilege hole. An initial
encoding with two prefix pages was produced first, then dropped in favour of the
single page (D-21) before any commit. Cycle counts are deferred until the datapath
bus count (hardware.md §9) is decided.

## D-21 — Single opcode page (no prefix pages)
**Status:** Decided (2026-06-17) — supersedes the initial prefix-page encoding under
D-20.
**Context:** The first encoding used a primary page plus two prefix pages
(`0x10`/`0x11`) for long branches, wide compares, and system/MMU ops. Keep that, or
hard-limit to one 256-opcode page?
**Decision:** One 256-opcode page, no prefix bytes — every instruction is one opcode
byte + 0–3 trailing bytes. The ~216 instructions pack into 256 with ~40 slots free;
the formerly-prefixed ops move into holes (long branches → `0xB0–0xBF`; wide compares
→ the `0x30`-row holes; `SEI/CLI`, USP banking, `LDMMU/STMMU`, `TAS` →
low-page holes).
**Why:** The prefix spill was caused by the field-encoded grid's reserved holes, not
by real space exhaustion. A single page simplifies instruction fetch/decode (uniform
"opcode → dispatch", no prefix-byte state) and gives a modest code-density /
fetch-cycle win for the formerly-prefixed ops; the common case and the clock are
unchanged. Microcode size is not a constraint (writable control store + planned
microcode tooling + cheap SRAM/EEPROM), so dense packing beats a prefix mechanism.
**Alternatives/notes:** Field encoding is what keeps microcode lean (opcode bits
parameterize shared routines); under dense packing that survives where the grids are
kept (RMW, A/D, B/wide, branch-condition) and is otherwise carried as decode-hint
fields in the microcode dispatch table. Cost accepted: a hard 256 ceiling (~40 free)
and a table-driven (not algorithmic) encoding — both fine for a lean, microcoded
design.

## D-22 — Drop FIRQ; mode bit in CC; minimal interrupt frame
**Status:** Decided (2026-06-17) — supersedes D-20's mode-location choice; realigns
with D-08 (which always had the mode in `CC`).
**Context:** The early design carried a fast interrupt `FIRQ` (mask `CC.F`, minimal
frame) and an `E` "entire-frame" bit, both inherited from the 6809 influence without
a requirement behind them. `R-CPU-3` calls only for a maskable IRQ + timer + NMI.
**Decision:** Remove `FIRQ`. Keep one maskable `IRQ` (mask `CC.I`) plus `NMI`. Every
interrupt/trap stacks a **minimal frame (`PC`+`CC`)**; the handler saves any other
registers it uses via `PSHS`/`PULS` (matching the caller-saves ABI, D-19). This
frees the `F` mask, makes the `E` bit redundant (single frame type), and removes the
`SEF`/`CLF` opcodes (`0x0E`/`0x0F` → reserved). The freed room lets the
supervisor/user **mode bit `M` live in `CC`** (bit7); new `CC` = `M – H I N Z V C`
(bit6 reserved). `M` saves/restores automatically with `CC` and is protected from
user-mode writes alongside `I`.
**Why:** `FIRQ` was unjustified by any requirement (R-CPU-3); `IRQ`+`NMI` give two
levels, ample for the OS, and a minimal frame gives low-latency entry on a discrete
CPU. Mode-in-`CC` is simpler than the separate-state choice in D-20 (which was forced
only by `CC` being full) — it rides `CC` save/restore and reuses the existing
user-mode-`CC`-write protection.
**Alternatives/notes:** A full auto-stacked register frame was considered and
rejected (slow entry; conflicts with caller-saves). One `CC` bit is left reserved in
case a second interrupt level is ever justified.

## D-23 — Adopt `ADCD`/`SBCD` and `D` multi-bit shifts
**Status:** Decided (2026-06-18)
**Context:** A study of another homebrew TTL CPU (Magic-1) surfaced two capabilities
BLIP lacked that a C target benefits from: 16-bit add/subtract **with carry-in**, and
a multi-bit shift of the 16-bit accumulator. (See the influence note below.)
**Decision:** Add `ADCD`/`SBCD` (16-bit add/subtract-with-carry on `D`; immediate /
indexed / extended) at `0xF5–0xFA`, and `ASLD`/`LSRD`/`ASRD #n` (shift `D` left /
logical-right / arithmetic-right by an immediate count) at `0xFB–0xFD`. Both sit in
the `0xF0–0xFF` "wide ops" band beside `LDSP`/`STSP`. The shift count is an immediate;
a runtime-register count is **not** added (see below). Spec in [isa.md](isa.md) §8.8.
**Why:** `ADCD`/`SBCD` keep multi-word (`long`) integer add/subtract on the 16-bit
arithmetic path instead of emulating the carry chain in 8-bit steps (R-ISA-6),
shrinking the compiler's `long` helpers (R-BUILD-1). The `D` shifts fill a real hole —
the base set has no 16-bit shift on `D` — and make constant-count shifts (scaling by
powers of two, field extraction), the dominant C case, single instructions (R-ISA-6,
R-BUILD-1).
**Alternatives/notes:** A *runtime-variable* shift (count in a register) was
considered and deferred: `D = A:B` holds the value being shifted, so the count would
have to occupy `X`/`Y` (the pointer/return registers), which is too costly to
standardise; the constant-count form captures most of the benefit and a register-count
form can be added later if profiling justifies it. Placing these in the `0xF` band
(rather than column-adjacent to `ADDD`/`SUBD`) is forced by the ALU grids being
column-full; the `0xF` band already collects 16-bit `SP` ops, so the wide ALU ops sit
coherently there. Cost accepted: nine of the formerly-free `0xF5–0xFF` slots are now
used (~34 free remain, D-21).
**Influences (non-normative):** Magic-1 (Bill Buzbee) implements 16-bit
add/subtract-with-carry and register-count variable shifts. The 8-bit lineage BLIP
draws its *shape* from notably lacked 16-bit add-with-carry (a later revision of that
family added it) — the gap `ADCD`/`SBCD` close. These are the *source* of the idea,
not its justification; the requirements above are.

## D-24 — Dispatch by microaddress formation (no mapping PROM)
**Status:** Decided (2026-06-18)
**Context:** hardware.md §4 listed "dispatch on `IR`" as a next-address capability but
not its implementation; working through the fetch/decode path raised whether the
opcode→microroutine selection should be a mapping PROM.
**Decision:** Dispatch forms the microaddress directly from instruction bits — the
opcode (from `IR`) is the high part of `µPC`, the within-routine step the low part; the
indexed postbyte's mode field is OR'd into a base microaddress to reach the *shared*
effective-address sub-routine, with the postbyte's register-select field carried as a
datapath mux setting. There is **no mapping PROM/ROM and no separate lookup memory** on
the dispatch path; it indexes the same writable control store (WCS) SRAM as the rest of
the microcode. Spec in [hardware.md](hardware.md) §4.
**Why:** A non-volatile lookup on the per-instruction dispatch path would reintroduce
the very access latency that R-CTRL-2 — and the boot-copy of microcode into fast SRAM
(D-03) — exist to eliminate. Direct microaddress formation is pure wiring (no lookup
stage), keeps dispatch off the cycle-time budget (R-CTRL-2), and stays fully patchable
because routine placement lives in the boot-copied image (R-CTRL-1, R-CTRL-3). It also
makes the postbyte a true operand specifier consumed by shared microcode — one EA
routine serving all index registers — matching the single-page encoding (D-21).
**Alternatives/notes:** (1) A mapping **PROM** indexed by the opcode — rejected: too
slow on the hot path (the same argument as D-03). (2) A boot-loaded **SRAM** map — fast
and patchable, but adds a serial lookup stage before the WCS for no benefit over direct
addressing; not adopted. (3) A combinational **PAL/PLA** decoder — fast, but fixed
logic, so it fights "correct/extend microcode without rewiring" (R-CTRL-1/3). (4)
Folding *all* control state (flags, postbyte-mode, loop counts) into the address to
eliminate next-address logic entirely — rejected: live flags force replicating every
microstep across all flag values, and removing branches further needs postbyte-mode and
loop-count fields in the address, multiplying the control store by large factors; an
increment-only step also cannot express data-dependent loops (`MUL`, the variable
shifts), and dropping jumps breaks microcode sharing. The blow-up in WCS and boot-ROM
costs far more than the few packages of next-address logic it would save. The
addressing trick is therefore used only where the field is constant for the whole
instruction (opcode, postbyte-mode).

---

## Pending (not yet decided)

Tracked in the docs' own "Open questions" sections; the load-bearing ones:

- **Datapath bus count** — one shared 8-bit bus vs two/three. ([hardware.md](hardware.md) §9)
- **I/O addressing** — separate I/O space vs fully memory-mapped.
  ([requirements.md](requirements.md))
- **Concrete interface spec** — formalize the functional + debug signal lists.
- **Step-3 retrofit** — scrub remaining architecture names from the normative
  parts of isa/hardware/README into *Influences* sections.
