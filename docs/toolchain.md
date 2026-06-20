# BLIP — Development Workflow & Toolchain

> **Tier-3 spec.** How BLIP is built, simulated, and regression-tested — the
> development flow that realizes the *simulation-first* decision (D-10) and the
> boot-loaded writable control store (D-03, R-CTRL-3). For the control word this flow
> compiles see [microcode.md](microcode.md); for the datapath it simulates see
> [hardware.md](hardware.md); for the CPU boundary the tests stop at see
> [interface.md](interface.md); for the programmer's contract under test see
> [isa.md](isa.md); for *why* see [goals.md](goals.md).
>
> **Status:** v0 design direction (new). This lays out the toolchain options and a
> recommended stack; concrete tool versions, the microcode source syntax, and the
> cell-library timing data firm up as the first routines and chip models are
> written. It answers to the simulation/verification requirements **`R-SIM-1…4`** and
> the microcode-toolchain requirement **`R-BUILD-3`**, with `R-CTRL-3`, `R-CLK-1`,
> and the interface requirements behind specific claims. Per [AGENTS.md](../AGENTS.md)
> tool choices justify on **technical merit and requirement IDs**, not by popularity,
> and no CPU architecture is cited as a reason.

---

## 1. Principles

Four principles shape the whole flow; everything below is their consequence.

- **P1 — Single source of truth, twice over.** The hardware is **one** structural
  description (the netlist); the ISA is **one** microcode image (the exact bytes the
  EEPROMs receive). Every other artifact — simulations, waveforms, schematics,
  burn files — is *derived* from these two, never maintained in parallel. This is
  the operational form of R-SIM-2 (the image that drives simulation is the image the
  machine runs) and R-CTRL-3 (one reflashable image), realizing D-10 (the simulation
  is the reference model the hardware is built against, so the design verified is the
  design that ships).
- **P2 — Two simulators, one source.** No single simulator is simultaneously
  nanosecond-accurate *and* fast enough for a large regression suite (§4). The
  resolution is to run the **same** hardware description under two engines — a
  timing-accurate one for design sign-off and a fast functional one for iteration —
  rather than to seek one tool or to keep two divergent models.
- **P3 — Visualization is generated, never authored.** Schematic, waveform, and
  interactive views are produced *from* the source and the simulation output, so
  they cannot drift from the design. This is the structural difference from a
  schematic-capture tool, where the picture *is* the hand-maintained source.
- **P4 — The CPU boundary is the test boundary (R-SIM-3).** The simulated top level
  is the CPU module, whose only ports are the functional interface (R-IF-1, G7). Memory
  and peripherals are bus-attached models that live **outside** that module;
  "mocking a peripheral" is swapping one of those models. Tests assert on
  architectural state and on bus transactions at the boundary — never on signals
  internal to the CPU (except via the privileged debug taps of R-DBG-5).

---

## 2. The pipeline

```
   SOURCES (single source of truth)                 DERIVED ARTIFACTS / CONSUMERS
   ┌───────────────────────────┐
   │ microcode source (.uasm)  │   assemble    ┌─────────────────────────────┐
   │  + field-definition file  │ ────────────► │ ONE EEPROM image             │──► EEPROM burner
   │   (the 88-bit word spec)  │               │  = 13 SRAMs (11 WCS + 2 map) │──► boot loader fans out
   └───────────────────────────┘               │ (.hex / .bin, same bytes)    │──► sim $readmemh (image)
                │ generates                     └─────────────────────────────┘
                ▼                                              │ loaded into
   ┌───────────────────────────┐                              ▼
   │ microcode.md §3 field table│              ┌───────────────────────────────────────┐
   └───────────────────────────┘              │  CPU model (structural Verilog)         │
                                              │  built from the 74-series cell library  │
   ┌───────────────────────────┐  instantiate │  (each cell = one chip + specify delays)│
   │ 74AHCT / 74ACT cell library│ ───────────► │                                         │
   │  (datasheet min/typ/max)  │              └───────────────────────────────────────┘
   └───────────────────────────┘                 │                         │
                                          same source under two engines     │
                              ┌────────────────────┘                        └──────────────┐
                              ▼ Icarus (delays on)                       ▼ Verilator (zero-delay)
                    ns-accurate timing sign-off                  fast functional regression
                              │                                         │
                              └──────────── cocotb (one test API) ──────┘
                                     │ peripherals = bus-attached models OUTSIDE the CPU
                                     ▼
                    VCD/FST ──► GTKWave / Surfer        Verilog ──► Yosys ──► netlistsvg (schematic)
                    (execution + propagation delays)                      └─► DigitalJS (interactive)
```

