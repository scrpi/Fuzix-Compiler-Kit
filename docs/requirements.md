# BLIP — Requirements

> **Tier 2 of 3.** This document turns the project [goals](goals.md) into
> concrete, testable needs. It is the contract the [ISA](isa.md) and
> [hardware](hardware.md) specifications must satisfy. See [AGENTS.md](../AGENTS.md)
> for the three-tier model and the rules below.

**How to read this.** Each requirement has:
- a **stable ID** (`R-<AREA>-<n>`) — specifications cite these IDs;
- a **source link** (`⟸ Gn`) tracing it to the goal(s) it derives from;
- a **self-standing "shall" statement** in BLIP's own terms.

**Rules.** Requirements name no external architecture and are not re-argued from
their goal — the goal link records *where they came from*, the statement says
*what must be true*. Specifications justify themselves by citing these IDs, never
by reaching past them to a goal or to another design.

---

## Construction (HW)

- **R-HW-1** (⟸ G1) — The processor's core (datapath, registers, ALU, control
  unit) shall be built from commodity discrete logic and standard memory devices.
  No single device may implement the processor's core function (no integrated
  CPU, microcontroller, or programmable-logic soft-core acting as the CPU).
- **R-HW-2** (⟸ G1, G9) — All core logic shall be drawn from a small, mutually
  level-compatible set of logic families sharing one signaling regime (5 V, TTL-level
  CMOS), fast enough to meet R-CLK-1, so signaling levels are uniform across the machine.
  (In practice 74AHCT for SSI and 74ACT for MSI — see decision log D-37.)
- **R-HW-3** (⟸ G1) — Peripheral and support functions that are not the
  processor itself (console, clock generation, mass storage interface, glue)
  may use dedicated devices and are exempt from R-HW-1.
- **R-HW-4** (⟸ G5) — The CPU's architectural and working register set (`A`, `B`,
  `X`, `Y`, `SP`, `PC`, `CC`, and the datapath working registers), its ALU, and its
  internal buses shall be realized as individually-observable discrete components,
  not as addressed or time-multiplexed bulk storage. Memory-like arrays — main
  memory, the writable control store, and the MMU translation table — are exempt.

## Instruction set & C model (ISA)

- **R-ISA-1** (⟸ G2) — A function's local variables and spilled temporaries
  shall be readable and writable relative to the stack pointer in a single
  instruction, with no per-variable address arithmetic.
- **R-ISA-2** (⟸ G2) — The stack-relative access of R-ISA-1 shall reach frames
  large enough that typical functions need no dedicated frame-pointer register.
- **R-ISA-3** (⟸ G2) — The CPU shall provide enough simultaneously-live 16-bit
  pointer registers to handle common C patterns (array traversal, struct access,
  pointer-to-pointer) without frequent spilling.
- **R-ISA-4** (⟸ G2) — Address computation — `p + n`, `&array[i]`, `&local` —
  shall be expressible as single operations, including a 16-bit add and an
  effective-address computation.
- **R-ISA-5** (⟸ G2) — Pointer access shall be supported directly by addressing
  modes covering displacement, indexing by a value, and post-increment /
  pre-decrement (for `*p`, `a[i]`, `*p++`).
- **R-ISA-6** (⟸ G2) — 16-bit integer and pointer values shall have a 16-bit
  arithmetic path (add, subtract, compare) that does not require multi-step
  emulation.
- **R-ISA-7** (⟸ G2) — Conversion between 8-bit and 16-bit values shall be
  cheap: the 8-bit and 16-bit accumulation paths shall share storage so widening
  and narrowing need minimal data movement.
- **R-ISA-8** (⟸ G2, G3) — Function calls shall be reentrant: parameters,
  locals, and the return linkage shall live on a per-invocation stack, so any
  function is safe under recursion, interruption, and concurrent tasks. Statically
  allocated (overlaid) per-function locals are not acceptable.

## Calling convention (ABI)

- **R-ABI-1** (⟸ G2) — There shall be exactly one documented, stable calling
  convention that both the C toolchain and hand-written assembly follow; it is
  fixed (not an internal implementation detail free to change).
- **R-ABI-2** (⟸ G2) — The convention shall pass the leading scalar arguments in
  registers rather than exclusively on the stack, so that calls to small and leaf
  functions are inexpensive.
- **R-ABI-3** (⟸ G2) — A returned 16-bit value shall be delivered in a register
  that supports memory-access addressing modes, so a returned pointer is
  immediately usable without a register move.
