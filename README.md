# BLIP — Ben's Little Processor

An 8-bit CPU built from **discrete 74-series logic** (no CPU-on-a-chip), designed
to be a *genuine* C compiler target, to run a real Unix-like OS
([FUZIX](https://www.fuzix.org/)), to address well beyond 64 KB, and to be
covered in functional blinkenlights.

BLIP is not a re-implementation of any existing chip. It is a clean-sheet ISA
whose every design decision answers to one question: *does this make a real
optimizing C compiler emit good code, and can I still build it on a bench from
74AHCT parts and watch it think?*

## Headline goals

- **Discrete logic only.** 74-series (74AHCT) gates, registers, and SRAM — no
  microprocessor, no microcontroller, no FPGA soft-core as the CPU.
- **A real C target, not a toy.** C local variables and pointer arithmetic must
  be *efficient*, not merely possible. Primary toolchain plan: a new **SDCC**
  backend cloned from the STM8 port.
- **Runs FUZIX.** A real multitasking Unix-like OS, which sets the bar for
  memory size, banking, interrupts, a timer, storage, and a console.
- **More than 64 KB, with protection.** A paged translation MMU (GIME/DAT-style,
  8 KB pages, up to 16 MB) gives each process a flat 16-bit view, and a
  supervisor/user CPU mode keeps the kernel isolated from user code.
- **Microcoded control** with a **writable control store** loaded from ROM into
  fast SRAM at power-on.
- **~10 MHz aspirational** clock.
- **Functional blinkenlights.** Every bus and register is always meaningfully
  displayable, and a front panel can examine/deposit memory and bootstrap the
  machine by hand.
- **A fixed external interface.** The CPU meets the functional system — memory,
  address translation, I/O — through a defined set of bus and control lines. Only
  the front panel reaches past that boundary, via a separate privileged debug
  interface, to display the CPU's internals.

## Documentation

- [docs/goals.md](docs/goals.md) — high-level design goals and the priority
  hierarchy that breaks ties. *(Tier 1 — what and why, no implementation.)*
- [docs/requirements.md](docs/requirements.md) — testable requirements derived
  from the goals, with stable IDs. *(Tier 2 — the contract specs must satisfy.)*
- [docs/isa.md](docs/isa.md) — instruction-set rationale, register model,
  addressing modes, encoding map, and the opcode table. *(Tier 3 — the
  programmer's contract.)*
- [docs/hardware.md](docs/hardware.md) — register file, datapath, MMU, microcode
  state machine, clocking, front panel, and peripherals. *(Tier 3 — how it's
  built.)*
- [docs/decision-log.md](docs/decision-log.md) — chronological record of
  decisions and their rationale. *(Non-normative.)*

## Status

Early design. The goals are settled; the ISA register model and addressing modes
are proposed and under active discussion; the full opcode table and the hardware
schematics are in progress. See the "Open questions" sections in each doc.

## Name

**B**en's **L**ittle **P**rocessor. The blinkenlights blip.
