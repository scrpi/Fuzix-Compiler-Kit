# BLIP — Design Goals

> This document is **what and why only**. No gate counts, no opcodes, no
> schematics. For the programmer's contract see [docs/isa.md](isa.md); for how
> it's built see [docs/hardware.md](hardware.md).

BLIP — *Ben's Little Processor* — is an 8-bit CPU built entirely from discrete
74-series logic, designed from the ground up to be a first-class target for a
real C compiler and to run a real Unix-like operating system, while remaining a
machine you can build on a bench and watch think.

## 1. The goals

### G1 — Discrete logic, no CPU-on-a-chip
The processor is built from off-the-shelf 74-series parts (gates, registers,
multiplexers, counters, ALUs) and standard SRAM/ROM. No microprocessor,
microcontroller, or FPGA soft-core may stand in for the CPU itself. The CPU's
behaviour must be fully explained by its discrete parts. (Support functions that
were never the *point* of the build — a UART, a clock generator, glue
programmable logic — are pragmatic and allowed; see Non-goals.)

### G2 — A genuine C target
BLIP must be a machine a real optimizing C compiler can target and produce
*good* code for — not a machine where C is technically possible but miserable.
Concretely:

- C **local variables** must be cheap to access (a stack-relative,
  displacement-addressed model — no per-variable address arithmetic).
- **Pointer arithmetic and dereferencing** must be efficient, with real
  address-computing and 16-bit operations rather than emulated multi-step
  sequences.
- **Reentrancy and recursion** come for free from a hardware stack, so the same
  code is safe in interrupts and across tasks.

The success test is comparative: code quality should be in the same league as a
6809 (the historical high-water mark for 8-bit C), not merely "it compiles."

### G3 — Run FUZIX
BLIP must run [FUZIX](https://www.fuzix.org/), a multitasking Unix-like OS. This
is the forcing function that turns "a nice ISA" into "a real computer," and it
imposes concrete requirements that the ISA and hardware must satisfy:

- enough memory, with per-process address spaces (see G4);
- a hardware stack and an efficient C calling convention (see G2);
- interrupts and a periodic timer tick;
- a console (serial) and block storage;
- the ability for an OS kernel to run privileged from common memory while user
  processes are swapped beneath it.

### G4 — Address well beyond 64 KB
An 8-bit data path with a 16-bit logical address space (64 KB) is not enough to
run FUZIX usefully. BLIP extends physical memory into the **megabytes** via
address translation, while preserving a **flat 16-bit logical view per process**
so that ordinary C code and pointers never have to know memory is paged. Going
big must not corrupt G2.

### G5 — A legible, component-level architecture
The machine's architecture must be *physically legible*: every architectural
element — each register, the ALU, the flags, the internal buses — is realized as
its own identifiable component you can point to and watch change. Architectural
state must **not** be collapsed into opaque, addressed, or time-multiplexed storage
(for example a register file hidden inside an SRAM), even where that part would
itself be discrete logic.

- this binds the CPU's **register set** (`A B X Y SP PC CC` and the working
  registers `MAR`, `MDR`, `IR`, temporaries), the ALU, and the internal buses;
- memory-like **arrays** — main memory, the writable control store, and the MMU
  translation table — stay bulk storage, read out rather than lit element by element;
- the payoff is comprehension: you understand and debug the machine by looking at
  it, and its structure teaches.

It is stronger than G1 (which permits standard SRAM) and is the structural
precondition for G6 — you can only light each register if each register physically
exists.

### G6 — Functional blinkenlights
The machine must always be *meaningfully displayable*. LEDs are not decoration
bolted on at the end; they are a design constraint:

- every bus and architectural register is latched/buffered so its value is
  stable and legible, even at speed (or single-stepped);
- a **front panel** can halt the CPU, take the buses, **examine and deposit**
  memory, and **bootstrap** code by hand — enough to bring the machine up from
  nothing and to debug it without external tools;
- the display is genuinely useful for debugging, not just pretty.

### G7 — A defined CPU/system interface
The CPU shall be a self-contained module that connects to the *functional* parts
of the system — memory and I/O peripherals —
**only through a fixed, documented set of external signals** (the *functional
interface*: buses and control lines). That signal set *is* the boundary: it is
where the CPU ends and the rest of the machine begins.

This buys modularity. The CPU's internals can be revised, corrected, or
reimplemented — in hardware or in simulation — without disturbing anything
attached to it, as long as the interface holds.

**One privileged exception: the front panel.** Displaying and single-stepping the
machine (G6) inherently requires seeing *inside* the CPU — its registers and
sequencing state — which is more than the functional interface exposes. The front
panel is therefore the sole party allowed to reach past the boundary, through a
separate privileged *debug interface*. No functional peripheral may use it.