- **R-ABI-4** (⟸ G2) — It shall be possible to keep at least one 16-bit pointer
  live across a function call without spilling it to memory, to serve the common
  loop-carried-pointer pattern.

> *Note:* R-ABI-2 (more values passed/returned in registers) and R-ABI-4 (a
> register preserved across calls) pull in opposite directions over a finite
> register file; the ISA spec resolves the balance and records the trade-off.

## Execution & OS support (CPU)

- **R-CPU-1** (⟸ G3) — The CPU shall provide two privilege levels — a privileged
  level for the operating-system kernel and an unprivileged level for user
  processes — with a controlled, well-defined transition from unprivileged to
  privileged execution.
- **R-CPU-2** (⟸ G3) — A software-initiated trap shall transfer control to the
  kernel at a fixed privileged entry point, preserving enough caller state to
  resume it (the system-call mechanism).
- **R-CPU-3** (⟸ G3) — The CPU shall support maskable external interrupts and a
  periodic timer interrupt suitable for pre-emptive scheduling, with clean
  saving and restoring of interrupted state.
- **R-CPU-4** (⟸ G3, G4) — Unprivileged code shall be unable to read or alter
  memory or control state outside its assigned address space — in particular the
  address-translation configuration (R-MEM-3) and the kernel's working state.
- **R-CPU-5** (⟸ G3) — The kernel shall have a stack that unprivileged code can
  neither name nor corrupt.
- **R-CPU-6** (⟸ G3) — The kernel shall be able to execute critical sections
  without interruption, to protect scheduler and data-structure invariants.
- **R-CPU-7** (⟸ G3, G6) — On reset the CPU shall enter a defined, deterministic
  state — supervisor mode, interrupts masked, execution beginning at a fixed reset
  vector — so startup does not depend on uninitialised state. (supports R-DBG-3)

## Memory & address space (MEM)

- **R-MEM-1** (⟸ G4, G2) — Each running program shall be presented with a flat
  16-bit (64 KB) logical address space; ordinary code and pointers shall not need
  to be aware that physical memory is larger or partitioned.
- **R-MEM-2** (⟸ G3, G4) — Physical memory shall extend well beyond 64 KB, on
  the order of megabytes — enough to hold a kernel plus several concurrent user
  processes (at least ~128 KB working memory, with headroom far above that)
  without forcing memory-to-storage swapping in the common case.
- **R-MEM-3** (⟸ G3, G4) — Each process shall have its own logical-to-physical
  mapping, which the kernel can switch on a context switch.
- **R-MEM-4** (⟸ G3) — A region of memory shall stay mapped at a fixed location
  across every per-process mapping, to hold kernel code and data that must always
  be reachable — including the code that performs mapping switches and data
  transfers between mappings.
- **R-MEM-5** (⟸ G3, G4) — Switching the active mapping on kernel entry/exit and
  on context switch shall be cheap, ideally implicit in the privilege transition
  rather than a long instruction sequence.
- **R-MEM-6** (⟸ G4) — Address-translation granularity shall be fine enough to
  allocate physical memory to processes with little internal waste, yet coarse
  enough to keep the translation hardware small.
- **R-MEM-7** (⟸ G3, G6) — On reset, address translation shall default to a
  transparent (identity) mapping of the low 64 KB of logical space onto the low
  64 KB of physical, so the machine can fetch, execute, and be bootstrapped before
  any translation is configured. (supports R-DBG-3 and first-bring-up)

## Control & microcode (CTRL)

- **R-CTRL-1** (⟸ G8) — The **entire** instruction set — opcode encodings,
  addressing modes, operations, and flag effects — shall be defined by the stored
  microcode, with no instruction-specific behaviour in fixed logic, so the
  instruction set can be corrected, extended, or redefined without rewiring.
- **R-CTRL-2** (⟸ G8, G9) — The runtime microcode store shall be fast enough not
  to dominate the cycle time at the target clock (R-CLK-1).
- **R-CTRL-3** (⟸ G8) — The microcode image shall be **field-reprogrammable**:
  changing the instruction set shall require only reflashing the non-volatile store
  from which the control store is loaded at power-on — never a hardware change — and
  the microcode shall be retained across power cycles so the machine boots unattended.