---

## 3. Microcode toolchain

A small **assembler** (Python is the pragmatic choice — it is glue, not a runtime
component, so R-HW-1 does not apply) turns a human-readable microcode source into
the control-store image (R-BUILD-3). The image is the single source of truth that
both the EEPROMs and the simulator consume (R-SIM-2, P1).

### 3.1 One definition of the control word

The 88-bit word's field layout (the [microcode.md §3](microcode.md) table — names,
bit positions, widths, value encodings) is held in **one machine-readable
field-definition file**. Both the documentation table *and* the assembler's
bit-packer are generated from it, so the spec, the tool, and the doc cannot drift.
A field's symbolic values (`ALU_OP=ADD`, `USEQ_OP=CALL`, …) and its illegal
combinations (e.g. `MEM_OP` may not co-assert read and write, R-IF-2) live here too.

### 3.2 Source language

The source is a **register-transfer notation** — `MAR <- X + SCR1`, not raw
`field=value` — with **one statement per microword** (strict 1:1), so counting lines
counts cycles. The assembler derives the control-word fields from the field definition
(§3.1). The full grammar — operand/operator vocabulary, the memory/flag/sequencer
clauses, and the realizability rules — is specified in
**[microcode-source.md](microcode-source.md)** (`.uc` source files). With `CALL`/`RETURN`
available (D-42), shared prologues (effective-address computation, push/pop) are written
once and called, so the source stays DRY.

### 3.3 Outputs

- **One EEPROM image** holding all 13 control-store SRAMs (D-43): the 11 WCS chips
  (88 bits = 11 byte-wide SRAMs) and the 2 opcode→start-address map chips (D-40 —
  `{PAGE, IR}`, 512 entries × 13-bit `µPC`, split low byte + high 5 bits). The boot
  loader fans this single image out to the 13 SRAMs at power-on (§3.5); there is **one**
  burnable part, not thirteen.
- **Chip-major, uniform-segment layout.** The image is 13 contiguous 2¹³-byte segments —
  segment *k* is SRAM *k*'s full contents — so the loader is pure binary address-slicing
  (`eeprom_addr = (segment << 13) | sram_addr`). Total 13 × 8192 = 106 496 bytes — the low
  region of a 128 KB control-store EEPROM (the design size, D-43; the physical part is a
  hardware/BOM choice the toolchain need not know); map segments are zero-padded above their
  512 used entries; unused bytes are `0x00`, the inert NOP control word.
- Emitted both as the **burner image** (raw binary) and in `$readmemh` form — **the same
  bytes**, so the device the machine runs is the device the sim ran. Per-SRAM slices are
  also emitted as an optional direct-load *bypass* (§3.5).

### 3.4 What the assembler owns

Symbolic field encoding; label and `NEXT_ADDR`/`CALL`-target resolution; dense
microaddress allocation (routines are placed freely because the D-40 map decouples
opcode number from microroutine location); and validation of illegal field
combinations before a single bit is burned.

### 3.5 Boot path vs. simulation load

On hardware, the boot loader copies the single EEPROM image out to the 13 control-store
SRAMs at power-on — the 11 WCS chips and the 2 opcode-map chips — then releases the CPU
(D-03, D-43, R-CTRL-3). **Simulation loads that same single image and runs the same
loader**, so the boot-copy circuit is exercised on every functional run (D-43): the image
the machine is burned with is the image the sim fans out (R-SIM-2), with no separately
maintained per-SRAM slices to drift. A direct per-SRAM `$readmemh` **bypass** is available
as an opt-in to isolate a loader fault from a microcode fault, but it is **not** the
default — putting the loader in the standard path means a loader regression is caught by
the ordinary functional suite (R-SIM-4), not only by a dedicated test.

---

## 4. Hardware description & simulation

### 4.1 Structural Verilog on a 74-series cell library

