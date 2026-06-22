# PLAN — The CPU's internal motherboard: a flat, respinnable per-function board set

> **Status: TEMPORARY / NON-NORMATIVE planning document.** This is a working
> plan, not a tier-3 spec. It lives outside the three-tier justification chain
> ([AGENTS.md](../../AGENTS.md)) and **justifies nothing on its own**. It records
> a converged design direction so it is not lost, and gives the build something to
> execute against. When its decisions are ratified they move into
> [hardware.md](../hardware.md) (a new "Physical construction" section), into
> [decision-log.md](../decision-log.md) (a new decision), and — for the one durable
> structural commitment — into [requirements.md](../requirements.md) as a candidate
> `R-HW` requirement; this file is then deleted. Drafted 2026-06-21.
>
> **One-line summary:** the CPU is realized as a **flat motherboard** — a *passive
> interconnect plus the control-word decode glue, and nothing else* — into which
> each architectural element (every register, the ALU, the MMU, …) plugs as its
> **own respinnable board** behind a documented connector contract. State lives on
> boards; only glue lives on the motherboard.

---

## 0. Scope: what this covers, and the gap it fills

There are **two distinct physical buses** in the machine, and this document is
about only one of them.

1. **The external / system bus** — the *functional interface* specified in
   [interface.md](../interface.md): `A[23:0]`, `D[7:0]`, the transfer strobes, the
   async control lines. This is where memory and peripherals attach. It is the G7
   boundary (`R-IF-1`), already specified, and **out of scope here**.
2. **The CPU's internal interconnect** — the wiring that joins the datapath
   registers, the ALU, the MMU, the control unit, and the front panel *to each
   other* **inside** the CPU. This is what this document specifies, and we realize
   it as a **flat motherboard**.

**The gap.** No existing requirement governs the CPU's *internal* modular
construction. `R-IF-*` is the *external* boundary; `R-HW-4` (`⟸ G5`) constrains
*what* must be individually observable (registers, ALU, buses) but not *how the
pieces are physically partitioned and joined*. `R-SIM-3`/`R-SIM-5` and `D-45`/`D-46`
fix the *simulation* and *repository* structure (one cell = one chip, `hdl/` is the
netlist, `hw/<board>/` holds boards) but stop short of a physical-partition policy.
This plan proposes that policy. Where it would eventually need a normative anchor it
**names candidates** (see §9) and stops — per the plan-document rule, it creates no
requirement IDs and no decision-log entries.

**Status of the content.** The partitioning principles, the topology, and the
board inventory are converged. Everything numeric below — pin counts, tap counts,
chip counts, termination values — is **engineering estimate pending schematic and
simulation**, and is flagged as such. The biggest single unknown that gates the
motherboard's width, the datapath bus count (LEFT/RIGHT/Z widths,
[hardware.md](../hardware.md) §9), is **still open** and called out in §8.

---

## 1. Motivation & principles

### 1.1 Why a flat motherboard at all (the goal-driven part)

The defining property of BLIP's construction is that **the whole CPU is visible at
once, with nothing buried.** That is not an aesthetic preference; it is what `G5`
and `G6` demand, and those two goals **outrank** the interface (`G7`), the
microcode realization (`G8`), and the clock (`G9`) in the priority order
([goals.md](../goals.md) §2).

- `R-HW-4` (`⟸ G5`): every register, the ALU, and the internal buses must be
  **individually-observable discrete components** — not collapsed into addressed or
  time-multiplexed storage. You can point at each one.
- `R-DBG-1` (`⟸ G6`): every bus and architectural register must be **continuously
  displayable** in a stable, legible form, free-running or stopped.

A **flat motherboard** — boards lying flat in a plane, plugged into a base board —
serves both directly: every board's parts and LEDs are in view simultaneously, none
hidden behind another. A *vertical card stack* would bury all but the edge of each
card; it optimizes for density (a non-goal — [goals.md](../goals.md) §3) at the cost
of the legibility `G5`/`G6` exist to protect. So the orientation decision falls out
of the priority order, not out of taste.

There is a real **electrical bonus**, which counts as independent technical merit
(`R-CLK-1`): a flat base board lets the shared data-plane traces (§3) be **short,
straight, controlled-impedance, and end-terminated**. A slotted backplane forces
every signal through a connector and down a stub at each slot, and those stubs are
reflection sources. A flat board can keep the bus a clean transmission line and put
the connector stubs *off* the through-line, which helps at the ~10 MHz target.

### 1.2 The clean line: state on boards, glue on the motherboard

The single rule that makes everything else fall into place:

> **Anything stateful or functional lives on its own board. The motherboard is
> passive interconnect plus the control-word decode glue, and nothing else.**

- Every **architectural and working register** (`D`, `X`, `Y`, `USP`, `SSP`, `PC`,
  `MAR`, `CC`, `IR`, the scratch registers), the **ALU**, and the **MMU** — anything
  `R-HW-4` names, plus anything that holds state — is on a board.
- The motherboard carries the **buses**, the **clock tree**, the **reset/global**
  net, the point-to-point links, **and the control-word decoders** — and that is
  all. It holds **no architectural state.**

