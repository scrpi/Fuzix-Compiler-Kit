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

## Repository layout

```
blip/
├── README.md  AGENTS.md  CLAUDE.md  Makefile
├── docs/
│   ├── (Tier 1–3 normative + decision-log.md)
│   └── reference/          # datasheets/, isa-comparison.md, d41-isa-refinement.md, *.svg
│
├── hdl/              ◀ SOURCE OF TRUTH #1 — structural Verilog (the CPU netlist = the BOM)
│   ├── cells/              # 74-series library, one model per chip + specify timing
│   ├── cpu/               # datapath, alu, registers, mmu, sequencer, control-store
│   ├── boot/              # boot-copy loader, reset
│   └── cpu.v              # top: ports = the functional interface ONLY (R-SIM-3)
│
├── microcode/        ◀ SOURCE OF TRUTH #2 — the control-store image (data + its validator)
│   ├── control_word.toml  # the field definition (the spine)
│   ├── check_fields.py    # field-def validator — lives next to control_word.toml
│   ├── src/               # the .uc routines
│   └── build/ (gitignored)  # the EEPROM image: control store ONLY (WCS + map SRAMs)
│
├── tools/            # HOST-side tooling
│   ├── uasm/              # microcode assembler (uasm.py); args: <field-def> <source>, with defaults
│   ├── cc/               # C compiler backend (submodule, later)
│   ├── asm/  link/       # ISA assembler + linker (R-BUILD-1/2)
│   └── viz/              # netlistsvg / DigitalJS / GTKWave generators (P3)
│
├── sim/              # verification — two engines, one source
│   ├── tb/               # testbenches per module (+ the system tb)
│   ├── models/           # bus-attached peripheral models: uart, timer, memory, system-ROM… (P4)
│   ├── tests/            # ISA functional programs + pinned vectors
│   ├── sta/              # static timing analysis
│   └── bench/            # engine benchmark
│
├── src/              # software that RUNS on blip (target)
│   ├── monitor/          # bootstrap/monitor → its OWN system ROM (NOT the microcode ROM)
│   ├── lib/  examples/  fuzix/(later)
│
├── hw/               ◀ PHYSICAL — one subdir per board
│   ├── <board>/          # schematic/  pcb/  bom/   gerbers/(gitignored)
│   └── …                 # e.g. cpu-card, front-panel, memory, io, backplane
```

Peripherals (a UART, timer, storage) are deliberately **not** in `hdl/`: the CPU
module's only ports are the functional interface (R-SIM-3), so peripherals live as
bus-attached models in `sim/models/` and as physical parts in `hw/`. The microcode
EEPROM stores **only** the control store; the firmware monitor is a separate system
ROM in the memory map (D-31).

**Two standing rules:**

1. **Generated artifacts are never committed.** Only the `hdl/` netlist and the
   `microcode/` source/field-definition are tracked; *everything derived* — the
   EEPROM image, simulation outputs, schematics, waveforms, generated views, the
   BOM — is rebuilt, never stored in git (toolchain.md P1/P3).
2. **New artifacts go in an existing top-level domain, never a new top-level
   folder.** The domains above (`docs hdl microcode tools sim src hw`) are
   exhaustive by design; a new kind of file belongs inside one of them. This keeps
   the top level stable as the project grows.

## Status

Early design. The goals are settled; the ISA register model and addressing modes
are proposed and under active discussion; the full opcode table and the hardware
schematics are in progress. See the "Open questions" sections in each doc.

## Name

**B**en's **L**ittle **P**rocessor. The blinkenlights blip.