This is **simulation, not emulation** (R-SIM-1): the model *is* the structure of the
machine — every gate and flip-flop is a part on the board, evaluated with its own
propagation delay — not a behavioral program that merely reproduces the ISA's results.
The soundness of the discrete TTL design can only be shown by simulating that
structure at the target clock (R-CLK-1); R-SIM-1 makes this explicit ("the structure
under test shall be the design that is built"), which is also why §4.3 keeps no
separate behavioral model.

The CPU is described **structurally** in Verilog, built by instantiating a library
of **74-series cell models** — one model per physical part (`74AHCT`/`74ACT`, D-37,
R-HW-2). Each cell carries its datasheet timing (propagation `tpd`, setup `tsu`,
hold `th`, pulse width `tpw`) in `specify` blocks, with **min / typ / max** corners
(worst-case `tpd` for the setup question, best-case `tpd` for the hold question).
Modeling 74-series parts structurally is established practice and open chip libraries
exist, but they typically carry only simple gate delays; attaching full datasheet
setup/hold timing via `specify` (standard, simulation-only Verilog) is work we do
ourselves — chip vendors ship IBIS/SPICE models, not Verilog timing models — so the
library, not its download, is the investment.

Building the cell library is that one substantial up-front investment, and it is
**unavoidable**: gate-level timing faithful to the real chips is the only way to
verify that the discrete TTL design is electrically sound at the target clock
(R-CLK-1). The library is reusable, and because each instance maps 1:1 to a chip on
the board, the netlist doubles as a legible, BOM-like description (R-HW-4, G5).

### 4.2 The same netlist under two engines

A correct **synchronous** design is functionally correct at zero delay; the timing
simulation's job is to prove the propagation delays fit inside the clock period
(R-CLK-1) — the registered/pipelined structure R-CLK-2 prefers is what makes that
period achievable. That lets the *same* structural Verilog run under two engines:

| Engine | Timing model | Speed | Role for BLIP |
|--------|--------------|-------|---------------|
| **Icarus Verilog** | `#`/gate delays + `specify` path delays (via `-gspecify`) → ns-accurate; no `$setup`/`$hold` checks | moderate | **Directed worst-case timing tests** (bounded, a few cycles): drive the worst-case control word down each critical path and check the R-CLK-1 margin; whole-CPU worst-case is STA's job (§5.2). |
| **Verilator** | zero-delay (cycle-based; compiled to C++) | very fast | **Functional regression**: run the ISA/microcode suite and whole programs quickly. |
| Commercial (Questa/Xcelium/VCS) | full timing + SDF + automated setup/hold checks | fast | Gold standard for sign-off; reserved for if open tools prove insufficient (licensing cost). |

The central trade-off, stated plainly: **you run two simulators, not one.** There
is no robust tool that is both nanosecond-accurate and Verilator-fast, so the flow
is built to make the split cheap — one Verilog source, one microcode image, one
test suite feeding both engines.

**Speed is not the bottleneck, because of how the two are used (§5).** The functional
suite — the part that runs many cycles — is Verilator, which comfortably exceeds the
≥1 MHz simulated target for a CPU this size. Gate-level timed simulation in Icarus is
far slower per cycle (kHz, not MHz), but it is never run for long: timing is a
worst-case property checked by **STA or short directed tests** (§5.2), so it is
bounded / one-shot, not throughput-bound. Two facts shape that timing check: `specify`
path delays are off by default in Icarus (enable with `-gspecify`), and Icarus
implements no `$setup`/`$hold` timing-check tasks, so margins are read from the
waveform, not reported by the simulator (§5.2).

### 4.3 Why not a separate behavioral model

A fast hand-written behavioral CPU model would tempt divergence from the gate-level
design and break P1. The structural design under Verilator already supplies the
speed, so no separate "golden" model is kept; the gate design *is* the golden model.

---

## 5. Test harness & regression

A **regression** is *something that used to work, broken by a change* — the suite's
job is to catch backsliding against a known-good baseline (pinned expected results
for function; the R-CLK-1 worst-case margin for timing), not to characterize new
behavior. This automated dual functional+timing gate is R-SIM-4.

**cocotb** (Python testbenches) drives **both** Icarus and Verilator through one
API, giving the single test runner the requirements call for. Tests are written in
Python — congenial to a code/data-first workflow — and select the backend per suite.
(As of 2026, cocotb 2.0.x drives Verilator without the former "experimental" caveat
given a recent Verilator — 5.036+ — though Verilator remains the most
feature-constrained of the supported backends.)

### 5.1 Timing is a worst-case hardware property — so regression is asymmetric

The hardware is timing-valid only if its worst-case path fits the clock window for
**any control word the WCS could hold** — i.e. for *all possible microcode*, not for
any particular program (R-CLK-1). Once the hardware passes timing, microcode cannot
break it. That makes the regression model **asymmetric**:

| Change | Suite that must pass | Why |
|--------|----------------------|-----|
| **Microcode** | functional only (ISA unit + integration) | timing holds for any microcode by the invariant, so it is assumed, never re-checked |
| **Hardware** (incl. the cell library) | the **entire** suite — worst-case timing **and** all functional unit + integration tests | a hardware change can bust timing *and* can change results |

One harness; the **gate** (which subset is required) is selected by what changed.
Microcode iteration — the frequent activity — runs only the fast functional suite.

### 5.2 The two suites

- **Functional / ISA suite** (run under Verilator): load a program into the simulated
  memory model, run, and assert on architectural state (registers, flags, memory) and
  on bus transactions against **pinned expected values** (authored from the ISA spec;
  arithmetic cross-checked against the host). Catches functional regressions from
  *either* domain; this is where R-BUILD-1 output (compiled C, eventually FUZIX) is
  exercised, and where the long runs live.
- **Worst-case timing verification** (per hardware change, R-SIM-1): show the
  worst-case path fits the R-CLK-1 window over the **whole control-word space** — *not* by sampling
  margins from a program trace, which only exercises the paths that program happened
  to hit. Two ways, both bounded: **static timing analysis** (STA — e.g. the open
  OpenSTA — on the netlist), which finds the worst path with no notion of a program at
  all; or **directed worst-case timing tests** in Icarus that drive the worst-case
  control word down each enumerated critical path (clock tree, ALU carry chain,
  WCS→datapath) and check the margin (Icarus implements no `$setup`/`$hold` tasks, so
  the margin is read from the VCD: `tpd`(max) arrival ≤ capture-edge − `tsu`, hold
  window met). A violation fails the gate.

### 5.3 Speed

Only the functional suite runs many cycles, and it runs on Verilator: **≥1 MHz
simulated is the target and is comfortably met** for a CPU this size (often several
MHz), so a long integration test or a FUZIX boot is seconds-to-minutes of wall-clock.
Timing verification is **bounded, not throughput-bound**: STA is a one-shot analysis
(seconds-to-minutes for a design this size); directed tests are a few cycles each, so
even though gate-level timed Icarus runs at kHz — not MHz — per cycle, each test is
milliseconds of wall-clock. The per-cycle slowness of timed simulation therefore
never gates iteration; the one configuration that would hurt — *long programs at
gate-level-with-timing* — is exactly what §5.1 says never to run. (These rates are
estimates; an early action is to **benchmark a representative slice** — ALU + a few
registers + the WCS path — under both engines, to replace them with measurement, §10.)

**Peripherals are explicitly outside the CPU (R-SIM-3, P4, R-IF-1…3, G7).** The CPU
module exposes only the functional interface (R-IF-1…3); memory, UART, timer, and block device are
separate bus-attached models. A test "mocks" a peripheral by substituting its model
(e.g. a scripted UART that injects bytes, a memory that logs accesses). No test
reaches inside the CPU except through the privileged debug taps (R-DBG-5).

---

## 6. Visualization

All views are generated from the two sources (P3); none is hand-maintained.

- **Execution & propagation delays — waveforms.** GTKWave or Surfer on the VCD/FST
  any run emits. The timing build is where the propagation delays are literally
  visible, edge by edge — the nanosecond view used to debug the critical path.
- **The "plumbing" — schematic.** Yosys exports the netlist as JSON, which
  **netlistsvg** (a separate tool) renders to a schematic SVG — drawn directly from
  the Verilog. The wiring diagram is generated, so it is never stale.
- **Interactive, animated logic — the Logisim experience, from code.** Yosys →
  **DigitalJS** (`yosys2digitaljs`) produces a clickable, signal-animated logic
  simulation in the browser / editor, from the same Verilog. It is *functional*
  logic simulation — not timing-accurate (it models unit combinational delays, not
  nanosecond gate timing) — so it is an intuition and teaching view, not an authority.
- **Sketchpad.** Logisim Evolution or *Digital* (the goals.md realization note
  names both) remain useful for reasoning visually about a block *before* committing
  it to Verilog. They are **never authoritative and never in the verification path** —
  their delay models are abstract/unit, not datasheet nanoseconds, and they are not
  the source of truth.

This recovers the value of schematic capture (visual intuition) while keeping the
picture in lockstep with the design, because it is generated from the one Verilog
source rather than maintained beside it.

---

## 7. Selective & optional tools

- **Commercial sign-off (Questa free-tier).** If automated, SDF-grade setup/hold
  checking is ever wanted beyond what testbench assertions provide, a size-limited
  free commercial simulator is the step up — without changing the source.
- **FPGA bring-up — logic validation at speed.** Synthesizing the *structural*
  design to a cheap FPGA runs real software (eventually FUZIX) far faster than any
  software sim, validating **logic**. It does **not** validate TTL soundness —
  FPGA timing ≠ discrete-74-series timing — so it is a bring-up accelerator, never
  part of timing sign-off, and never the CPU itself in the shipped machine (R-HW-1
  bars a programmable-logic soft-core from acting as the CPU; ⟸ G1).

**Out of scope for now.** Analog signal integrity — reflections, ringing,
bus-contention current — is a deliberate later concern, not addressed by this flow.
Logic-timing verification (§5.2) covers setup/hold, races, and clock skew; the analog
layer is left for when the physical build makes it real.

---

## 8. What runs where

| Need | Tool(s) | Grounded in |
|------|---------|-------------|
| Microcode source → burnable image | Python assembler + field-definition file | R-BUILD-3, R-CTRL-3, D-03 |
| Same image drives the sim sequencer | `$readmemh` of the assembler output | R-SIM-2, R-CTRL-3, D-10 |
| Worst-case timing over all microcode | STA / directed Icarus tests + 74-series cell library | R-SIM-1, R-CLK-1, R-HW-2, D-37 |
| Fast functional regression | Verilator (same Verilog) | R-SIM-4, R-SIM-1 |
| One test runner, both engines | cocotb | R-SIM-4 |
| Stop at the CPU boundary; mock peripherals | bus-attached models outside the CPU module | R-SIM-3, R-IF-1…3, G7 |
| See execution / delays | GTKWave / Surfer (VCD/FST) | R-DBG-1 (echoes observability) |
| See the architecture / plumbing | Yosys + netlistsvg / DigitalJS | R-HW-4 (echoes legibility) |

---

## 9. The recommended stack

```
Sources of truth:
  • Hardware  → structural Verilog on a hand-built 74AHCT/74ACT cell library
                with datasheet specify-timing (min/typ/max corners)
  • Microcode → Python assembler → 11 device images + opcode-map image
                (same bytes feed $readmemh AND the EEPROM/boot-ROM burn)

Simulation (two engines, one source):
  • Verilator      → fast functional regression (≥1 MHz; same Verilog, zero-delay)
  • STA / Icarus   → worst-case timing over all microcode (bounded, one-shot)

Tests:
  • cocotb (Python) → one runner, both backends; peripherals are
                      bus-attached models OUTSIDE the CPU module

Visualization (all derived from the Verilog):
  • GTKWave / Surfer → waveforms & real propagation delays
  • Yosys+netlistsvg → auto-generated schematic ("the plumbing")
  • Yosys+DigitalJS  → interactive animated sim (Logisim, from code)

Selective / optional:
  • Questa free-tier → only if SDF-grade setup/hold checks are wanted
  • FPGA build       → fast real-software/FUZIX bring-up (NOT TTL timing)

(Analog signal integrity is out of scope for now — §7.)
```

The two real investments, in order: (1) the **74-series timing cell library** — the
gate to gate-level soundness; (2) the **microcode assembler + field-definition
file** — the single-source-of-truth spine. Everything else is off-the-shelf and
free.

---

## 10. Status & open questions

1. **Requirement chain — closed.** The simulation/verification needs this flow serves
   are now stated as testable requirements in [requirements.md](requirements.md):
   **`R-SIM-1`** (gate-level timing-accurate simulation), **`R-SIM-2`** (the same
   microcode image in sim and hardware), **`R-SIM-3`** (CPU-boundary harness with
   external peripheral models), **`R-SIM-4`** (the dual functional+timing regression
   gate), and **`R-BUILD-3`** (the microcode toolchain). This document answers to
   them; it is no longer provisional. (Analog signal-integrity verification was
   deliberately left out of scope — §7.)
2. **Microcode source syntax.** Finalize the concrete grammar (mirroring §5
   notation), comment style, and whether shared sequences are expressed purely via
   `CALL`/`RETURN` (D-42) or also with assembler-level macros.
3. **Cell-library timing data.** Decide the vendor and corner data for the
   `74AHCT`/`74ACT` models (datasheet min/typ/max vary by manufacturer), and how
   temperature/voltage corners are represented.
4. **Worst-case timing method.** Two routes give the §5.2 worst-case gate: **STA**
   (e.g. OpenSTA) — rigorous and exhaustive (it finds the worst path automatically),
   but needs the cell timing captured as Liberty/SDF, more setup; or **directed
   worst-case tests** in Icarus — reuse the `specify` models already built, but you
   must enumerate the critical paths yourself (risk of missing one). Likely both:
   directed tests for the hot paths now, STA once the cell timing is in Liberty/SDF.
5. **Visualization prune (not a reopening).** The recommendation stands as-is —
   DigitalJS for interactive logic, netlistsvg for schematic, GTKWave/Surfer for
   waveforms. The only open call is whether DigitalJS earns its keep once the
   schematic + waveform views mature: a later prune, not a v0 choice.
6. **Benchmark the engines early.** Replace the §5.3 speed estimates with
   measurement: model a representative slice (ALU + a few registers + the WCS path)
   and time it under Verilator and Icarus before committing to the split.