Why are the decoders allowed on the otherwise-passive motherboard? Because they are
**glue, not architectural state.** `R-HW-4` governs the *registers, the ALU, and the
buses* — not the combinational fan-out that turns a control field into per-resource
strobes. Those decoders were always going to exist (the control word is horizontal;
"one decoder per binary-encoded field" is intrinsic to the design — see
[microcode.md](../microcode.md) §3). They steer signals; they remember nothing. So
they sit comfortably on the interconnect without making it "stateful," and putting
them central (§3.3) is what keeps each board's connector narrow. The line is sharp
and easy to police: *if it latches or computes a datapath value, it is a board; if
it only routes or decodes a control field, it may be motherboard glue.*

### 1.3 The per-board connector contract = `G7`, applied internally

`G7` is "a defined CPU/system interface": revise the inside freely as long as the
boundary holds. We apply the **same discipline one level down.** Each board exposes a
**documented connector** — pinout, signal list, and timing — that it must honor.
Behind that connector you may respin the board's internals at will (change part
choices, re-lay it out, fix a bug) and nothing else needs to move, exactly as a
peripheral is insulated from CPU-internal change by `R-IF-6`. **The motherboard is
the stable internal interface; the connector contracts are its clauses.**

This is a *plan-level* application of the `G7` discipline, not a claim on `R-IF-*`
(which is, and stays, the external boundary). It is the internal analogue, and it is
why the work is tractable: the boards can be designed, simulated, and cut largely
independently once their contracts are pinned.

### 1.4 Board boundaries mirror `hdl/` module boundaries

The physical partition is **not invented**; it tracks the structure the simulation
already enforces (`D-45`, `D-46`, `R-SIM-3`, `R-SIM-5`):

- a **board** = an `hdl/` module (a register board ⇔ the register module, the ALU
  board ⇔ the ALU module, …);
- the **motherboard** = the **top-level netlist** rendered in copper — the wiring and
  the decode glue that joins the modules;
- a **respun board** = a re-implemented `hdl/` module behind the **same ports**;
- the **simulator proves the contract** (ports + timing) **before any board is cut.**

This keeps the two sources of truth ([hdl/](../../hdl), [microcode/](../../microcode))
authoritative over the copper: `hw/<board>/` is a *realization* of an `hdl/` module,
and the structural-only gate (`D-46`, `R-SIM-5`) guarantees the simulated module is
buildable from real chips in the first place. The netlist is the BOM; the board is
that BOM laid out.

---

## 2. Two buses, kept distinct

To keep §0's distinction concrete, here is the boundary in one table. The
motherboard hosts the left column; the right column is `interface.md`'s and only
ever appears at the south edge of two boards (the MDR/bus-interface board and the
MMU board, §5).

| | **Internal interconnect** (this doc — the motherboard) | **External / system bus** ([interface.md](../interface.md)) |
|---|---|---|
| Carries | LEFT, Z; decoded control strobes; clock tree; reset; the point-to-point links (§3.5) | `A[23:0]`, `D[7:0]`, `/RD`, `/WR`, `/WAIT`, `CLK`, `/RESET`, `/IRQ`, `/NMI`, `/BUSREQ`, `/BUSGRANT` |
| Width / role | datapath-internal; **width TBD** with the LEFT/RIGHT/Z bus count (§8) | 24-bit physical address + 8-bit data; fixed (`R-IF-2`) |
| Who attaches | only CPU boards | memory, I/O peripherals; the front panel reaches memory here via `/BUSREQ`/`/BUSGRANT` (`R-DBG-2`) |
| Stability anchor | the per-board connector contracts (§1.3) — *plan-level* | `R-IF-6` (normative) |
| Where they meet | — | at the **south edge** of the MDR board (`D[7:0]`) and the MMU board (`A[23:0]`) — **not** across the CPU motherboard |

The external `A`/`D` deliberately **leave south to the system bus** rather than
traversing the CPU motherboard: the MMU emits the physical address `A[23:0]` at its
own south edge, and the MDR/bus-interface board drives/receives `D[7:0]` at its own
south edge (§5). The motherboard's bus plane is the *internal* LEFT/Z only.

---

## 3. Interconnect topology — a hybrid, not all point-to-point

The datapath is a **bus architecture** by decision: `D-34`/`D-35` settled that *any*
register may drive **LEFT** and *any* register may latch **Z**. Forcing the internal
interconnect to be fully point-to-point would require a central crossbar to preserve
"any-to-any," which is **more chips and less legible** — directly anti-`G5`. So the
topology is a **deliberate hybrid**, matched to how each signal class actually
behaves.

| Signal class | Topology | On the motherboard? | Rationale (IDs) |
|---|---|---|---|
| **Data plane — LEFT + Z** | shared bus, controlled-impedance, end-terminated | **Yes** — the bus plane | `D-34`/`D-35` (bus datapath); legibility `G5`; `R-CLK-1` (clean line) |
| **RIGHT** | local to the ALU board | **No** — never reaches it | `D-34`/`D-35` (only scratch + const-gen drive it); §3.2 |
| **Control** | central decode; only decoded strobes fan out | **Yes** — the decoders | `R-CTRL-4` (fixed substrate); `R-HW-4` (decoders = glue); §3.3 |
| **Clock** | star, length-matched | **Yes** — the clock tree | `R-CLK-1` (skew at ~10 MHz) |
| **Reset / global** | broadcast | **Yes** | skew-tolerant; `R-CPU-7` |
| **Point-to-point / cluster** | dedicated links / ribbons | partly (see §3.5) | locality of each link |