- **R-CTRL-4** (⟸ G8) — The datapath shall be a **complete microcode substrate**:
  the control word shall expose every primitive needed to realize an instruction
  (register loads/enables, bus routing, ALU operations, memory and MMU control, and
  sequencing), so that no instruction's behaviour depends on fixed, instruction-specific
  logic. The fixed substrate — register set and widths, ALU primitives, bus topology,
  the MMU, and the G7 interface — bounds what microcode can change.

## Timing (CLK)

- **R-CLK-1** (⟸ G9) — The design shall target a continuous clock of about
  10 MHz. This target yields to correctness and to higher-priority requirements
  where the critical path cannot meet it; the achievable clock is whatever the
  critical path supports.
- **R-CLK-2** (⟸ G9) — The microarchitecture shall prefer registered/pipelined
  structures over long sequential combinational paths wherever an equivalent
  registered alternative exists.

## Debug & front panel (DBG)

- **R-DBG-1** (⟸ G6) — Every bus and architectural register shall be
  continuously displayable in a stable, legible form, whether the machine is
  free-running, single-stepped, or stopped.
- **R-DBG-2** (⟸ G6) — A front panel shall be able to halt the CPU, take control
  of the buses, and examine and deposit individual memory locations by hand.
- **R-DBG-3** (⟸ G6) — The machine shall be bootstrappable from the front panel
  alone: code can be entered and execution started with no external tools.
- **R-DBG-4** (⟸ G6) — The CPU shall support run/stop control and single-stepping
  (at least per instruction; preferably also per microstep).
- **R-DBG-5** (⟸ G6, G7) — The front panel shall be the sole exception to the
  functional-interface boundary of R-IF-1. It shall connect through a separate,
  privileged **debug interface** that exposes internal architectural and
  microarchitectural state — at minimum the registers and instruction/microcode
  sequencing state needed for R-DBG-1, plus the per-microstep control needed for
  R-DBG-4 — which the functional interface deliberately does not carry. No
  functional peripheral shall connect to this interface.

## Toolchain (BUILD)

- **R-BUILD-1** (⟸ G2, G3) — An optimizing C compiler shall target BLIP and be
  able to build a multitasking OS kernel and its userland, producing efficient
  code for the common C constructs (locals, pointer access, function calls).
- **R-BUILD-2** (⟸ G2) — The C toolchain shall interoperate with hand-written
  assembly through the convention of R-ABI-1, so low-level kernel code can be
  written by hand and linked with compiled code.
- **R-BUILD-3** (⟸ G8) — A microcode toolchain shall compile the microcode from a
  human-readable source into the binary image(s) of the control store, in a form
  suitable both for loading into simulation and for programming the non-volatile
  store from which the control store is loaded at power-on (R-CTRL-3).

## Simulation & verification (SIM)

- **R-SIM-1** (⟸ G1, G9) — The complete CPU shall be simulable at the level of its
  individual logic components, exercising their real propagation and timing
  behaviour, so that the discrete design's logical correctness and its timing against
  the target clock (R-CLK-1) can be verified before, and independently of, physical
  construction. A model that only reproduces instruction results does not satisfy
  this: the structure under test shall be the design that is built.
- **R-SIM-2** (⟸ G8) — The microcode image that drives the simulated control
  sequencer shall be the identical image loaded into the hardware control store
  (R-CTRL-3), so that what simulation verifies is what the machine runs.
- **R-SIM-3** (⟸ G7) — Simulation shall exercise the CPU through its functional
  interface (R-IF-1), with memory and peripherals represented as models outside the
  CPU under test, so any peripheral can be substituted without altering the CPU.
- **R-SIM-4** (⟸ G1, G8) — A change to the hardware or to the microcode shall be
  validated by an automated regression suite — one that fails when a behaviour which
  previously met its specification no longer does — covering both functional
  behaviour (instruction results, flags, memory, and bus transactions) and
  worst-case timing (against R-CLK-1).
- **R-SIM-5** (⟸ G1) — Every module of the design under test shall consist solely
  of instances of real-device cell models and their interconnect (wires, bus
  selections, and constant ties); it shall introduce no behavioural or synthesised
  logic of its own. Behavioural description is confined to the cell models — one per
  real device, modelled from its datasheet — and to the test harness. This shall be
  mechanically checkable, so that no synthetic logic can stand in for a device that
  must physically exist.
- **R-SIM-6** (⟸ G1, G9) — Every cell model shall carry its propagation timing —
  combinational input-to-output path delays and sequential clock-to-output delays.
  The timed simulation engine shall always apply that timing, so every timed run
  exercises real propagation behaviour; functional (zero-delay) verification is
  performed by a separate engine. This shall be mechanically checkable.

