# PLAN — Front panel: a privileged debug console + a functional switch/light I/O port

> **Status: TEMPORARY / NON-NORMATIVE / WORK-IN-PROGRESS planning document.**
> This is an **interim** spec — the front-panel design is **still being actively
> developed** and the control/display set below **will change**. It lives outside the
> three-tier justification chain ([AGENTS.md](../../AGENTS.md)) and **justifies nothing
> on its own**; it records a converging direction so it is not lost. Nothing here is
> ratified. When it settles, its content is promoted into [hardware.md](../hardware.md)
> (a rewrite of §6, "Front panel & bus mastering"), into
> [decision-log.md](../decision-log.md) (a new decision), and the still-deferred
> **privileged debug interface** ([interface.md](../interface.md) §7, [D-13](../decision-log.md))
> is specified from the signal bill in §8; this file is then deleted. Drafted 2026-06-25.
>
> **One-line summary:** because every architectural register now lights its own value
> in place on its own board ([cpu-physical-construction.md](cpu-physical-construction.md)
> §6.2/§6.4), the panel **re-displays no register**. It is re-aimed at the jobs nothing
> else can do — be the **physical bus master**, the **run/stop/clock/step control head**,
> and the **observer of state that has no board** — and it additionally carries a small,
> electrically separate **functional switch/light I/O port** on the system bus.

---

## 0. Scope & status

This document specifies the **front panel** and, as a by-product, the **signal bill the
privileged debug interface must carry** (§8). It supersedes, when ratified, the tentative
front-panel design in [hardware.md](../hardware.md) §6 — in particular it **retires the
shadow-register scheme** there (§7, §11).

**What is decided-so-far vs open.** §3–§6 (the switch banks, console controls, clocking,
and the functional I/O port) record the **user's interim decisions** and are the firm core.
§7 (observation displays) is **recommended but not yet decided**. Every numeric particular
(switch counts aside) — pin budgets, the debug-ribbon width, display groupings — is an
**estimate pending schematic + simulation**. The whole document is provisional and named as
such.

**Two pivots it rests on (both from elsewhere, not re-argued here):**

1. **Registers self-display.** Each register board carries LEDs on its real `'163` outputs
   ([cpu-physical-construction.md](cpu-physical-construction.md) §6.2/§6.4), so the panel
   need not mirror `D X Y USP SSP PC MAR CC IR MDR`. This is what frees the panel to be a
   *control + non-register-observer* console rather than a register display.
2. **The reset memory map.** [D-31](../decision-log.md): reset enters at physical
   `0x000000` (boot ROM), RAM begins at `0x004000`, translation comes up as the identity
   map of the low 64 KB. This is what shapes the bootstrap flow (§9).

---

## 1. The pivot: what the panel is for

With registers self-displaying, the panel does exactly the things that have no other home:

- **(a) Physical bus master** — halt the CPU, take the system bus via `/BUSREQ`÷`/BUSGRANT`,
  and **examine/deposit/bootstrap** memory by hand (`R-DBG-2`, `R-DBG-3`, `R-IF-4`).
- **(b) Run/stop/clock/step control head** — gate and select the CPU clock; advance by one
  instruction or one microstep (`R-DBG-4`).
- **(c) Observer of state with no board** — the byte in flight, the panel's own address
  cursor, the shared LEFT/Z buses, and the live micro-sequencing (`µPC`, `USEQ_OP`, the
  branch decision, traps) that lives on the sequencer board and lights up nowhere
  (`R-DBG-1`, `R-DBG-5`).

The guiding rule: **the panel instruments what the machine is *doing*, not what its
registers *hold*.**

It additionally carries one thing that is **not** a debug function at all — a small
functional switch/light I/O port (§6) — which shares the physical panel but not the
electrical boundary (§2).

---

## 2. Two electrically-separate subsystems on one board

The panel board hosts two unrelated subsystems. Keeping them electrically distinct is a
**requirement-level cleanliness point**, not a layout nicety:

| | **(A) Privileged debug console** | **(B) Functional switch/light I/O** |
|---|---|---|
| Connects via | the **privileged debug interface** (`R-DBG-5`) + bus-master arbitration (`R-IF-4`) | the **functional system bus**, like any peripheral, in the I/O page ([D-28](../decision-log.md)) |
| Carries | bus mastering, run/stop/clock/step, examine/deposit, LOAD-PC, EXECUTE, RESET, observation taps | 8 sense switches (input), 8-bit output → 2-hex display |
| Justified by | `R-DBG-1…5`, `R-IF-4` | a programmer's console I/O convenience; reached by ordinary load/store |
| Boundary rule | the **sole** party allowed past the functional boundary (`R-DBG-5`) | **must not** touch the debug interface — `R-IF-1`/`R-DBG-5` forbid any functional peripheral on it |

So subsystem (B) attaches to `D[7:0]`/`A[…]`/`/RD`/`/WR` at two I/O-page addresses exactly
as a UART would; it has **no** connection to the debug ribbon. This is the load-bearing
reason they are described separately throughout.

---

## 3. Switch banks (entry)

Three independent toggle banks:

| Bank | Width | Role |
|---|---:|---|
| **Address** | **24** | dial `A[23:0]` for examine/deposit; its **low 16** are the logical address LOAD-PC writes to `PC` (§4) |
| **Deposit-data** | **8** | the byte DEPOSIT / DEPOSIT-NEXT writes — a **dedicated** bank (kept separate from the address switches so all 24 stay address, and separate from the sense switches so the I/O port and the console don't share state) |
| **Sense** | **8** | a functional input port the running program reads (§6) — **not** part of the console |

---

## 4. Console controls (subsystem A)

| Control | Type | Behaviour | Serves |
|---|---|---|---|
| **EXAMINE** | momentary | cursor ← address switches; bus-read at cursor; latch to data readout | `R-DBG-2/3` |
| **EXAMINE-NEXT** | momentary | cursor ← cursor + 1; read; latch | `R-DBG-2` |
| **DEPOSIT** | momentary | write the deposit-data byte at cursor | `R-DBG-2/3` |
| **DEPOSIT-NEXT** | momentary | cursor ← cursor + 1; write the deposit-data byte | `R-DBG-3` |
| **TAKE-BUS** | maintained | assert `/BUSREQ`; the panel's A/D drivers are **electrically gated by `/BUSGRANT`** so examine/deposit are inert until grant lands | `R-IF-4`, `R-DBG-2` |
| **RUN/STOP** | maintained | pause/continue **in place**; STOP halts at the next instruction boundary (clean frame, so taking the bus is safe) | `R-DBG-4`, `R-DBG-2` |
| **LOAD-PC** | momentary | `PC ← address-switches[15:0]` via the debug interface (a **PC-write**, §8) | `R-DBG-3` |
| **EXECUTE** | momentary | clear halt, drop `/BUSREQ`, run from the current `PC` — a fresh start (distinct from RUN, which resumes in place) | `R-DBG-3` |
| **STEP-INSTR** | momentary | advance exactly **one instruction** (clocks to the next instruction boundary) | `R-DBG-4` |
| **RESET** | momentary | assert `/RESET`: supervisor mode, `/IRQ` masked, identity-map low 64 KB, `PC = 0x000000` ([D-31](../decision-log.md)) | `R-DBG-3`, `R-CPU-7` |

The **single-step microstep pulse** is not a top-level button — it is folded into the clock
selector's SINGLE-STEP position (§5).

**The cursor model.** A panel-internal 24-bit **address cursor** (a loadable `'163`-style
counter) drives the bus during panel access. EXAMINE loads it from the address switches and
reads (so EXAMINE doubles as "load address"); the `-NEXT` variants pre-increment. The
data-readout LEDs (§7) show the last byte read; the deposit-data toggles supply the byte
written.

---

## 5. Clocking & stepping (one subsystem)

The clock selector, RUN/STOP, the single-step pulse, and STEP-INSTR are **facets of one
clocking subsystem** and are designed together.

- **Clock selector (rotary, 3 positions):**
  - **FAST** — the ~10 MHz target crystal; run at speed (`R-CLK-1`).
  - **SLOW** — a low-Hz astable so the buses and `µPC` can be watched changing live
    (`R-DBG-1`'s "free-running … legible"). Feasible because the machine is **fully static
    CMOS** (74AC/HC + SRAM): the clock may be slowed or stopped indefinitely with no state
    loss.
  - **SINGLE-STEP** — the CPU clock advances **only on a manual pulse**. The
    **single-step PULSE button** (the former "step-µ" / manual pulse, now folded here)
    issues exactly **one CPU clock = one microstep** per press (`R-DBG-4` "preferably per
    microstep").
- **RUN/STOP** gates the free-running source (FAST/SLOW) to the CPU; in SINGLE-STEP the
  source *is* the pulse button, so the machine is inherently stopped between presses.
- **STEP-INSTR** advances one full instruction whenever the machine is not free-running
  (STOPped, or in SINGLE-STEP): it issues clocks until the instruction boundary.
- **EXECUTE** starts the program from `PC` under whatever the selector currently is.

**Why one pulse = one microstep.** The control word is registered (the 88-bit pipeline
register, [microcode.md](../microcode.md) §3), so each CPU clock presents one new microword
and advances `µPC` one step. A manual clock pulse and a "microstep" are therefore the same
operation — which is exactly why the former step-µ button collapses cleanly into the
selector's SINGLE-STEP pulse rather than being a separate control.

**The instruction boundary is the FETCH entry, not `DISPATCH_IR`.** STEP-INSTR and the
FETCH marker (§7) key off the **fetch-routine entry reached via `RETURN_FETCH`**, *not* off
`DISPATCH_IR`. Two reasons, both from [microcode.md](../microcode.md) §2:

- the `0x80` page prefix **re-runs `DISPATCH_IR`** (with `DISPATCH_PAGE = 1`), so a
  page-1 instruction would otherwise step in **two**;
- a taken trap is steered by the hardware trap-vector encoder at `RETURN_FETCH` to a trap
  entry **without** passing through `DISPATCH_IR`, so a trapped instruction would miss a
  `DISPATCH_IR`-keyed boundary.

Keying on the FETCH entry makes one press = one architectural instruction in both cases.

This needs, from the debug interface (§8): an **external `µPC` advance/clock-enable gate**
(the panel cannot reuse `USEQ_OP = WAIT` — that micro-op is written by the *microcode*, not
the panel) and an **instruction-boundary detect** line.

---

## 6. The functional switch/light I/O port (subsystem B)

A small console I/O device on the **functional** bus (not the debug interface, §2):

- **Sense switches** — the 8-switch sense bank (§3) presented as a **read-only** byte at one
  I/O-page address; the running program reads switch settings with an ordinary load.
- **Output port** — an **8-bit** write-only register at one I/O-page address, displayed on a
  **2-digit hex** readout; the program writes it with an ordinary store. *(Reduced from the
  earlier 16-bit/4-digit idea — one byte, two hex characters, one bus write.)*

Both live in the I/O page (`0x00E000–0x00FFFF`, [D-28](../decision-log.md)). **Open:** the
two specific I/O-page addresses (§10).

---

## 7. Displays / observation (recommended — NOT yet decided)

Register *values* are read on the boards, not here (the pivot). What the panel should add —
the state with no board — is recommended below but **still open**; none is user-ratified.

| Display | What | Serves |
|---|---|---|
| **`µPC` (12) + FETCH marker** | `µPC` (12-bit, [D-49](../decision-log.md), 3 nibble groups) + a lamp on the fetch boundary (§5). The only locator of where you are in microcode, and what makes STEP-INSTR observable. | `R-DBG-1/4/5` |
| **Data-readout (8)** | the byte EXAMINE last read — memory has no board to light it | `R-DBG-1/2` |
| **Address cursor (24)** | the panel's auto-incrementing cursor (§4) — panel state, no board shows it | `R-DBG-1/2/3` |
| **LEFT + Z buses (2 × 16, latched)** | snapshot at quantum-end, Z-over-LEFT; + a Z-WRITE pip (OR of decoded load strobes) to tell a held value from a fresh latch. The "every bus" half of `R-DBG-1`. | `R-DBG-1/5` |
| **LEFT source-ID (~9)** | one lamp per LEFT driver, off decoded `LEFT_SRC` — *which* board drives LEFT this cycle | `R-DBG-1/5` |
| **Sequencer decision** | `USEQ_OP` (8 labeled lamps; a small 4→16 decode is needed for the `UCOND_SEL` field) + two lamps: raw condition vs post-polarity TAKEN | `R-DBG-1/4/5` |
| **Status strip** | RUN / HALT (executed-HALT, ≠ bus-stall) / BUS-GRANT / WAIT / TRAP-PENDING | `R-DBG-1/4/5` |
| **Trap-vector dispatch** | the **five** priority-encoder inputs (NMI>IRQ>SWI>illegal>privilege) + TRAP-TAKEN — the one place next-`µPC` is chosen by fixed hardware with no control-word field | `R-DBG-1/5` |
| **Run-time physical address** | `A[23:0]` off the system-bus connector, meaningful **while the CPU runs**: MAR's board shows the *logical* address, this shows the *post-MMU physical* one, so translation is legible | `R-DBG-1/5` |

Further-optional (microcode-development face): `µSR` ([D-42](../decision-log.md) already
earmarks it "readable on the front-panel LED bank"), the `ULOOP` counter + LOOP-ZERO lamp,
the full decoded control-word field bank, the RIGHT bus (needs a **new** ALU-board tap —
RIGHT is deliberately board-local), a force-condition override, and a PC/`µPC` breakpoint
comparator (note: a bare `PC==value` compare can fire in the wrong process, since FUZIX
aliases logical PCs under different maps — `R-MEM-3` — so gate it on `CC.M`/active map).

---

## 8. The privileged debug interface this forces (signal bill)

The panel **is** the forcing function for the deferred debug interface
([interface.md](../interface.md) §7, [D-13](../decision-log.md)). The control/display set
above requires it to carry, at minimum:

**Debug ribbon (subsystem A — privileged, `R-DBG-5`):**

- **`PC`-write (16)** — for LOAD-PC. *(The single most load-bearing signal for `R-DBG-3`;
  without it EXECUTE has no target — see §9.)*
- **External `µPC` advance / clock-enable gate** — for the SINGLE-STEP pulse (§5).
- **Instruction-boundary detect** (FETCH entry / `RETURN_FETCH`) — for STEP-INSTR (§5).
- **Run/halt control + halt-at-boundary acknowledge** — for RUN/STOP, and so the panel
  knows it is safe to take the bus.
- **Observation taps** (§7): `µPC`(12) + FETCH; LEFT/Z + decoded `LEFT_SRC`/load strobes;
  `USEQ_OP`, `UCOND_SEL`+polarity+TAKEN; the trap-pending lines; `CC.M`/`CC.I`.

**System-bus side (subsystem A's memory access — arbitrated, `R-IF-4`):** `/BUSREQ`,
`/BUSGRANT`, `A[23:0]` drive, `D[7:0]` in/out, `/RD`, `/WR`, `/RESET`.

**Functional-IO side (subsystem B — ordinary peripheral, separate connector):** the
sense-switch input port and the 8-bit output port, at two I/O-page addresses.

A genuine sub-decision (§10): whether the panel **decodes on-panel** from a wide raw control
word or **taps the already-decoded strobes** ([cpu-physical-construction.md](cpu-physical-construction.md)
§3.3) — this sets the debug-ribbon width.

---

## 9. Bootstrap path & the memory-map reconciliation

The bootstrap loop has to be reconciled against [D-31](../decision-log.md): reset vectors to
`0x000000` (boot ROM, the firmware monitor), and RAM does not begin until `0x004000`. So
"DEPOSIT then RESET" runs the **monitor**, never hand-keyed code. The path that works,
purely from the panel:

1. **RESET** (or STOP) → identity map, supervisor, `PC = 0x000000`.
2. **TAKE-BUS** → wait for BUS-GRANT.
3. Dial a RAM address (`0x004000+`) on the address switches; **EXAMINE** sets the cursor.
4. Set the deposit-data byte; **DEPOSIT** / **DEPOSIT-NEXT** to key the program in.
5. Dial the entry address; **LOAD-PC** (`PC ← switches[15:0]`).
6. **EXECUTE** → release the bus, clear halt, run from `PC`.

Under the reset identity map, physical `0x004000` = logical `0x4000`, so step 5's logical
PC-load lands on the code deposited at the physical address — which is why the **`PC`-write
of §8 is mandatory** for `R-DBG-3` and is the resolution of the gap the earlier (shadow-era)
sketch left open. The address switches are *physical* for examine/deposit and *low-16
logical* for LOAD-PC; in the low 64 KB they coincide, which is exactly the bootstrap regime.

---

## 10. Open questions / still-developing

This list is **expected to grow** — the spec is interim.

1. **The two I/O-page addresses** for the sense-switch input and the output port (§6).
2. **Debug-ribbon width:** decode-on-panel from the raw control word vs tap the
   already-decoded strobes (§8).
3. **The observation-display set (§7)** is entirely unratified — which of `µPC`, LEFT/Z,
   `USEQ_OP`/condition, traps, status, runtime-physical-address are built, and the
   microcode-development face (`µSR`, `ULOOP`, decoded control word, RIGHT, breakpoints).
4. **Retiring the shadow-register scheme** of [hardware.md](../hardware.md) §6 — this plan
   assumes it is fully retired by per-board LEDs (§11); confirm, including whether a
   consolidated **remote** register repeater is wanted for a distant operator station
   (ergonomics, not an `R-DBG` requirement — recommend declining unless demonstrated).
5. **EXECUTE above 64 KB:** LOAD-PC writes a 16-bit logical `PC`; starting above the
   identity-mapped low 64 KB would need MMU setup the panel deliberately avoids. Decide
   whether panel EXECUTE is simply low-64-KB-only (recommended) or more.
6. **Halt-at-boundary semantics during a `/WAIT`-stretched cycle** — confirm STOP/STEP never
   strand a half-finished transfer.
7. **Connector family, pin budgets, LEFT driver strength, display groupings** — all numeric
   particulars, settle in schematic + simulation.

---

## 11. Path to ratification

When this direction settles (named as candidates — **this plan creates none of them**):

| Action | Where | Note |
|---|---|---|
| Rewrite "**Front panel & bus mastering**" | [hardware.md](../hardware.md) §6 | Replace the tentative shadow-register design with this two-subsystem panel. **Delete** the shadow-register bullet and its counter-shadow correctness condition; **delete** the §2/§2.1 "every register write is posted on Z *for the shadow*" justification (re-justify the Z-posting on the **bus display** basis if kept — a single tap, not N shadows). **Resolve** the §6 and §9 "shadow vs multiplexed" open items in favour of: local board LEDs for registers; the panel carries only non-register observation + the bus-master/clock/step controls + the functional I/O port. |
| New **decision** (next free id) | [decision-log.md](../decision-log.md) | "The front panel re-displays no architectural register (registers self-display on their boards); it is a physical-bus-master + run/stop/clock/step console + the observer of non-register state, and additionally hosts a small functional switch/light I/O port on the system bus. The shadow-register scheme of hardware.md §6 is retired." Reason cites `R-DBG-1…5`, `R-IF-4`; records the rejected alternatives (shadow-register bank; consolidated panel register mirror). A display-architecture commitment, so it warrants a D-entry. |
| Specify the **privileged debug interface** | [interface.md](../interface.md) §7 | From the §8 signal bill; confirm the two §7 wish-list items (run/halt state, instruction-fetch marker) are both consumed here. |
| Resolve the construction-doc knob | [cpu-physical-construction.md](cpu-physical-construction.md) §6.4 / §8 #5 | Local board LEDs fully retire the shadow scheme for register values; the panel keeps no register mirror (only the non-register residue). |

Until then, this file is the working reference; on ratification it is deleted (per the
plan-document rule).

---

## Influences / prior art (non-normative — justifies nothing)

Deposit/examine consoles with sense switches, an address/data switch register, and a
program-readable/-writable lights-and-switches I/O port are a long-standing homebrew and
minicomputer-era idea; BLIP's panel is in that spirit. *Historical context only — it is no
part of any justification above, which rests solely on `R-DBG-1…5`, `R-IF-4`, and the cited
decisions.*