### 3.1 Data plane: LEFT + Z (shared, on the motherboard)

LEFT and Z are the shared datapath buses, and they live on the motherboard as a
controlled-impedance, **end-terminated** transmission line that visits each datapath
board in turn. Width is the sum of the LEFT and Z widths — **TBD** until the bus
count is fixed (§8); on the current 16-bit-core direction that is on the order of
**32 lines** (16 + 16) plus termination.

The loading on the two is **asymmetric**, and this matters for who pays the timing
cost:

- **Z is a cheap broadcast.** The ALU drives Z; every register *receives* it into
  high-impedance latch inputs. Many receivers on a driven line are electrically easy
  — input capacitance, not contention.
- **LEFT is the load to watch.** Every register can *drive* LEFT, so LEFT carries
  **many tri-state drivers** (one per source board). Tri-state drivers are the real
  load — bus capacitance, leakage, and turnaround all scale with driver count. LEFT,
  not Z, is what pulls against the clock (§7).

### 3.2 RIGHT stays local to the ALU board (off the motherboard)

RIGHT is the ALU's right input, and by `D-34`/`D-35` its **only** drivers are the
scratch registers (`SCR1`/`SCR2`) and the constant generator `{-2..+2}`, and its
**only** consumer is the ALU. All of those live on the **ALU board** (§5). So RIGHT
is an entirely **on-board** net: it never appears on a connector and never reaches
the motherboard. This is a direct payoff of the asymmetric-bus decision — the
sparsely-driven source bus costs the interconnect nothing.

### 3.3 Control: decode centrally, fan out only decoded strobes

The 88-bit registered control word ([microcode.md](../microcode.md) §3) comes off
the control-store board to the motherboard. The motherboard's **decoders** (one per
binary-encoded field) turn it into **per-resource strobes**, and **only the strobes a
given board needs fan out to that board** — its load enables, its drive-LEFT enable,
its ALU-op lines, etc.

**There is no wide control "bus" into the modules.** An earlier idea — broadcast all
64 datapath-section bits to every board and let each board decode locally — was
**rejected**: it made even a two-register board need ~100 pins (64 control + 16 Z + 16
LEFT + clock/reset/power), the connector dwarfing the board. Central decode collapses
each board's control footprint to a handful of decoded enables (see the register-board
budget, §6.3).

**Central decode costs zero microcode flexibility.** The field→resource wiring is
**fixed substrate** by `R-CTRL-4`: the control word "shall expose every primitive …
so that no instruction's behaviour depends on fixed, instruction-specific logic," and
the substrate is *bounded and fixed* — `G8` flexibility lives in the **contents** of
the writable control store, not in the decode wiring. Decoding `LEFT_SRC=D` into "D
drives LEFT" centrally vs on D's board changes nothing about what microcode can
express; it only moves where the (fixed) decode happens. So the central decoder is
the natural home for it.

**Bonus:** the decoded **load strobes** are *exactly* what the front panel wants to
observe (`R-DBG-1`, `D-13`) — "this register just latched" is a decoded strobe, and
the panel taps the same lines (§5, front panel; §6.4).

### 3.4 Clock and reset

- **Clock — star distribution, length-matched.** At ~10 MHz with fast ACT edges,
  **skew matters** (`R-CLK-1`). A star from a central clock driver, with
  length-matched legs to each board's clock pin, keeps the edges aligned across the
  machine. (Single- vs multi-phase, and fixed vs stretchable, are open —
  [hardware.md](../hardware.md) §5; see §8.)
- **Reset / global — broadcast.** `/RESET` and any other global async lines are
  **skew-tolerant** (they gate a deterministic power-on state, `R-CPU-7`, not a timed
  edge race), so a simple broadcast net suffices.

### 3.5 Point-to-point and cluster signals

Some signals are inherently local and are routed as dedicated links rather than onto
the shared plane:

| Link | Width (est.) | Endpoints | Notes / IDs |
|---|---:|---|---|
| **Logical-address bus** | 16 | `PC`/`MAR` → MMU | **off-bus** per [microcode.md](../microcode.md) §5 (`translate-PC` / `translate-MAR`); clusters physically with the MMU (§5) |
| **Flags** | ~8 | ALU → CC → sequencer | `N Z V C` + half-carry; CC then feeds the sequencer's condition mux ([microcode.md](../microcode.md) §2) |
| **Control-unit hot ribbon** | ~37 | control-store board ↔ sequencer board | `µPC` (13) + the 24-bit sequencer-section word; the runtime sequencing path (§5) |
| **External address** | 24 | MMU → **south** to system bus | `A[23:0]`; **leaves the CPU**, not across the motherboard (§2) |
| **External data** | 8 | MDR board ↔ **south** to system bus | `D[7:0]`; the MDR board is the boundary (§2) |

The logical-address link is the reason `PC`/`MAR` cluster physically with the MMU:
the MMU translates `MAR` (or `PC`, for an off-bus stream fetch) without a `PC→MAR`
copy ([microcode.md](../microcode.md) §5), so those three boards want to be neighbors
with a short dedicated 16-bit path between them.