## CPU/system interface (IF)

> The functional interface is specified in [interface.md](interface.md) (decision
> [D-29](decision-log.md)); the privileged debug interface (R-DBG-5) is deferred.

- **R-IF-1** (⟸ G7) — All interaction between the CPU and the *functional* parts
  of the system (memory, translation, I/O peripherals) shall occur through one
  documented set of external signals — the functional interface — and no
  functional peripheral shall depend on any signal internal to the CPU. The front
  panel is the sole exception (R-DBG-5).
- **R-IF-2** (⟸ G7) — The interface shall define an address bus, a data bus, and
  the control signals that qualify and time a bus transfer (transfer direction, a
  validity/strobe indication, and a timing reference).
- **R-IF-3** (⟸ G7, G3) — The interface shall carry the asynchronous system
  control lines: a reset input, the interrupt request inputs (maskable and
  non-maskable), and the clock/timing reference. (supports R-CPU-3; the fast
  interrupt was dropped — D-22)
- **R-IF-4** (⟸ G7, G6) — The interface shall provide a bus-request / bus-grant
  handshake by which an external master can take ownership of the buses while the
  CPU tri-states its bus drivers. (supports R-DBG-2)
- **R-IF-5** *(retired)* — Originally required the interface to expose the CPU's
  privilege level to *external* translation/protection hardware. Superseded by the
  decision to place translation and protection **inside** the CPU (see
  [isa.md](isa.md) §6 and [hardware.md](hardware.md) §3); the functional interface
  therefore conveys neither privilege nor a translation-fault signal. The
  underlying needs remain covered by R-CPU-4, R-MEM-3, and R-MEM-5.
- **R-IF-6** (⟸ G7) — The interface shall be stable: changes to the CPU's
  internal implementation shall not alter the documented signal set or its timing
  contract, so existing peripherals remain compatible.

---

## Goal → requirement coverage

| Goal | Requirements |
|------|--------------|
| **G1** Discrete logic | R-HW-1, R-HW-2, R-HW-3, R-SIM-1, R-SIM-4, R-SIM-5, R-SIM-6 |
| **G2** Genuine C target | R-ISA-1…8, R-ABI-1…4, R-BUILD-1, R-BUILD-2 |
| **G3** Run FUZIX | R-ISA-8, R-CPU-1…7, R-MEM-2…5, R-MEM-7, R-IF-3, R-BUILD-1 |
| **G4** >64 KB, flat per-process | R-MEM-1…6, R-CPU-4 |
| **G5** Legible component architecture | R-HW-4 |
| **G6** Functional blinkenlights | R-DBG-1…5, R-IF-4, R-CPU-7, R-MEM-7 |
| **G7** Defined CPU/system interface | R-IF-1…4, R-IF-6, R-DBG-5, R-SIM-3 |
| **G8** The ISA lives in microcode | R-CTRL-1, R-CTRL-2, R-CTRL-3, R-CTRL-4, R-BUILD-3, R-SIM-2, R-SIM-4 |
| **G9** ~10 MHz | R-HW-2, R-CLK-1, R-CLK-2, R-CTRL-2, R-SIM-1, R-SIM-6 |

## Open questions for this document

- **Coverage check:** does every goal's intent feel fully captured above, or are
  there needs you hold implicitly that aren't yet written down?
- **Quantification:** R-MEM-2 ("~128 KB, headroom into the megabytes") and
  R-CLK-1 ("~10 MHz") are the only numeric requirements — do you want firmer
  numbers, or keep them as ranges until simulation informs them?
- **Missing areas?** e.g. a real-time clock for the OS, or I/O breadth beyond
  console + storage — say if any should become requirements. *(Power-on reset
  behaviour is now covered by R-CPU-7 / R-MEM-7.)*
- **Interface boundary (decided):** translation sits *inside* the CPU; the external
  address bus is the **physical** address (R-IF-5 retired). The functional interface
  is a plain physical bus — no privilege or fault lines.
- **I/O addressing (decided):** all I/O is **memory-mapped** — no separate I/O space
  and no "memory vs I/O" qualifier on the interface. Peripherals are decoded from a
  reserved physical I/O page (see [isa.md](isa.md) §6 and decision log D-28), so
  R-IF-2's signal set stays address + data + transfer control only.
