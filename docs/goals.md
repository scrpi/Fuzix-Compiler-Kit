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

### G5 — Microcoded control
Instruction decoding and sequencing are **microcoded** rather than hard-wired,
so the ISA can be developed, corrected, and extended by changing microcode
rather than rewiring. The control store is **writable** (fast SRAM) and loaded
from non-volatile ROM at power-on, making microcode both fast at runtime and
hackable at the bench.

### G6 — ~10 MHz aspirational clock
A 10 MHz target clock is the performance *aspiration* that keeps the design
honest — it rules out lazy, deeply sequential microarchitecture and pushes
toward a pipelined, registered control path. It is **not a hard gate**: when
10 MHz conflicts with a higher-priority goal, correctness and C-friendliness
win, and the achievable clock is whatever the critical path allows.

### G7 — Functional blinkenlights
The machine must always be *meaningfully displayable*. LEDs are not decoration
bolted on at the end; they are a design constraint:

- every bus and architectural register is latched/buffered so its value is
  stable and legible, even at speed (or single-stepped);
- a **front panel** can halt the CPU, take the buses, **examine and deposit**
  memory, and **bootstrap** code by hand — enough to bring the machine up from
  nothing and to debug it without external tools;
- the display is genuinely useful for debugging, not just pretty.

### G8 — A defined CPU/system interface
The CPU shall be a self-contained module that connects to the *functional* parts
of the system — memory and I/O peripherals —
**only through a fixed, documented set of external signals** (the *functional
interface*: buses and control lines). That signal set *is* the boundary: it is
where the CPU ends and the rest of the machine begins.

This buys modularity. The CPU's internals can be revised, corrected, or
reimplemented — in hardware or in simulation — without disturbing anything
attached to it, as long as the interface holds.

**One privileged exception: the front panel.** Displaying and single-stepping the
machine (G7) inherently requires seeing *inside* the CPU — its registers and
sequencing state — which is more than the functional interface exposes. The front
panel is therefore the sole party allowed to reach past the boundary, through a
separate privileged *debug interface*. No functional peripheral may use it.

## 2. Priorities (tie-breakers)

When two goals collide, decisions are made in this order. **This ordering is a
proposal — confirm or reorder it, because the rest of the design cites it.**

1. **G1 Discrete logic** — the soul of the project; never traded away.
2. **G2 Genuine C target** — the ISA exists to serve the compiler.
3. **G3 Run FUZIX** — the proof that G2 and G4 are real.
4. **G4 >64 KB with a flat per-process view** — required by G3, must not break G2.
5. **G5 Microcoded control** — the means by which the ISA is realized.
6. **G8 Defined CPU/system interface** — a structural commitment; the CPU is
   revised *within* the boundary, not around it.
7. **G6 ~10 MHz** — pushed for hard, but yields to G1–G5, G8.
8. **G7 Functional blinkenlights** — shapes the datapath, but never dictates the ISA.

Read it as: *I will not give up discrete logic to go faster; I will not cripple
C to save gates; I will not break flat per-process pointers to get more RAM.*

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
- **G8 boundary placement (decided):** the address-translation unit sits *inside*
  the CPU; the external address bus carries the **physical** address. Translation
  and protection are internal, so the functional interface is a plain physical bus
  that conveys neither privilege nor translation faults. The programmer's model
  stays 16-bit logical (R-MEM-1).
- **Realization (decided):** v1 is proven in **simulation first**
  (Logisim/Digital/Verilog), then built in hardware against the sim as a reference
  — so G6's 10 MHz need only hold in simulation for v1, with the hardware clock
  measured later.