---

## 4. The motherboard's own contents

Pulling §1–§3 together, the motherboard carries exactly these, and **no architectural
state**:

1. **The LEFT + Z bus plane** — controlled-impedance traces with end termination,
   tapped by each datapath board (§3.1, §7).
2. **The control-word decoders** — one per binary-encoded field, fanning **decoded
   per-resource strobes** to the boards that need them, and **to the front-panel tap**
   (§3.3).
3. **The clock tree** — a length-matched star from a central driver (§3.4).
4. **The reset / global broadcast net** (§3.4).
5. **The dedicated point-to-point / cluster links** of §3.5 that happen to run board-
   to-board (the logical-address path, the flags path; the hot ribbon may be a direct
   board-to-board ribbon rather than a motherboard trace — schematic detail).
6. **Board connectors** — the physical sockets the boards plug into, each wired to the
   contract of §5/§6.

It explicitly does **not** carry: any register, the ALU, the MMU table, RIGHT, the
external `A`/`D` through-traffic (those go south, §2), or any latch holding a datapath
value.

---

## 5. Board inventory & per-board connector contracts

The CPU partitions into the boards below. Each row's "connector (contract)" is the
**documented interface** of §1.3 — the stable clause the board must honor; its
internals are respinnable behind it. Pin counts are **estimates** pending the bus
count (§8) and schematic.

| Board | `hdl/` module (mirror) | Holds (state / function) | Connector contract (signals; est. pins) | Realizes / IDs |
|---|---|---|---|---|
| **Universal 16-bit register** (×5 — `D`, `X`, `Y`, `USP`, `SSP`) | register | a 16-bit register as a `'163`-counter superset (§6) | Z-in 16, LEFT-out 16, {drive-LEFT, load-lo, load-hi, count} EN, CLK, `/RESET` — **~38** | `G5`/`R-HW-4`; `D-36`; `G7`-internal |
| **PC/MAR** (different form factor) | register (counter core) + addr port | `PC`, `MAR` (counter core) + a 2nd output port to the MMU | register-board contract **+** logical-addr-out 16 + the MMU-drive EN per register | `D-36`; [microcode.md](../microcode.md) §5; clusters w/ MMU |
| **ALU** | alu | 16-bit ALU + const-gen `{-2..+2}` + `SCR1`/`SCR2` + flag gen; **RIGHT local** | LEFT-in 16, Z-out 16, decoded ALU ctrl (`ALU_OP`/`ALU_SHIFT`/`ALU_CIN`/`ALU_WIDTH`, `FLAG_WE`, `V_SRC`, `C_SRC`, `RIGHT_SRC`), flags-out ~8, CLK, `/RESET` | `G2`/`G9`; `R-CTRL-4` |
| **CC** | cc | the 8-bit `CC` (`M – H I N Z V C`) | LEFT-in/Z (8), flags-in ~8 (from ALU), decoded `CC_WRITE_SRC`/`CC_MI_LOAD`/`FLAG_WE`, `CC.M`-out (to SP-bank decode, MMU map-sel, sequencer), CLK, `/RESET` | `R-CPU-1`/`-4`/`-6`; not the 16-bit form factor (8-bit) |
| **IR** | ir | the 8-bit instruction register | opcode-byte in (from MDR/datapath), `IR[7:0]`-out (→ opcode-LUT on the control-store board), decoded `IR_LOAD`, CLK, `/RESET` | dispatch ([microcode.md](../microcode.md) §2) |
| **MDR / bus-interface** | mdr | `MDR` (8-bit) + external `D[7:0]` buffers — the system-bus boundary | LEFT-in (write path), Z-out (read path), decoded `MEM_OP`/`TAS_LOCK`, **south:** `D[7:0]`, `/RD`, `/WR`, `/WAIT`, CLK, `/RESET` | `R-IF-2` boundary; `D[7:0]` leaves here |
| **MMU** | mmu | page-table register file (kernel+user, 8×11-bit — bulk array, **exempt** from `R-HW-4`) + translate logic + `A[23:0]` drivers | logical-addr-in 16 (from PC/MAR cluster), light LEFT/Z tap (`LDMMU`/`STMMU`), `CC.M`-in (map-select), decoded `MMU_*`, **south:** `A[23:0]`, CLK, `/RESET` | `G3`/`G4`; `R-MEM-1`/`-3`/`-6`; `A[23:0]` leaves here |
| **Control-store + loader** | control-store + boot | 13 SRAMs (11 WCS + 2 LUT) + 88-bit pipeline reg + 13 boot buffers + boot/run addr mux + boot `/WE` decode + socketed EEPROM + loader (§5.2) | `IR[7:0]`-in (LUT index), 88-bit word **out** (datapath section → motherboard decoders; sequencer section → sequencer), `µPC` ↔ hot ribbon, CLK, `/RESET` | `G8`; `D-43`; `R-CTRL-1`/`-2`/`-3` |
| **Sequencer** | sequencer | `µPC` + `µSR` + next-addr mux + condition mux (16:1 + polarity) + `ULOOP` counter + trap-vector priority encoder | hot ribbon ↔ control-store, flags/conditions-in (from CC/ALU), `IRQ`/`NMI`/`WAIT` microconditions-in, CLK, `/RESET` | [microcode.md](../microcode.md) §2; `R-CLK-2` |
| **Front panel** | (debug — `hdl/` top exposes only `R-IF`, so this attaches via the debug tap, not a functional port) | switches + LED banks; the privileged debug observer | Z tap + decoded load-strobe tap (or per-board local LEDs, §6.4), `IR`/`CC`/`µPC` for display, RUN/STOP/EXAMINE/DEPOSIT/RESET, **system-bus** `/BUSREQ`/`/BUSGRANT` for memory access | `G6`; `D-13`/`R-DBG-5`; reaches memory via `R-IF-4` arbitration |

