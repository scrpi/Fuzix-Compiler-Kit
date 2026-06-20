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
>
> **Goal numbers** in older entries reflect the numbering current when they were
> written; [goals.md](goals.md) is authoritative for current numbers. Entries are
> **not** retroactively renumbered (this supersedes D-27's earlier approach), so the
> renumber/reprioritise entries (e.g. D-26, D-27, D-32) record the mapping of their
> era.

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
| D-12 | Add goal G6: a fixed external CPU/system interface | Decided |
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
| D-25 | Assembly notation house style (verb/register split, `$`-hex, parens=memory, `LD`/`XCHG`) | Decided |
| D-26 | Strengthen G7 (ISA fully in microcode, field-reprogrammable); reprioritise blinkenlights > interface > microcode | Decided |
| D-27 | Renumber goals so numbering matches priority order (G5↔G7, G6↔G8) | Decided |
| D-28 | Memory-mapped I/O: one 8 KB physical I/O page inside the boot identity window | Decided |
| D-29 | Functional CPU/system interface: sync bus + `/WAIT`, separate `/RD`/`/WR`, separate buses, fixed-vector IRQ/NMI, REQ/GRANT | Decided |
| D-30 | Exception entry: auto-mask `CC.I` on entry; fixed pointer-slot vectors (RESET hardwired) | Decided |
| D-31 | Reset vector & physical memory map: reset entry `0x000000`, monitor/loader boots kernel from block device | Decided |
| D-32 | Add goal G5 (legible component architecture); renumber G5–G8 → G6–G9 | Decided |
| D-33 | Discrete architectural registers (no SRAM register file) | Decided |
| D-34 | High-level datapath: 16-bit core, two-bus (S+R + ALU latch), dedicated address incrementer | Decided |
| D-35 | Rename internal buses to LEFT / RIGHT / Z (Z replaces R, avoids clash with RIGHT) | Decided |
| D-36 | Off-bus `+1` up-counters on PC/MAR/X/Y; USP/SSP & `+2`/`-1`/`-2` via ALU + const-gen `{-2..+2}` | Decided |
| D-37 | Logic family refined: 74AHCT (SSI) + 74ACT (MSI) — AHCT has no counters/ALU | Decided |
| D-38 | Microcode control-word format: 80-bit horizontal control word (10 SRAMs, fully self-describing); one scratch sufficient for the ISA core (two retained) | Decided |
| D-39 | Control word restructured into two clean chip-aligned sections (sequencer + datapath), single 12-bit next-address; 88-bit / 11 SRAMs | Decided |

---

## D-01 — 10 MHz is an aspiration, not a hard gate
**Status:** Decided (2026-06-17)
**Context:** G8 sets a 10 MHz target; we needed to know how binding it is when it
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

## D-12 — Add goal G6: a fixed external CPU/system interface
**Status:** Decided (2026-06-17)
**Context:** We wanted the CPU to be a self-contained module with a stable
boundary to the rest of the system.
**Decision:** Added goal G6 — functional peripherals attach only through a fixed,
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
**Context:** Where does the translation unit sit relative to the G6 boundary? It
affects timing, the interface, and the front panel.
**Decision:** Translation and protection are inside the CPU; the external bus
carries the 24-bit physical address; the functional interface carries no privilege
or fault line.
**Why:** Translation can overlap address generation, keeping it off the memory
critical path (R-CLK-1); the external fault/abort path disappears; the front panel
reaches physical memory directly for bootstrap (R-DBG-3). Software still sees a flat
16-bit logical model (R-MEM-1), the external interface stays fixed (G6), and it is
all discrete logic plus a small SRAM (R-HW-1).
**Alternatives/notes:** External MMU (CPU emits logical address + privilege line)
was the earlier recommendation. Reversed after weighing the above: the 8 extra
address lines are a minor cost, and "welded to the CPU" is *not* a G6 violation,
since G6 fixes the *external* interface, which an internal MMU keeps stable (just
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

## D-25 — Assembly notation house style
**Status:** Decided (2026-06-18)
**Context:** BLIP began with a 6809-style notation (register baked into the mnemonic —
`LDA`, `SUBA`; `#imm` immediates; bare `addr16`; `n,X` indexed). A column-by-column
comparison against Z80, STM8, 6502, Magic-1, 8080, and 8086 (non-normative
[isa-comparison.md](isa-comparison.md)) was used to settle one consistent house style.
**Decision:** Four rules, now applied throughout [isa.md](isa.md) (§4.1 and the §8 tables):
1. **Verb/register split** — the operand register is separated from the verb:
   `LDA`→`LD A`, `SUBA`→`SUB A`, `NEGB`→`NEG B`, `CMPX`→`CMP X`, `STA`→`ST A`,
   `LEAX`→`LEA X`. Mnemonics with no register designator are unchanged.
2. **Immediates are bare `$`-hex** — `#$05`→`$05` (the `#` is dropped).
3. **Parentheses mean memory (dereference)** — `(addr)` is the contents at `addr`:
   register-indirect `(X)`, displacement `(X+6)`, accumulator `(X+B)`, auto-inc/dec
   `(X+)`/`(-X)`, absolute `($1234)`, indirect `((X+6))`. An operand that names an
   *address* rather than its contents stays bare — a `LEA` result (`LEA X,X+4`) and a
   jump/branch target (`JMP X`, vs the indirect `JMP (X)`).
4. **Register↔register moves use `LD`/`XCHG`** — `TFR src,dst`→`LD dst,src` (operands
   swap: `LD` is destination-first), `EXG`→`XCHG`. `TFR`/`EXG` retire as mnemonics; the
   assembler emits the transfer/exchange opcode when both operands are registers (one
   `LD` verb over register/immediate/memory operands).
**Why:** A single, unambiguous notation lowers friction for hand-written kernel code and
for reading compiler output (R-BUILD-2); the parens-mean-memory convention removes the
immediate-vs-memory ambiguity the old `#`/bare split papered over. It is a *notational*
choice only — opcodes, encodings, and semantics are unchanged (a register copy is still
the transfer opcode; a load still sets `N/Z`).
**Notes / consequences:** (a) The opcode matrix now shows several `LD` cells (the
memory/immediate loads, the register move at `0x06`, the USP-banking form at `0x1A`) —
expected when one verb is overloaded; the assembler disambiguates by operand kind.
(b) A behavioural wrinkle surfaced by the unification: a memory/immediate `LD` sets
`N/Z`, but the register-move `LD` (old `TFR`) sets no flags, so `LD`'s flag effect
depends on operand kind. Left as-is for now (preserves `TFR` behaviour); making the
register-move form also set `N/Z` for uniformity is a possible future tweak.
**Influences (non-normative):** Z80 (one `LD` verb, parens = memory) and 8086 (`XCHG`,
bracket-memory) — sources of the spelling, not its justification.

## D-26 — Strengthen G7 (ISA fully in microcode) and reprioritise
**Status:** Decided (2026-06-18)
**Context:** G7 and R-CTRL-1/3 already said the instruction set could be "developed,
corrected, and extended without rewiring," but framed it as bench-time editing of
*decoding/sequencing*. Ben wants the stronger property as a first-class goal: the ISA
must be **fully** expressible in microcode and changeable in the field by reflashing
EEPROM, never by respinning a board.
**Decision:** (1) Sharpen **G7** ("The ISA lives in microcode"): the whole instruction
set — encodings, addressing modes, operations, flag effects — is defined by the
control-store image, with no instruction-specific behaviour in fixed logic; the datapath
is a fixed, general substrate exposing a complete set of microcode-controllable
primitives; the ISA is corrected/extended/redefined by reflashing the boot EEPROM.
(2) Strengthen the requirements: **R-CTRL-1** (whole ISA control-store-defined, no fixed
instruction logic), **R-CTRL-3** (field-reprogrammable, not just bench-modifiable), and a
new **R-CTRL-4** (the datapath is a complete microcode substrate). (3) Reprioritise so
**G5 (blinkenlights) > G6 (interface) > G7 (microcode)** — observability and the fixed
external boundary outrank microcode flexibility; new order is G1, G2, G3, G4, G5, G6, G7,
G8.
**Why:** It makes the ISA a software artifact over a fixed machine — longevity and
evolvability without board changes (G7). It is already *realised* by the boot-copy of
microcode EEPROM→SRAM (D-03) and microaddress-formation dispatch with no fixed decode
PROM (D-24); this records the intent and sets a standing guardrail on datapath design (no
hardwired special-case an instruction's meaning depends on). The honest boundary — what
microcode cannot change without hardware (register set/widths, ALU primitives, bus
topology, MMU, the G6 interface, control-word width) — is stated in G7 so the goal stays
bounded and testable.
**Notes:** The reprioritisation reads as "keep the machine observable and its interface
clean before reaching for microcode convenience." The ISA's *shape* still answers to G2,
which outranks all three.

## D-27 — Renumber goals to priority order
**Status:** Decided (2026-06-18)
**Context:** After D-26 reprioritised the goals, the goal *numbers* no longer matched
their priority rank — confusing, since the numbering is cited throughout the docs.
**Decision:** Renumber so the number *is* the priority rank. Mapping `G5↔G7` and `G6↔G8`
(G1–G4 unchanged): old G5 (microcode) → **G7**, old G6 (clock) → **G8**, old G7
(blinkenlights) → **G5**, old G8 (interface) → **G6**. Applied across goals.md,
requirements.md (every `⟸ Gn` link and the coverage table), this log, and hardware.md;
isa.md / AGENTS.md / README.md reference only G1–G4 and were untouched.
**Why:** The priority order is load-bearing (the design cites it for tie-breaks); making
the numbering match it removes a standing source of confusion. The reorder is a pure
relabelling — no goal, requirement, or decision changed in substance.
**Note:** Earlier entries now name goals by their *current* numbers (e.g. the external
interface, added under D-12, is **G6** — though it was introduced as G8); the log tracks
the live design, not its numbering history.

## D-28 — Memory-mapped I/O in a physical I/O page (no separate I/O space)
**Status:** Decided (2026-06-18)
**Context:** With the MMU internal and the external bus physical (D-14), we had to
choose how peripherals are addressed: a separate I/O space — its own qualifier line
and `IN`/`OUT` instructions — or memory-mapped into the ordinary address space.
**Decision:** I/O is **memory-mapped**. There is no separate I/O address space, no
`IN`/`OUT` instructions, and no "memory vs I/O" qualifier on the functional
interface. Peripherals are decoded — *outside* the CPU — from a reserved region of
the 24-bit **physical** space: a single 8 KB **I/O page** at physical
`0x00E000–0x00FFFF` (frame 7, the top frame of the low 64 KB), device registers at
fixed offsets within it. A device access is an ordinary `LD`/`ST` that the MMU
translates to a physical address the system decodes to a peripheral.
**Why:**
- *Minimal, stable interface (R-IF-2, R-IF-6).* No extra bus line and no I/O
  opcodes — the functional interface stays address + data + transfer-qualifying
  control, and nothing about I/O is wired into the CPU.
- *C-friendly (G2).* Drivers touch device registers as ordinary `volatile` pointers
  through the existing load/store addressing modes. BLIP has no data cache and does
  not reorder loads/stores, so no hardware ordering machinery is needed.
- *Protection for free (D-18).* The only way to reach the I/O page is a map entry,
  and only supervisor code writes maps (D-16). A user map that omits frame 7 cannot
  touch hardware; the kernel maps frame 7 into its own map for drivers — the same
  mechanism that isolates memory gates devices.
- *Boot reachability (D-15, R-MEM-7).* The I/O page sits inside the reset identity
  window, so the boot ROM reaches the console and storage with no MMU setup.
**Consequences:**
- The I/O region is page-granular (8 KB): the whole frame maps as a unit; devices
  share it at offsets. An 8 KB hole at physical `0x00E000` is never handed out as
  RAM (negligible against 16 MB).
- Constrains the still-open reset-vector location ([isa.md](isa.md) §9): reset entry
  must not fall inside `0xE000–0xFFFF`, which the boot identity map exposes as the
  I/O page.

## D-29 — Functional CPU/system interface
**Status:** Decided (2026-06-18)
**Context:** `R-IF-1…6` set the interface requirements; we needed to fix the concrete
signalling. The privileged debug interface ([D-13](decision-log.md)) is deferred.
**Decision:** Specify the functional interface in [interface.md](interface.md):
a **24-bit physical** address output ([D-14](decision-log.md)), an **8-bit**
bidirectional data bus, a **synchronous** bus referenced to a single **`CLK` input**
with a **`/WAIT`** extension, **separate `/RD` and `/WR`** strobes, **fully separate
(non-multiplexed)** buses, **fixed-vector (software-polled)** interrupts on a **level `/IRQ`** + **edge
`/NMI`**, and a **two-line `/BUSREQ`/`/BUSGRANT`** arbitration handshake — 41
architectural signals.
**Why (per fork):**
- *Synchronous + `/WAIT`* over async handshake: full speed in the common case (G8),
  trivial for fast SRAM, still admits slow devices; async adds a per-cycle return
  path that works against G8.
- *Separate `/RD`/`/WR`* over R/W + strobe: map straight onto SRAM `/OE`/`/WE` and
  peripheral enables with no glue; memory-mapped I/O (D-28) removes any
  memory-vs-I/O qualifier.
- *Separate buses* over multiplexed: the address is always valid and legible for
  blinkenlights (G5); part count is a non-goal, so the pin saving isn't worth the
  lost observability and the ALE timing tax.
- *Fixed-vector, software-polled* over device-vectored: no acknowledge cycle and no
  vector lines on the boundary (keeps `R-IF-6` minimal); fits FUZIX's modest device
  set; the handler polls to find the source.
- *`CLK` input* over output: the clock can be gated or single-stepped externally for
  bring-up and blinkenlights (G5); the oscillator is a permitted support module.
- *Level `/IRQ` + edge `/NMI`*: level IRQ allows wire-OR sharing and poll-to-source
  (matches the poll-to-find-source model); edge NMI fires once per event.
- *Two-line REQ/GRANT, release at cycle boundary*: the simplest handshake that meets
  `R-IF-4`; a third grant-acknowledge line only earns its keep with multiple masters.
**Notes:** Exact CLK-edge timing waits on the datapath bus count (pending). The
reset-vector address and physical memory map remain open ([isa.md](isa.md) §9). The
interrupt/trap *entry* mechanism (hardwired entry vs fixed memory slot) is settled in
[D-30](decision-log.md) — a fixed pointer-slot vector table, `RESET` hardwired — with
only the table's physical address deferred to the memory-map decision. This entry
also removes the stale "fast interrupt" from `R-IF-3`, consistent with D-22.

## D-30 — Exception entry: auto-mask on entry, fixed pointer-slot vectors
**Status:** Decided (2026-06-18)
**Context:** D-29 fixed interrupts as fixed-vector / software-polled but left two
details open: whether interrupt acceptance masks further interrupts, and how an
exception reaches its handler.
**Decision:**
- **Auto-mask on entry.** Accepting any interrupt or trap (`IRQ`, `NMI`, `SWI`, the
  fault traps) saves the old `CC`, then sets `CC.I`, so the handler runs with `IRQ`
  masked; `RTI` restores the saved `CC`. The kernel re-enables interrupts (`CLI`)
  when it is safe. (`NMI` itself stays non-maskable; the entry masking only blocks
  `IRQ` nesting.)
- **Fixed pointer-slot vectors.** `NMI`/`IRQ`/`SWI`/traps each dispatch through a
  fixed table of pointer slots holding handler addresses; the CPU loads `PC` from the
  slot (resolved in the kernel map that entry selects). The kernel installs handlers
  by writing the table at init. `RESET` is special — RAM is invalid at reset, so it
  uses a hardwired entry into boot ROM, not a slot.
**Why:**
- Auto-mask suits a simple, largely non-reentrant kernel (G3): handlers start in a
  known masked state and choose when to re-enable (R-CPU-3). Without it every handler
  would have to mask by hand before touching shared state, and a tick could nest
  immediately.
- A pointer-slot table lets the OS install and change handlers at runtime (G3) with
  no microcode change, at the cost of one memory indirection per exception. Hardwired
  entries (no table) were rejected as too rigid for an OS; device-supplied vectors
  were already rejected (D-29) as needing an acknowledge cycle on the interface.
**Notes:** Resolved by [D-31](decision-log.md): the table sits at the top of the
resident common region (logical `0xFFE0–0xFFFF`).

## D-31 — Reset vector & physical memory map
**Status:** Decided (2026-06-18)
**Context:** isa.md §9 left open the reset-entry address, the reset `PC`/`SP` values,
the exception vector-table location ([D-30](decision-log.md)), and where ROM/RAM/I/O
sit in physical space. D-15 (identity-map boot) and D-28 (I/O page) constrain it.
**Decision:**
- **Reset entry & state.** `PC = 0x000000` (start of boot ROM) — the hardwired reset
  entry of D-30; `CC` = supervisor, `IRQ` masked (D-15); `SSP = 0x00E000` (top of boot
  RAM, just below the I/O page). Translation is the identity map of the low 64 KB.
- **Boot-visible physical layout** (what the reset identity map exposes):
  - `0x000000–0x003FFF` (16 KB) — boot ROM: the firmware monitor/loader (reset entry,
    hardware init, block-device driver, kernel loader, default handlers).
  - `0x004000–0x00DFFF` (40 KB) — RAM: monitor stack and staging.
  - `0x00E000–0x00FFFF` (8 KB) — I/O page (D-28).
- **Rest of physical** `0x010000–0xFFFFFF` — RAM (kernel + process frames). No
  ROM-shadow/disable latch: with the internal MMU (D-14) ROM has a fixed physical home
  reachable at reset and is simply left unmapped afterward.
- **Boot model.** A **firmware monitor/loader** in boot ROM initialises hardware and
  **loads the FUZIX kernel from a block device** into RAM (placing it across physical
  frames via `LDMMU` windowing), builds the kernel map, populates the exception vector
  table, and enters the kernel; the kernel re-enables interrupts and starts the tick.
  The means by which the loader locates the kernel on the device (raw reserved sectors
  vs partition vs filesystem) is **deferred**.
- **Logical layout (every map).** The resident **common** region is slot 7 (logical
  `0xE000–0xFFFF`, R-MEM-4): trap/interrupt entry stubs, map-switch code, `udata`, and
  the **exception vector table** at the top (`0xFFE0–0xFFFF`). User programs link from
  `0x0000` and get slots 0–6 (56 KB); the user stack grows down from `0xDFFF`. At
  runtime `0xE000` is the common, so the kernel maps the physical I/O page into a
  separate free slot for device access (it is at `0xE000` only under the boot identity
  map).
**Why:**
- `0x000000` is the natural reset entry: reachable through the boot identity map
  (D-15) and clear of the `0xE000–0xFFFF` I/O page (D-28), and a hardwired low entry
  needs no vector fetch before RAM is valid (D-30).
- Loading the kernel from a block device rather than ROM matches how FUZIX is run
  (G3): the kernel and root filesystem share one medium and the kernel updates without
  reflashing. (Unlike a no-MMU machine, BLIP needs no ROM-disable latch — the MMU just
  unmaps ROM.)
- Common-at-top gives a zero-based program load address and puts vectors at the top of
  memory; keeping the common in every map means trap entry and cross-map copy always
  find their stubs (R-MEM-4).
**Notes:** Resolves isa.md §9 Q1 and fixes the D-30 vector-table address. The boot-ROM
region is sized generously (16 KB) for the monitor/loader (which must include a
block-device driver); the means of locating the kernel on the device remains open. In
simulation the block device is a disk image, so the same loader path works from first
bring-up (D-10).

## D-32 — Add goal G5 (legible component architecture); renumber G5–G8 → G6–G9
**Status:** Decided (2026-06-18)
**Context:** Wanting discrete registers "so I can see them" exposed a property no goal
captured: G1 permits standard SRAM, and blinkenlights only require register *values* be
displayable — neither forbids collapsing architectural state into one opaque package.
**Decision:** Add a new Tier-1 goal **G5 — a legible, component-level architecture**:
each architectural element (registers, ALU, flags, internal buses) is its own
identifiable physical component, not collapsed into opaque / addressed / time-
multiplexed storage; memory-like arrays (main memory, control store, MMU table) are
exempt. Rank it **just above blinkenlights**, so the existing goals shift: old
G5→G6, G6→G7, G7→G8, G8→G9 (G1–G4 unchanged). New requirement **R-HW-4 ⟸ G5**.
**Why:** It is the structural precondition for blinkenlights (you can only light a
register that physically exists) and a strengthening of G1's discreteness toward
*legibility* — the soul of a bench machine you watch think at the component level.
Ranked below the functional goals (G1–G4), which it never conflicts with, but above
blinkenlights, the interface, microcode, and clock — the things it is traded against
(density / part-count / speed), where visibility is ranked higher.
**Scope of renumber:** applied to the normative docs (goals.md, requirements.md,
hardware.md, interface.md). The decision log is **not** retroactively renumbered —
older entries keep the numbering of their era and goals.md is authoritative (see the
index note; this supersedes D-27's renumber-the-log approach).

## D-33 — Discrete architectural registers (no SRAM register file)
**Status:** Decided (2026-06-18)
**Context:** The first structural choice for the internal datapath: how the register
set is realized. (Bus count and the rest of the datapath follow from this plus the ALU
and address path, not the other way around.)
**Decision:** The architectural and working registers are **discrete registers** — one
physical register per element, individually buffered for display — **not** an SRAM
register file. Memory-like arrays stay SRAM.
**Why:** Required by **R-HW-4 (⟸ G5)** — each register must be an individually visible
component, which an SRAM file hides as addresses inside one chip. It also gives
blinkenlights (G6) a per-register latch to display directly, and a discrete register is
typically *faster* than an addressed file (no read-port arbitration), so it does not
cost G9.
**Notes:** This is an input to the high-level datapath architecture (to be written in
hardware.md); the internal **bus count / topology** falls out of the register ports +
ALU routing + address path. The earlier 1/2/3-bus cycle analysis becomes *evidence*
(it shows a single shared bus is too slow), not a standalone decision.

## D-34 — High-level datapath architecture (16-bit core, two-bus, address incrementer)
**Status:** Decided (2026-06-18)
**Context:** With discrete registers fixed (D-33), the internal datapath needed its
high-level shape — and the **bus count was to fall out of that design**, not be picked
first (the principle behind D-33).
**Decision:**
- **16-bit core.** One 16-bit ALU and 16-bit internal buses; 8-bit ops (`A`/`B`) use the
  low lane. One ALU serves data, pointer, and effective-address math (no separate address
  adder).
- **Two buses.** A source bus `S` and a result bus `R`; the ALU reads input 1 live from
  `S` and input 2 from an operand latch `L` (loaded from `S` a microcycle earlier),
  result to `R`. Register moves are ALU pass-throughs; two-operand ops take two
  microcycles.
- **Dedicated address incrementer** on `PC` and `MAR`, off the buses, for `PC++` and
  16-bit byte-stepping.
**Why:**
- *16-bit core:* most registers are 16-bit (D-07), so a 16-bit datapath keeps pointer/EA
  math single-pass (G2, G9) and gives one uniform ALU primitive for microcode
  (G8 / R-CTRL-4). Extra parts are accepted (a non-goal; G1/G5).
- *Two buses, not three:* the 8-bit external memory makes the machine memory-bound, so a
  third bus's parallelism rarely shows in wall-clock (the earlier cycle analysis); two
  buses mean fewer drivers and a simpler front panel, at the cost of one extra microcycle
  to stage the second ALU operand.
- *Dedicated incrementer:* `PC++` every fetch and the byte-stepping inside every 16-bit
  access are the hottest paths; off the ALU/buses they overlap the memory cycle (G9) and
  keep the 2-bus microcode simple.
**Alternatives:** 8-bit core (rejected — pointer/EA math pays 2× on the critical path,
against G2/G9); three buses (rejected — benefit capped by the 8-bit memory bus, more
drivers, less legible); ALU-only increments (rejected — every `PC++`/byte-step would
occupy the single ALU + buses, serial with data work).
**Notes:** Bus count is thus a *consequence* of the datapath, per the design principle.
Written into [hardware.md](hardware.md) §2; remaining detail (ALU parts, control-word
width/format, pipeline depth) is hardware.md §9.

## D-35 — Rename internal buses: LEFT / RIGHT / Z
**Status:** Decided (2026-06-18)
**Context:** The working datapath direction ([hardware.md](hardware.md) §2) adds a
second, sparsely-driven ALU source bus named **RIGHT**. D-34's result bus was called
**R**, which now reads ambiguously against RIGHT.
**Decision:** Name the internal buses:
- **Z** — the **result** bus (ALU drives it, registers latch from it). **Z replaces the
  name `R`** used in D-34; the bus's role is unchanged. This rename is firm regardless of
  how the source side evolves.
- **LEFT** — the source bus *every* register can drive (ALU left input).
- **RIGHT** — the source bus only the scratch registers + constant generator drive (ALU
  right input).
(LEFT/RIGHT name the source side of the current — still tentative — two-source-bus
direction; **Z** is the firm rename either way.)
**Why:** Avoids confusing the result bus "R" with the source bus "RIGHT" in specs,
microcode listings, and on the front panel; LEFT/RIGHT-into-the-ALU and Z-out read
unambiguously.
**History note:** Earlier entries — notably **D-34** — keep their original `S`/`R`
naming and are **not** retroactively edited (per the log policy in the index note).
hardware.md and later specs use LEFT / RIGHT / Z.

## D-36 — Off-bus address increment: `+1` up-counters on PC/MAR/X/Y
**Status:** Decided (2026-06-19)
**Context:** D-34's off-bus incrementer was left open in hardware.md §2 (keep / drop /
post-on-Z), and the constant generator (`reg+const` via ALU → Z) overlapped its job. We
needed to fix *which* registers get a dedicated incrementer, and how wide.
**Decision:**
- **Off-bus `+1` up-counters on `PC`, `MAR`, `X`, `Y`** — each a 16-bit loadable
  synchronous counter (4× `74ACT163` — AHCT has no MSI counters, see D-37), so `+1` is a
  control line internal to the register,
  clear of the LEFT/RIGHT/Z buses and the ALU (hardware.md §2.1).
- **`USP`/`SSP` are not counters;** they and all `+2`/`-1`/`-2` steps go through the **ALU +
  constant generator**, whose set is finalised as **`{-2, -1, 0, +1, +2}`**.
- The front-panel shadow (D-13, §6) stays correct by making each counter register's shadow
  a counter too, advanced by the same count strobe.
**Why:** a `+1` up-counter only helps where `+1` dominates; for `+2`/`-1`/`-2` the ALU +
constant generator already does the step in one cycle, so a counter offers nothing there.
- `PC`/`MAR` are ~100% `+1` (instruction-stream fetch; multi-byte byte-stepping) → ideal
  (G9).
- `X`/`Y` are `+1` for byte-pointer loops (`*p++`, `*d++ = *s++` — pervasive in C/FUZIX,
  G2); making *both* index registers counters lets them advance off-bus and overlap memory.
  Word (`+2`) and pre-decrement fall back to the ALU.
- `USP`/`SSP` stepping is `±2`-and-decrement dominated (every call is `SP-2`; 16-bit
  save/restore `±2`; frames `±N`); the lone `+1` case (8-bit pull) is a minority and its
  8-bit-push partner is a `-1` a counter can't do — so an up-only counter would sit idle.
- `-2` is required by the call path (`SP-2`), hence its addition to the constant set.
**Alternatives:** shared `'283` adder (rejected — more muxing, no advantage over
per-register counters for `+1`); `reg+const` through the ALU for *all* increments (rejected
for `PC`/`MAR`/`X`/`Y` — loses the off-bus overlap on the hot paths); up/down counters on
`X`/`Y` for off-bus pre-decrement (deferred — revisit only if microcode timing shows
pre-decrement loops are hot).
**Notes:** Resolves the address-increment open question in hardware.md §2/§2.1. The
"one scratch register or two?" question remains open.

## D-37 — Logic family refined: 74AHCT for SSI, 74ACT for MSI
**Status:** Decided (2026-06-19)
**Context:** D-02 chose **74AHCT** as the working family, but AHCT is an SSI-focused line —
it carries gates, buffers, registers, and latches but **no MSI**: no synchronous counters
(and no ALU/adder slices). The off-bus address counters (D-36) and the ALU need MSI parts.
**Decision:** Use **74AHCT** for SSI and the common functions (gates, buffers `'244`/`'245`,
registers `'574`/`'377`, latches), and **74ACT** for the MSI parts AHCT does not offer —
beginning with the address counters (`74ACT163`, D-36). MSI parts that ACT also lacks (some
ALU/adder slices) are taken from the nearest TTL-level family as availability dictates; the
ALU's family is fixed with the ALU part choice (hardware.md §9).
**Why:** AHCT has no counter/ALU MSI, so the core cannot be single-family in the literal
sense. AHCT and ACT are both **5 V, TTL-input CMOS**, so they interoperate at consistent
signaling levels — preserving the *intent* of R-HW-2 (uniform levels, fast enough for
R-CLK-1) even though two part-families are used. This refines D-02 and relaxes R-HW-2's
"single family" to "one consistent TTL-level CMOS signaling regime."
**Notes:** D-02 is left as the original record (not retroactively edited). ACT has faster
edges and higher drive than AHCT, so decoupling/layout get the usual care; electrically the
two mix cleanly. Touches hardware.md §1/§2.1 and R-HW-2.

## D-38 — Microcode control-word format (80-bit horizontal control word)
**Status:** Decided (2026-06-19)
**Context:** The datapath was settled (D-33/D-34/D-35/D-36) and dispatch by
microaddress-formation was settled (D-24), but hardware.md §4/§9 still listed the
control-word **width and field layout** as TBD. With the datapath fixed, the control word
that drives it could be enumerated, sized, and chosen. *(This entry squashes the
pre-commit width exploration — earlier 96-bit and 64-bit drafts — into the single landed
decision; the rejected widths are recorded under Alternatives below.)*
**Decision:** A single **horizontal, registered, 80-bit (10-byte) control word** — ten
8-bit-wide WCS SRAMs in parallel — specified in [microcode.md](microcode.md). The word is
**fully self-describing**: every datapath field has one fixed meaning (no mode/format bit
re-reads any datapath control), so the lit word reads directly on the front-panel LED bank
(G5/G6). Structure:
- **Sequencer:** `uPC` up-counter + next-address mux, no explicit next-address field per
  word and no mapping PROM (D-24). `USEQ_OP` (8 codes) is the sole field on the
  next-address path; conditional micro-branches take a common 5-bit near displacement
  (`UBR_NEAR`, which rides the same word as a full ALU op + a `ULOOP` decrement, so loop
  bodies are one cycle); the rare far target is an unconditional `JUMP` to `WIDE_TARGET`.
- **Datapath fields:** LEFT-bus source + lane; a dedicated RIGHT+ALU region (RIGHT source
  incl. the constant generator `{-2..+2}`, ALU op, shift, carry-in, width); `Z_DEST`+lane;
  the four off-bus counter controls (each owns its load-from-Z latch, so a counter and a
  non-counter can latch the same Z in one cycle); `MEM_OP`; `MMU_ADDR_SRC` (incl. a
  `translate-PC` stream-fetch path that removes the `PC→MAR` copy) and `MMU_MAP_SEL`;
  `SP_BANK`; `ULOOP_CTRL`; `TAS_LOCK`.
- **Flags:** **per-flag** one-hot write-enables (`FLAG_WE`) + `V_SRC`/`C_SRC`
  force-selects + `Z_ACCUM`, matching isa.md §8.5 exactly, each its own lit bit (no PLA).
- **The one context-typed field** is a 9-bit **wide-operand window**: `WIDE_TARGET` (a far
  microaddress) when `USEQ_OP=JUMP`, or the privileged `SPECIAL` sub-fields
  (`CC_WRITE_SRC`, `CC_MI_LOAD`, `MMU_PT_OP`, + spare) when `USEQ_OP=SPECIAL`. It is a
  *sequencing* operand — never a datapath control — so the datapath stays fully horizontal.
- **Scratch registers:** **one is sufficient for the validated ISA core; two are retained
  in the substrate** as provisional (see below).
**Why:**
- *Horizontal, one action per microcycle, self-describing* keeps the C-critical addressing
  paths a single step each (G2) and the cycle count honest (G9), makes the datapath a
  complete microcode substrate with no instruction-specific fixed logic (R-CTRL-1,
  R-CTRL-4), and keeps the control word point-and-readable on the LED bank (G5/G6).
- *Registered word* overlaps the WCS lookup for step *n+1* with execution of step *n*,
  keeping the store off the critical path (R-CTRL-2, R-CLK-2).
- *Width = 80 bits / 10 SRAMs.* Part count is an explicit non-goal, so the store width is
  chosen to serve the ranked goals rather than to minimise chips: 80 bits is the narrowest
  *fully self-describing* word — no field re-read under a mode bit, per-flag visibility
  intact — that also leaves headroom (a `TAS_LOCK` bit and spare `SPECIAL` codes) for
  adding privileged primitives by reflashing, not a respin (G8 / R-CTRL-3). Narrower words
  were evaluated and rejected (below).
**Validation:** Multi-agent workflows hand-assembled the canonical microroutines (FETCH,
`ADD A,$nn`, `LD A,(X+n)`, `ST A,(X+n)`, `Bcc rel8` taken/not, `JSR`, `IRQ` entry,
`LDMMU`, and the `ASL D,$n` micro-loop) against competing formats. Findings folded into
the design: the maximum scratch registers simultaneously live is **one** (`SCR2` never
asserted); five corrections (CC as a `LEFT_SRC`; an active-`SP` write-back gated by
`SP_BANK`; runtime page-table slot from imm8; cross-map `MMU_MAP_SEL` override; a
fixed-physical emit path for the vector slots); and the `IRQ` ordering (`CC.M/I` commit
*after* the `CC` push). Hand-assembly also caught two physically-impossible fused steps in
an early worked-routine draft (a read fused with the `MAR` load that addressed it; a push
driving LEFT from two registers at once) — corrected in microcode.md §5.
**Alternatives weighed (the width curve):**
- **48 bits / 6 chips — rejected.** Reaching 48 needs a multi-format vertical overlay;
  hand-assembly measured indexed loads/fetch free but indexed stores/calls/IRQ ~1.3–1.45×
  and tight microcoded **loops ~2.1–3×** (the loop body splits across three
  mutually-exclusive formats — ~3× on the kernel's `copyin`/`copyout`), plus a loss of the
  self-describing word and two correctness holes. A bad trade against G2/G3/G5/G6 for
  chips the goals do not reward.
- **56 bits / 7 chips — rejected.** Reachable only by re-opening the `FETCH`/`JSR`/push
  splits a wider word avoids.
- **64 bits / 8 chips — evaluated and superseded.** A single-overlay word (a `FORMAT` bit
  re-reading the idle ALU-operand bits as the far-branch/special window, plus a 4-bit
  flag-class PLA) hits every hot path and loop at baseline speed in 8 SRAMs — the
  minimum-compromise point. But it spends two things on legibility (the dual-use window
  and the flag PLA) and leaves zero slack, so a new control primitive would need hardware
  not a reflash. Since part count is a non-goal and the chip budget could move to 10, 80
  bits buys both back (de-overlay + per-flag visibility + the `PC`-direct path + headroom)
  for two SRAMs the priority order does not penalise.
- **96 bits — the first draft.** Over-wide (generous slack, redundant `ALU_CIN_SRC`,
  separate `MEM_REQ`/`MEM_DIR`/`MDR_SRC`); tightened where it cost nothing (`MEM_OP`
  merge, `ALU_CIN` dedup, imm8-only MMU slot, hardware-wired `M`/`I` protection and
  bus-grant tri-state).
- **Two-level nano-store and per-word explicit next-address** — rejected (more total chips
  + a lookup stage; or 8 bits/word for only "go to named successor"), against
  R-CLK-2/R-CTRL-2 and D-24.
- **Magic-1 cross-check** (non-normative): Bill Buzbee's 40-bit / 512-word TTL control
  store independently validates opcode-as-direct-microaddress with no mapping PROM (D-24)
  and the asymmetric narrow-RIGHT + constant-generator datapath; its narrowness comes from
  doing materially less per microword (4-bit ALU, no off-bus counters, simple flags) on a
  slower machine, so it is not evidence BLIP's width is bloated — width tracks datapath
  richness, depth tracks ISA breadth.
- **Scratch: keep two, commit later.** The canonical set omits the routines that
  classically force two live operands (`anyreg OP anyreg` staging, `MUL`, cross-map copy);
  the second scratch costs only a `RIGHT_SRC` code, a `Z_DEST` code, and one register, and
  removing it later is free while adding it later is not — so retain it until those are
  hand-assembled (matches the D-36 / hardware.md §2 open note).
**Process:** designed and adversarially validated by multi-agent workflows
(enumerate → competing formats → hand-assembled microroutine validation → judged against
the goal ordering), with explicit cost/value passes at each width fork; the field set and
80-bit width are the synthesized result, the width confirmed by Ben.
**Notes:** `WIDE_TARGET` stays sized to the actually-placed microcode (the on-hand WCS
SRAM is 8K×8 = 4096 words, so depth is ample; microcode.md §7); `TAS_LOCK` is provisioned
pending the isa.md §9 atomicity decision. The exploratory width analyses
(`control-word-field-analysis`, `control-word-48bit-analysis` and their renderings) were
non-normative working notes and have been removed now the width is settled.
**Resolves:** hardware.md §4/§9 control-word width & layout; creates
[microcode.md](microcode.md). **Touches:** hardware.md §4/§8/§9.

## D-39 — Control word restructured into two clean sections (sequencer + datapath)
**Status:** Decided (2026-06-20) — refines D-38 (the 80-bit single-overlay word, left
frozen as committed history).
**Context:** D-38's 80-bit word packed sequencing and datapath bits together: a
`FORMAT`-overlaid 9-bit window held either the far-branch target (`WIDE_TARGET`) or the
`CC`/MMU "SPECIAL" controls, and branching used a near/far pair (`UBR_NEAR` common + the
overlaid `WIDE_TARGET`). The requirement: (a) a strict separation between the bits that
drive internal microsequencing and the bits that drive the datapath — no field doing both;
and (b) a single next-address field plus one condition-select, one condition-polarity, and
one microsequencer-opcode field, with `NEXT_ADDR` 12 bits wide (4096-word store); budget up
to 12 SRAMs.
**Decision:** Restructure the control word into **two clean, chip-aligned sections with no
field shared**, totalling **88 bits / 11 WCS SRAMs**:
- **Sequencer section — 24 bits / 3 SRAMs (chips 0–2):** `USEQ_OP` (3), a single
  `NEXT_ADDR` (12), `UCOND_SEL` (4), `UCOND_POL` (1), `ULOOP_CTRL` (2), + 2 spare. The
  bits that sequence the microprogram — next-address selection plus the loop counter whose
  terminal-zero feeds the `loop-zero` condition.
- **Datapath section — 64 bits / 8 SRAMs (chips 3–10):** every field that drives a
  register/bus/ALU/memory/flag/MMU (59 used + 5 spare), now including the former overlay
  "SPECIAL" controls (`CC_WRITE_SRC`, `CC_MI_LOAD`, `MMU_PT_OP`) as plain always-present
  fields.
The near/far branch pair collapses to the single 12-bit `NEXT_ADDR`; `FETCH_ENTRY_SEL` is
removed as a control-word field, trap entry being selected by a fixed **hardware priority
encoder** (NMI > IRQ > SWI > illegal > privilege) that intercepts `RETURN_FETCH`. No
overlay, no `FORMAT` bit. Full layout in [microcode.md](microcode.md) §3; supersedes
D-38's structure and width.
**Why:**
- *Clean delineation.* Separating sequencer bits from datapath bits onto a chip boundary
  makes the two concerns independently legible and reasoned about (G5/G6) and removes the
  one place D-38 re-read bits under a selector. It is the structural form of G8's
  "fixed substrate, ISA in microcode": the sequencer is one well-bounded block.
- *The near/far split was an overlay artifact.* It existed only because D-38's far target
  shared the ALU-operand bits; with a dedicated sequencer section the single 12-bit
  `NEXT_ADDR` is always present, so **any** branch co-occurs with a full datapath op —
  strictly more capable than D-38 (every branch, not just near) and simpler (one target).
- *12-bit next-address* gives a 4096-word microprogram store, matching the on-hand 8K×8
  WCS SRAM depth.
- *Cost accepted and small.* 11 SRAMs vs D-38's 10 — about +3 ICs (one WCS SRAM + one
  pipeline `'574` + one boot-image plane). Part count is a non-goal, so this spends nothing
  the priority order rewards while buying the separation, the uniform next-address, and the
  depth.
**Alternatives weighed:**
- **12 SRAMs / 96 bits** (a 9th datapath SRAM for ~11 spare bits of reflash headroom) —
  offered, declined for the leaner 11-SRAM minimum; the design fits cleanly in 11 with
  byte-aligned sections, and each section already carries some spare.
- **Keeping D-38's overlay (80 bits / 10 SRAMs)** — rejected: it mixes the two concerns
  and forces the near/far split, the things this change removes.
- **`FETCH_ENTRY_SEL` as a sequencer field** — rejected: the sequencer section is exactly
  the four requested fields, so trap-entry selection moves to fixed hardware (a priority
  encoder), where D-38 had already placed the gating ("boundary microconditions").
**Notes:** `NEXT_ADDR` is the branch/jump target and doubles as the `DISPATCH_POSTBYTE`
base (the postbyte mode is OR'd into its low bits). `UCOND_SEL` (4) + `UCOND_POL` (1) cover
16 base conditions × both senses (32) — the 16 ISA `Bcc` conditions and their complements —
in one self-contained field, not borrowing the `IR` nibble. The micro-loop counter
`ULOOP_CTRL` sits in the sequencer section, not the datapath one — its terminal-zero feeds
`UCOND_SEL`, so it is a sequencing aux. The trap-vector priority
encoder's exact priority order and entry placement are deferred to the interrupt-controller
/ debug-interface work (microcode.md §7). **Touches:** microcode.md (full),
hardware.md §4/§8/§9.

---

## Pending (not yet decided)

Tracked in the docs' own "Open questions" sections; the load-bearing ones:

- **Datapath detail** — pipeline depth and ALU part choice (the high-level datapath is
  decided — D-34; the microcode control-word format is decided — D-38, restructured into
  two clean sections by D-39 / [microcode.md](microcode.md)).
- **Debug interface spec** — the privileged front-panel signal list (functional
  interface now done — D-29 / [interface.md](interface.md)).
- **Step-3 retrofit** — scrub remaining architecture names from the normative
  parts of isa/hardware/README into *Influences* sections.
