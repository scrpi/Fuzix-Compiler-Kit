# AGENTS.md — Working conventions for BLIP

Conventions for anyone — human or agent — writing BLIP's design documentation.

## Documentation: the three-tier model

BLIP's design docs are organized in three tiers, with a strict **one-directional
justification chain**. Each tier answers to the tier directly above it, and only
that tier.

| Tier | Question it answers | Lives in |
|------|--------------------|----------|
| 1. **Goals** | What is the project for? | [docs/goals.md](docs/goals.md) |
| 2. **Requirements** | What concrete, testable needs follow from the goals? | [docs/requirements.md](docs/requirements.md) |
| 3. **Specifications / decisions** | How do we meet the requirements? | [docs/isa.md](docs/isa.md), [docs/hardware.md](docs/hardware.md), … |

### The justification rule (the heart of it)

- A **specification or decision justifies itself by citing the requirement(s) it
  satisfies — by ID — and on its own technical merits.** Nothing else counts as a
  reason.
- **Do not reach transitively past a requirement to a goal.** "Because we want to
  run FUZIX" is not a valid reason for a spec; the *requirement* derived from that
  goal is.
- **Never appeal to an external architecture** — "because the 6809 / STM8 / Z80
  does it this way", "to match gcc6809", etc. That is an appeal to authority, not
  a reason. No other architecture may appear in normative text (requirements or
  specs) as a justification.

### Requirements

- Each requirement is a **self-standing, testable statement** written entirely in
  BLIP's own terms.
- Each requirement has a **stable ID** (`R-<AREA>-<n>`) — this is what specs cite —
  and a **traceability link to its source goal** (e.g. `R-MEM-1 ⟸ G3`).
- A requirement is *derived from* a goal; it is not re-argued from the goal.

### External designs are inspiration, never justification

Another design may be the *source* of an idea, but an idea cannot enter the
normative chain by reference. **Promote the insight into a requirement stated in
our own language, then let the spec answer to that requirement.**

Where we want to record *where* an idea came from, it goes in a clearly-marked,
**non-normative "Influences / prior art"** section that justifies nothing. Those
sections are explicitly outside the justification chain. The decision log
([docs/decision-log.md](docs/decision-log.md)) is the canonical home for decisions,
the alternatives weighed, and the outside designs that informed them.

### Before / after

❌ "16-bit values are returned in `X` because STM8 and gcc6809 return in `X`,
since 16-bit values are usually pointers."

✅ Requirement `R-RET-PTR ⟸ G2`: *A returned 16-bit value is most often a pointer
the caller immediately dereferences or indexes, so the return register must
support memory-access addressing modes.*
Decision (isa.md): *Return 16-bit values in `X`, the register with indexed /
auto-increment / offset addressing, so the common return-a-pointer-then-use-it
path needs no register move. Satisfies `R-RET-PTR`.*

The external insight survived; the architecture name did not.

## ID conventions

- **Goals:** `G1`, `G2`, … — defined in [docs/goals.md](docs/goals.md).
- **Requirements:** `R-<AREA>-<n>` — e.g. `R-MEM-1`, `R-ISA-3`, `R-DBG-2`.
  Suggested areas: `MEM` (memory/MMU), `ISA`/`CPU` (instruction set, registers),
  `IO`, `DBG` (debug / front panel), `BUILD` (toolchain), `CLK` (timing).
  Defined in [docs/requirements.md](docs/requirements.md).
- **Specs** cite requirement IDs inline, e.g. "(satisfies `R-MEM-1`, `R-MEM-2`)".