Two clusters fall out of the contracts: **PC/MAR + MMU** (the logical-address path,
§3.5) and **control-store + sequencer** (the hot ribbon, §3.5).

### 5.1 The ALU board (note on the open scratch count)

The ALU board carries the 16-bit ALU, the constant generator `{-2..+2}` (`D-36`),
the scratch register(s), and flag generation; RIGHT is local here (§3.2). It taps
LEFT in and drives Z out, receives its decoded ALU control from the motherboard, and
drives flags to CC and the sequencer. **Open:** one scratch register or two
([microcode.md](../microcode.md) §6/§7) — the canonical ISA set needs only one live
scratch, but a second is retained provisionally; whichever way it settles changes
*only this board* behind its connector, and the connector's `RIGHT_SRC` width already
covers both (`SCR1`, `SCR2`, const).

### 5.2 The control-store + loader board (the dense one) — why the 13 boot buffers

This is the densest board, and one detail drives its part count, so it is worth
stating plainly.

**Why 13 boot-isolation buffers exist.** At runtime all 13 SRAMs drive their **own
private 8-bit data slices simultaneously** to assemble the wide control word — so
their **data pins cannot share a bus.** But at boot they are written from the loader's
**single shared data byte** (`D-43`, chip-major broadcast). Each SRAM therefore needs
a per-SRAM **isolation buffer** (`'244`-class) that drives that byte onto the SRAM's
I/O during boot and goes **high-Z at runtime** so the SRAM drives its own slice
without contention. This is exactly the structure already in the scaffold
([hdl/cpu.v](../../hdl/cpu.v): "13× sn74ahct541 … the EEPROM byte fans out to all 13
SRAMs during boot … tri-stated during run").

**The asymmetry that makes it 13 buffers but no address buffers.** Address pins, by
contrast, **are** shared: they are high-Z *inputs*, and the `µPC` fans to all WCS
chips alike. So **address needs only a mux** (boot counter vs `µPC`), while **data
needs per-chip isolation.** Shared inputs vs private outputs — that single asymmetry
is the whole reason for the 13 buffers, and it is intrinsic to a wide, writable
control store, not a cost of partitioning.

**The boot path is entirely on-board.** Chip-major broadcast write (`D-43`): one
shared boot address + one shared data byte, a decoder strobes one `/WE` at a time, the
boot data is fanned through the 13 buffers (each enable gated by its chip-select). The
boot/runtime **address mux is intrinsic** to a writable control store — it is what
lets `µPC` drive the SRAMs at runtime and the loader drive them at boot — **not** a
cost of board partitioning. The loader was first floated as its own card but is
**folded onto this board** because it is tightly coupled to the SRAMs: it shares their
address bus and drives their buffers and `/WE`. Folding it in means **there is no
"boot ribbon"** — the entire copy is intra-board. **Socket the EEPROM** so that
reflashing the microcode (`R-CTRL-3`) is a *chip pull*, not a board pull.

The board drives the 88-bit word out in two streams: the **datapath section** to the
motherboard decoders (§3.3) and the **sequencer section** to the sequencer board over
the hot ribbon; `µPC` rides that same ribbon; `IR[7:0]` comes in for the opcode-LUT
read.

### 5.3 The sequencer board

Holds `µPC`, `µSR`, the next-address mux, the condition mux (16:1 + polarity), the
`ULOOP` counter, and the **trap-vector priority encoder** ([microcode.md](../microcode.md)
§2). It is joined to the control-store board by the **hot runtime ribbon** (`µPC` + the
24-bit sequencer-section word, §3.5), and takes flags/conditions off the motherboard
(from CC/ALU) plus the `IRQ`/`NMI`/`WAIT` microconditions.

**Open sub-decision (the `µPC` cut).** The leading direction is to keep `µPC`
**adjacent to the WCS** (i.e. physically on the control-store board) so the WCS-access
and boot paths stay local, while the sequencer board holds the **branch/condition
policy** (the muxes, the priority encoder, `µSR`, `ULOOP`). The exact bit-split across
the ribbon is a schematic-level detail. This split is recorded as a knob in §8, not
resolved here.

### 5.4 The front panel (the privileged debug observer)

The front panel is the sole party allowed past the functional boundary (`D-13`,
`R-DBG-5`). Physically it taps the **Z bus** and the **decoded load strobes** (§3.3),
plus `IR`/`CC`/`µPC` for display, and carries the RUN/STOP/EXAMINE/DEPOSIT/RESET
switches. It reaches **memory** not through any internal port but through the
system-bus arbitration handshake (`/BUSREQ`/`/BUSGRANT`, `R-IF-4`, `R-DBG-2`) — the
same way `interface.md` §4.6 describes. See §6.4 for how per-board local LEDs may
change the register-display story.

---

## 6. The centerpiece: the universal 16-bit register board

The highest-leverage board is the **universal 16-bit register** — **one form
factor** that serves **five registers**: `D`, `X`, `Y`, `USP`, `SSP`. Design and
debug it once, fab five, strap none, plug in. A single respin fixes every register at
once. This section specifies it.

### 6.1 The superset idea

The board is built around the off-bus `+1` counter (`D-36`) used as a **superset
storage element**:

- a **counter** does **load-from-Z**, **count +1**, and **hold**;
- a plain **latch** does only **load** and **hold**;
- so a counter is a **strict superset** of a latch.

Build every register from the counter, and the non-counter registers (`D`, `USP`,
`SSP`) simply **never assert count.** One board covers both the registers that need
`+1` off-bus (`X`, `Y` — and the same core serves `PC`/`MAR` on their variant board,
§5) and the registers that do not. Uniformity, bought for the price of a few unused
gates.

### 6.2 Contents

| Part | Qty | Role |
|---|---:|---|
| `74ACT163` (4-bit sync counter, sync load) | **4** | 16-bit storage; synchronous clear on `/RESET`; **independent per-byte load** via the separate `/PE` on the low pair and the high pair |
| `'244` (tri-state octal buffer) | **2** | the **LEFT driver** (gate the value onto LEFT) |
| LEDs | 16 | on the `'163` Q outputs — permanent, legible display (`R-DBG-1`) |

The `'163` outputs are permanent, so the LEDs (and any shadow) read straight off
them. Synchronous clear ties to `/RESET` for the deterministic power-on state
(`R-CPU-7`). The split `/PE` across the low and high `'163` pairs is what gives
**independent per-byte load** — load the low byte, the high byte, or both — which the
accumulator and the byte-cycle memory path both rely on.

### 6.3 Connector contract (~38 pins)

| Group | Lines | Direction |
|---|---:|---|
| Z-in | 16 | in (latch source) |
| LEFT-out | 16 | out (tri-state onto LEFT) |
| drive-LEFT EN | 1 | in (decoded) |
| load-low EN | 1 | in (decoded) |
| load-high EN | 1 | in (decoded) |
| count EN | 1 | in (decoded) |
| CLK | 1 | in |
| `/RESET` | 1 | in |
| **Total** | **~38** | identical on every register board |

The four enables arrive **already decoded** from the motherboard (§3.3) — this is why
the connector is ~38 pins and not ~100. The contract is **identical on all five
boards.**

### 6.4 Why the two "register-specific" features need no special board hardware

Two registers look like they need bespoke hardware. Neither does — both resolve off
the board, which is what lets the form factor stay universal.

**(a) `D`'s `A:B` accumulator lanes.** `D` is the `A:B` accumulator, and 8-bit ops use
its low lane with sign-extension/widening between 8 and 16 bits. It is tempting to
build lane-steering into `D`'s output. But lane **steering** (sign-extend, high→low)
is a **`LEFT_LANE` operation on the operand *entering the ALU*** ([microcode.md](../microcode.md)
§3.2; e.g. the `MDR → sign-ext → SCR1` step in the `LD A,(X+n)` routine, §5). It is
**source-agnostic** — one steer block sits on **LEFT**, in front of the ALU, and works
on whatever drove LEFT — so it is **not** a per-register-output feature. What `D`
actually needs is **independent per-byte load**, and four separate `'163`s with split
`/PE` (§6.2) already provide that. So **`D` needs zero special output hardware.**

**(b) `USP`/`SSP` banking (`ACTIVE_SP`).** The active stack pointer is whichever of
`USP`/`SSP` the privilege mode selects (`CC.M`/`SP_BANK`, [hardware.md](../hardware.md)
§2, [microcode.md](../microcode.md) §3.2). The bank choice is resolved by the
**motherboard decode**: it knows `CC.M` and `SP_BANK` and which physical slot is `USP`
vs `SSP`, and it hands each SP board an **already-bank-resolved enable** (the SSP board
gets the enable when SSP is active, the USP board when USP is active). **No bank logic
lives on the board.** The board is just a register that latches when told to.

**Identity is slot-defined.** Because banking and lane-steering both resolve off-board,
the five boards are **physically identical — even unstrapped.** The motherboard routes
the correct decoded enables to each slot, so a board's **role is where you plug it in.**
(If a later revision wants a board to self-identify for the panel, a slot-strap pin is a
trivial addition to the contract — noted in §8.)

**Per-board local LEDs and the shadow scheme.** Because each board carries LEDs on its
real `'163` outputs (§6.2), you can watch each register's **actual** value directly.
This **may retire the shadow-register scheme** of [hardware.md](../hardware.md) §6
(which had the panel carry shadow latches that listen to Z, precisely to avoid a
per-register display tap). With per-board local LEDs the panel need not shadow the
registers at all — it reads them in place. Whether local LEDs *fully* retire the
shadow scheme (the panel may still want a consolidated remote display, and the counter-
shadow correctness condition of §6 there would simply disappear) is an open knob (§8).

### 6.5 Cost and why it does not disturb `D-36`

**Cost.** About **2 extra chips** on each of `D`/`USP`/`SSP` (a counter where a latch
would have done) plus one dormant `count` line. This is **trivial** under the priority
order — part count is an explicit non-goal ([goals.md](../goals.md) §3), and `G5`/`G6`
(which the uniform, individually-lit board serves) outrank `G9`. The unused counter is
silicon bought for **uniformity**, and it earns its keep in design/debug/respin
leverage.

**It does not disturb `D-36`.** `D-36` decided which registers get an *off-bus
incrementer used for `+1`*: `PC`/`MAR`/`X`/`Y` yes; `USP`/`SSP` no, with their `±1`/`±2`
steps going through the **ALU + constant generator**. That stays exactly true: the
counter present on the `D`/`USP`/`SSP` boards is **never asserted to count** — `SP`
steps still go through the ALU and const-gen as `D-36` requires. The counter is just
*unused silicon* on those boards, present only so the form factor is uniform. The
microarchitecture `D-36` specified is unchanged; only the *board's parts list* is
uniform across roles.

### 6.6 Per-role usage table

| Role | `count` line used? | Per-byte load used? | `+1` source | LEFT/Z | Banking | Lane steering | Special board HW |
|---|:---:|:---:|---|:---:|---|---|:---:|
| **`D` (`A:B`)** | no (dormant) | **yes** (A/B lanes loaded independently) | — (no `+1`) | yes / yes | — | on LEFT (`LEFT_LANE`), source-agnostic | **none** |
| **`X`** | **yes** (byte-ptr `*p++`) | as needed | own `'163` counter (`D-36`) | yes / yes | — | — | **none** |
| **`Y`** | **yes** (byte-ptr `*p++`) | as needed | own `'163` counter (`D-36`) | yes / yes | — | — | **none** |
| **`USP`** | no (dormant) | as needed | ALU + const-gen (`D-36`) | yes / yes | motherboard decode hands bank-resolved EN | — | **none** |
| **`SSP`** | no (dormant) | as needed | ALU + const-gen (`D-36`) | yes / yes | motherboard decode hands bank-resolved EN | — | **none** |

`PC` and `MAR` use the **same `'163` core** on the PC/MAR variant board (§5), with the
`count` line live (~100% `+1`, `D-36`) and a **second output port** to the MMU on top of
the LEFT driver — one design lineage, a different carrier.

---

## 7. The bus-tap budget (the honest cost)

The price of "any register on the bus" is that **every datapath board is a stub on
LEFT/Z.** Counting the taps:

| Tappers on LEFT/Z | Count |
|---|---:|
| Universal register boards (`D`, `X`, `Y`, `USP`, `SSP`) | 5 |
| PC/MAR board (`PC`, `MAR`) | 2 |
| ALU board | 1 |
| MDR / bus-interface board | 1 |
| MMU board (light tap for `LDMMU`/`STMMU`) | 1 |
| CC board | 1 |
| **≈ total** | **~11** |

(IR taps the datapath via MDR rather than directly; the exact count moves with the
final partition and the scratch-count decision, §8.)

**~11 taps is the main thing pulling against 10 MHz.** Each tap adds bus capacitance
and, on LEFT, a tri-state driver (the heavier load, §3.1). This is a **real** cost and
is named as such.

**But the trade is sanctioned by the priority order.** `G9` is the **lowest** goal and
**explicitly yields** (`D-01`; `R-CLK-1`: "the achievable clock is whatever the
critical path supports"). The whole reason the registers are individually visible and
individually tapped is `G5`/`G6`, which **outrank** `G9`. So spending bus margin to buy
legibility is exactly the trade the order rewards — we do not collapse the register set
into a hidden file to go faster.

**Mitigations** (settle in schematic + simulation, §8):

- **controlled-impedance + end-termination** on LEFT/Z (the flat-board electrical bonus,
  §1.1) — tames reflections off the ~11 stubs;
- **strong LEFT drivers** — LEFT is driver-limited (§3.1), so the LEFT `'244`s are sized
  for the loaded line;
- **short connector stubs** — keep each board's tap off the through-line;
- **compact layout** — minimize total bus length.

And the discipline of `R-SIM-1`/`R-SIM-6` means this is **measured, not hoped**: the
timed engine (`D-47`) runs the loaded bus against the target clock before any copper.

---

## 8. Open questions / knobs

Carried forward so they are not lost; none is resolved here.

1. **Datapath bus count (LEFT/RIGHT/Z widths)** — **still open**
   ([hardware.md](../hardware.md) §9). **The motherboard width depends on it**, and it
   also gates the interface timing ([interface.md](../interface.md) §8). This is the
   biggest single dependency for the bus-plane spec (§3.1). *Until it lands, "~32 data
   lines" is a 16-bit-core placeholder.*
2. **Grouping low-interest registers** — e.g. `USP`/`SSP` as **one** board vs fully
   individual boards. Trades **LEFT tap count** (`R-CLK-1`, §7) against modularity (one
   respin per register vs per pair). The universal form factor makes either cheap.
3. **The `µPC` cut** between the control-store and sequencer boards (§5.3) — leading:
   `µPC` adjacent to the WCS, policy on the sequencer; exact ribbon bit-split is
   schematic-level.
4. **Clocking** — single fixed vs stretchable clock; single- vs multi-phase
   ([hardware.md](../hardware.md) §5). Affects the clock-tree spec (§3.4).
5. **Per-board local LEDs vs the shadow-register scheme** (§6.4) — do local LEDs *fully*
   retire [hardware.md](../hardware.md) §6's shadow registers, or does the panel keep a
   consolidated remote display?
6. **One vs two scratch registers** ([microcode.md](../microcode.md) §6/§7) — affects the
   **ALU board** internals only (§5.1); the connector already covers both.
7. **Bus termination scheme, connector family/pin budget, LEFT driver strength** — the
   numeric particulars of §6.3 and §7; settle in **schematic + simulation**.
8. **Board self-identification** — whether a slot-strap pin is added to the register
   contract so a board can name its role to the panel (currently role is purely
   slot-defined, §6.4). A trivial contract addition if wanted.

---

## 9. The plan

### 9.1 Phasing

A staged build that pins the highest-leverage contract first and proves every contract
in simulation before any copper is cut.

1. **Pin the universal register-board connector contract (§6.3) first.** It is the
   **most-replicated** board (five instances, plus a shared core on PC/MAR) and the
   **highest-leverage** — getting its ~38-pin contract right de-risks the largest part of
   the build. Settle the decoded-enable set, the per-byte-load split, and the LEFT/Z pin
   assignment.
2. **Verify that contract in simulation against the existing `hdl` register module**
   (`R-SIM-3`/`R-SIM-5`/`R-SIM-6`, `D-46`) — ports + timing — **before fab.** The board
   is the module; the simulator proves the module is buildable and meets timing on the
   loaded bus.
3. **Pin and verify the other functional boards** — ALU, CC, IR, MDR/bus-interface, MMU,
   PC/MAR, control-store+loader, sequencer — each behind its contract (§5), each proven in
   sim before copper. The control-store+loader board (§5.2) can lean on the existing
   scaffold ([hdl/cpu.v](../../hdl/cpu.v)).
4. **Design the motherboard interconnect** — the LEFT/Z bus plane with termination, the
   central decoders (§3.3), the clock tree (§3.4), the reset/global net, and the §3.5
   links. This is the **top-level netlist rendered in copper** (§1.4). Run the **loaded**
   bus against the target clock on the timed engine (`D-47`, §7) to size drivers and
   termination.
5. **Integration and the front-panel / debug tap** — bring the boards up on the
   motherboard, attach the front panel via the Z + decoded-strobe tap and the system-bus
   arbitration path (§5.4), and confirm `R-DBG-1`/`R-DBG-2` end to end.

### 9.2 Tie to `hdl/`

- **board = `hdl/` module** (§1.4);
- **motherboard = the top-level netlist** (the wiring + decode glue joining the modules);
- **a respun board = a re-implemented module behind the same ports;**
- **contracts proven in simulation before any copper** (`R-SIM-3`/`R-SIM-5`; structural-
  only DUT per `D-46`; timed per `R-SIM-6`/`D-47`).

`hw/<board>/` (schematic / pcb / bom / gerbers) is the *realization* of the matching
`hdl/` module; the netlist stays the BOM (`D-45`).

### 9.3 Path to ratification

When this direction is settled, promote it as follows (named as candidates — **this
plan creates none of them**):

| Action | Where | Note |
|---|---|---|
| New **decision** (next free id) | [decision-log.md](../decision-log.md) | "The CPU is realized as a flat motherboard — passive interconnect + control-word decode glue only — with all architectural state on respinnable per-function boards behind documented connector contracts." Reason = `R-HW-4` (legible, individually-observable components → boards), `R-DBG-1` (continuous display → flat, in-view layout + decoded-strobe tap), `R-CLK-1` (clean terminated bus; the ~11-tap trade sanctioned by `D-01`), and `R-CTRL-4` (central decode is fixed substrate, costs no flexibility). Records the rejected alternatives: vertical card stack (anti-`G5`/`G6`), full point-to-point crossbar (anti-`G5`), wide control-bus-into-modules (~100-pin connectors). |
| New "**Physical construction**" section | [hardware.md](../hardware.md) | The topology (§3), the motherboard contents (§4), the board inventory + connector contracts (§5), and the universal register board (§6). Sits alongside §2 (datapath) and §6 (front panel). |
| **Candidate requirement** `R-HW-5` (`⟸ G5`) | [requirements.md](../requirements.md) | *Anchoring the one durable structural commitment:* "The CPU shall be realized as individually-respinnable per-function boards joined by a passive interconnect motherboard, with all architectural state on the boards and only signal interconnect and control-word decode on the motherboard; each board shall meet a documented connector contract (signals + timing) so its internals may be reimplemented without disturbing the rest." Update the goal→requirement coverage table (`G5` row). *(Candidate only — not created here.)* |

Until then, this file is the working reference; on ratification it is deleted (per the
plan-document rule).

---

## Influences / prior art (non-normative — justifies nothing)

Deposit/examine front panels with in-view, individually-lit registers are a
long-standing homebrew and minicomputer-era idea; BLIP's flat, fully-visible layout is
in that spirit. *Historical context only — it is no part of any justification above,
which rests solely on `G5`/`G6`/`R-HW-4`/`R-DBG-1` and the cited decisions.*