### G8 — The ISA lives in microcode
The instruction set is realized **entirely** in microcode, not hard-wired: every
instruction's decode, operand fetch, execution, and flag effects are defined by the
control-store image, with no instruction-specific behaviour in fixed logic. The
hardware is a fixed, general datapath that exposes a *complete* set of
microcode-controllable primitives; the ISA is the **program** that runs on it. The
control store is **writable** (fast SRAM), loaded at power-on from non-volatile
**EEPROM**, so the ISA can be corrected, extended, or **redefined — in development or
in the field — by reflashing the EEPROM, never by respinning a board**. The fixed
substrate (the register set and widths, the ALU's primitive operations, the
datapath/bus topology, the internal MMU, and the G7 interface) is what bounds what
microcode can change; everything above that line is software.

### G9 — ~10 MHz aspirational clock
A 10 MHz target clock is the performance *aspiration* that keeps the design
honest — it rules out lazy, deeply sequential microarchitecture and pushes
toward a pipelined, registered control path. It is **not a hard gate**: when
10 MHz conflicts with a higher-priority goal, correctness and C-friendliness
win, and the achievable clock is whatever the critical path allows.

## 2. Priorities (tie-breakers)

When two goals collide, decisions are made in this order. **This ordering is a
proposal — confirm or reorder it, because the rest of the design cites it.**

1. **G1 Discrete logic** — the soul of the project; never traded away.
2. **G2 Genuine C target** — the ISA exists to serve the compiler.
3. **G3 Run FUZIX** — the proof that G2 and G4 are real.
4. **G4 >64 KB with a flat per-process view** — required by G3, must not break G2.
5. **G5 Legible component architecture** — the machine is built from individually
   visible components; this outranks observability of *values* (G6), the interface
   (G7), how the ISA is realized (G8), and the clock (G9), but yields to the
   functional goals above it.
6. **G6 Functional blinkenlights** — the machine must stay fully observable; this
   outranks how the ISA is realized (G8) and how the interface is drawn (G7). (The
   ISA's *shape* still answers to G2 above it — blinkenlights drive the datapath's
   observability, not the instruction set.)
7. **G7 Defined CPU/system interface** — a structural commitment; the CPU is
   revised *within* the boundary, not around it.
8. **G8 The ISA lives in microcode** — the means by which the ISA is realized;
   reprogrammable, but it yields to observability (G6) and the interface (G7).
9. **G9 ~10 MHz** — pushed for hard, but yields to every other goal.

Read it as: *I will not give up discrete logic to go faster; I will not cripple
C to save gates; I will not break flat per-process pointers to get more RAM; and I
will keep the machine built from visible components (G5), observable (G6), and its
interface clean (G7) before reaching for microcode flexibility (G8).*

## 3. Non-goals (for now)

- **Binary or pin compatibility** with any existing CPU (Z80, 6809, 6502, …).
  BLIP borrows *ideas*, not encodings.
- **Maximum clock speed as an end in itself.** 10 MHz is a target, not a record
  attempt; G2 outranks it.
- **A single-chip / minimal-part-count design.** Part count is acceptable in
  service of clarity and blinkenlights.
- **Graphics and sound.** Console + storage is the initial I/O scope; a video
  subsystem is a possible later chapter, not a launch goal.
- **A bespoke compiler from scratch.** We retarget an existing optimizing
  compiler (plan: SDCC); we do not write a new C compiler front end.
- **Full paged virtual memory / demand paging.** FUZIX needs coarse per-process
  translation, not a VAX-style MMU; we build only what FUZIX requires.
- **Per-page memory protection / faulting.** Process isolation comes from
  per-process address maps plus privileged map-control, not from per-page
  read-only / no-access bits (see decision log D-18).

## 4. What "done" looks like

- BLIP boots from its front panel / ROM and runs a FUZIX multi-user shell.
- The C toolchain (an SDCC backend) compiles the FUZIX kernel and userland, and
  its code quality for locals and pointers is competitive with a 6809.
- The machine runs at a measured clock the design honestly supports, with 10 MHz
  as the bar it was aiming at.
- The front panel can deposit and run a bootstrap, and the blinkenlights let you
  read what the machine is doing.
- The CPU's external interface is documented, and memory, address translation,
  I/O, and the front panel all attach through it.

## Open questions for this document

- **Confirm the priority ordering in §2.** Is C-target quality (G2) really above
  running FUZIX (G3), or do you want FUZIX as the top functional goal?
- **Is video/sound truly out of scope**, or do you want a stated "future" goal so
  the bus/timing design leaves room for it?
- **G7 boundary placement (decided):** the address-translation unit sits *inside*
  the CPU; the external address bus carries the **physical** address. Translation
  and protection are internal, so the functional interface is a plain physical bus
  that conveys neither privilege nor translation faults. The programmer's model
  stays 16-bit logical (R-MEM-1).
- **Realization (decided):** v1 is proven in **simulation first**
  (Logisim/Digital/Verilog), then built in hardware against the sim as a reference
  — so G9's 10 MHz need only hold in simulation for v1, with the hardware clock
  measured later.
