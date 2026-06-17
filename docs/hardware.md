# BLIP — Hardware Architecture

> How the silicon realizes the ISA. For the programmer's contract see
> [docs/isa.md](isa.md); for *why* see [docs/goals.md](goals.md).
>
> **Status:** design direction, v0. Subsystem responsibilities and the
> microarchitecture style are settled in outline; gate-level schematics, exact
> part choices, and timing budgets are in progress. Open questions are flagged
> throughout.

---

## 1. Build constraints that shape everything

- **74-series only for the CPU** (goal **G1**). Working family: **74AHCT** —
  fast enough (a few ns/gate) to chase 10 MHz, 5 V, TTL-compatible inputs so it
  mixes with the slower glue and memory.
- **Everything is displayable** (goal **G7**): every bus and architectural
  register is latched/buffered so the value driving the LEDs is stable and
  legible. This biases the datapath toward *registered* points rather than long
  combinational chains.
- **Microcoded** (goal **G5**): the control unit is a small writable-control-
  store sequencer, not a sea of random logic. New behaviour = new microcode.

---

## 2. Datapath overview

```
            +-------------------------------------------------+
            |                  8-bit DATA BUS                 |
            +--+------+------+------+------+------+------+-----+
               |      |      |      |      |      |      |
              A/B    D/X/Y  SP/PC   CC     ALU    MDR   (regfile read/write ports)
               |      |      |      |      |      |
            +--v------v------v------v------v------v--+
            |            register file               |
            +----------------------+------------------+
                                   |
                              +----v----+        +-----------------+
                              |   ALU   |<------>|  ALU temp TA/TB  |
                              +----+----+        +-----------------+
                                   |
                       +-----------v-----------+
                       | 16-bit ADDRESS path   |---> MAR --> [ MMU ] --> physical bus
                       +-----------------------+
```

- **Data bus:** 8 bits — BLIP is an 8-bit machine; 16-bit values move as two
  byte transfers (or via a dedicated 16-bit internal path; **TBD**, see §9).
- **Register file:** holds `A B (D) X Y USP SSP PC CC` (see [isa §2](isa.md#2-programming-model-register-file-v0)),
  with `USP`/`SSP` banked by the supervisor/user mode bit so the active `SP` is
  selected by privilege. 16-bit registers are two 8-bit slices with shared
  increment/decrement so `PC`, the active `SP`, `X`, `Y` can self-modify (for
  fetch, push/pull, auto-inc/dec) without the ALU.
- **ALU:** 8-bit, with the four ALU flags (`N Z V C`) plus half-carry. Candidate
  implementations: cascaded **74AHCT283** adders + a logic-op mux, or classic
  **74-181/74-381** ALU slices. 16-bit ops (`ADDD`, address math) are done as two
  8-bit passes with carry, sequenced by microcode. **TBD** (see §9).
- **Internal temp registers `TA`/`TB`** latch ALU operands so operand fetch and
  compute are separate microcycles — important for both timing and clean display.

> **Open:** one shared 8-bit bus vs a two-bus (A/B operand) or three-bus design.
> More buses = fewer microcycles per instruction (helps G6) at the cost of parts
> and a busier front panel. This is the central datapath tradeoff.

---

## 3. Memory & address translation (>64 KB)

Address translation lives **inside** the CPU: the datapath forms a 16-bit logical
address internally, the internal MMU translates it to a 24-bit physical address,
and the **physical** address is what leaves the CPU on the external bus. The
programmer's model stays a flat 16-bit logical space (R-MEM-1); the larger
physical space and its partitioning are invisible to ordinary code.

```
  logical address (16-bit)            physical address (e.g. 24-bit)
  +----+-----------------+            +-----------+-----------------+
  | pg |     offset      |  ----->    |  phys pg  |     offset      |
  +-+--+-----------------+            +-----+-----+-----------------+
    |     internal page table                ^
    +---- top bits index --> wider phys bits-+
```

- **Translation (decided).** With 8 KB pages the low **13 offset bits** pass
  straight through. The top **3 logical bits** select one of **8 page slots**;
  each slot holds an **11-bit physical page number** that drives `PA13–PA23`. The
  physical address is 24-bit → **16 MB** = **2048** physical 8 KB pages (R-MEM-1,
  R-MEM-2, R-MEM-6). The page table is small and fast, and the slot bits are known
  as early as the address is, so translation **overlaps** address generation
  instead of adding a serial stage (R-CLK-1).
- **Page table = internal privileged register file.** Two map sets (kernel and
  user), 8 entries each. The active set follows the privilege mode bit, so kernel
  entry/exit switches maps with no instruction (R-MEM-5). Entries are written only
  in supervisor mode, by privileged `LDMMU`/`STMMU` ([isa.md](isa.md) §6) — so
  user code cannot remap itself (R-CPU-4).
- **Common region.** Some slots map to the same physical pages in *every* map set,
  so the always-resident kernel code and the inter-map copy routines stay reachable
  across a map switch (R-MEM-4).
- **Protection model.** Isolation comes from the per-process map itself — a process
  can only form addresses to its own mapped pages (R-MEM-3) — together with
  privileged map-control instructions, so user code cannot remap itself (R-CPU-4).
  Per-page access protection (read-only / no-access bits with a fault) is a
  **non-goal** (decision log D-18): it would sit in the memory critical path and
  need mid-access aborts, and it is not required for isolation.
- **Reset = identity map.** On reset the table comes up mapping the low 64 KB
  logical onto the low 64 KB physical (logical = physical), so the CPU fetches its
  reset vector and runs before any translation is configured, and the front panel
  can bootstrap into known physical locations (R-MEM-7, R-CPU-7, R-DBG-3).

> **Open:** whether more than the kernel/user pair of map sets earns its registers.
> *(Per-page protection is settled as a non-goal — D-18.)*

---

## 4. Microcode engine

The control unit is a microsequencer driving a **horizontal** control word (each
field directly enables a datapath action), with a **writable control store**.

```
        opcode (from IR) + flags + condition select
                 |
            +----v-----------------+        +------------------------+
            |  next-address logic  |<-------|  microcode SRAM (WCS)  |
            +----+-----------------+        +-----------+------------+
                 |  uPC                                  |
            +----v----+                          control word (wide)
            |  uPC reg|------------------------------>  | bus enables, reg loads,
            +---------+                                 | ALU op, MAR load, mem r/w,
                                                        | uPC next/branch, ...
```

- **Sequencer:** a microprogram counter `µPC` with next-address logic that can
  (a) increment, (b) jump to an opcode's microroutine (dispatch on `IR`),
  (c) conditionally branch on a selected flag/condition, and (d) return to the
  fetch routine. Built from counters/registers + a next-address mux.
- **Control word:** wide (horizontal) so most datapath actions are one microstep;
  fields gate bus drivers, latch registers, select the ALU op, drive `MAR`/MMU,
  and assert memory read/write. **Width and field layout: TBD** (see §9).
- **Writable control store (WCS):** the control word ROM image lives in **fast
  static RAM** at runtime. This (a) keeps the control-store access fast enough to
  chase 10 MHz, and (b) lets microcode be patched at the bench instead of burning
  ROMs.
- **Boot-copy circuit:** at power-on/reset, a small hardware state machine copies
  the microcode image from a non-volatile **ROM/EEPROM** into the WCS SRAM, then
  releases the CPU to run. (Independent of the CPU — it's just a counter + the
  ROM + the SRAM + a little sequencing.) This is the mechanism behind goal G5's
  "fast at runtime, hackable at the bench."
- **Privilege & traps in microcode:** the user→supervisor switch on traps/
  interrupts (and its reversal on `RTI`), the `SSP`/`USP` bank select, the MMU
  map-set switch, and privileged-instruction checks are all handled in microcode
  at fetch/trap time — no extra random logic.
- **Pipelining for speed:** the control word is **registered** (latched) so the
  WCS lookup for microstep *n+1* overlaps the execution of microstep *n*, keeping
  the SRAM access off the critical path. Instruction fetch likewise overlaps
  where possible. (Goal G6.)

> **Open:** horizontal vs partly-vertical microcode (width vs ROM size);
> single-level vs nano/two-level store; how deep to pipeline (more stages = more
> clock, more hazards to manage in microcode).

---

## 5. Clocking & timing (the 10 MHz aspiration)

- **Target:** 10 MHz (100 ns) is the *aspiration* (goal G6), not a gate.
- **Budget reality:** at ~5 ns/gate for 74AHCT, a 100 ns cycle allows perhaps a
  dozen gate-delays — workable for a registered datapath but tight once SRAM
  access, ALU carry propagation, and bus turnaround are counted. The registered
  WCS (§4) and a short, registered datapath are what make it plausible.
- **Strategy:** design for correctness and C-friendliness first; measure the
  critical path; let the achievable clock fall out of it. A clean target is "runs
  correctly single-stepped and at whatever continuous clock the critical path
  supports, aiming at 10 MHz."

> **Decided:** v1 is proven in **simulation first** (Logisim Evolution / Digital
> / Verilog), where 10 MHz is "free", then built in hardware against the sim as a
> reference model. **Open:** single fixed clock vs a variable/stretchable clock
> for slow memory cycles.

---

## 6. Front panel & bus mastering (functional blinkenlights)

The front panel is a first-class subsystem (goal **G7**), modeled on classic
deposit/examine panels (Altair/PDP-8 lineage):

- **Bus mastering:** when halted, the CPU tri-states the address/data/control
  buses and the **panel takes the bus** (DMA-style). A clean `HALT`/grant
  handshake in the control unit makes this safe. Because the MMU is internal and
  tri-stated with the CPU, the panel drives **physical** addresses directly to
  memory — so bootstrap needs no translation setup (R-MEM-7, R-DBG-3).
- **Controls:** `RUN` / `STOP`, `SINGLE-STEP` (one instruction *or* one
  microstep — both are useful for debugging microcode), `EXAMINE` (read the
  address in the switches), `DEPOSIT` (write the switches to memory and advance),
  and `RESET`.
- **Bootstrap:** the panel can deposit a bootstrap by hand into RAM and start
  execution there — enough to bring the machine up from nothing.
- **Display:** address bus, data bus, and the key registers (`PC`, `IR`, `CC`,
  `µPC`, MMU page regs) are buffered to LED banks. Because every displayed point
  is a latch output, the lights are legible whether free-running, single-stepped,
  or stopped.

> **Open:** does single-step default to instruction-level or microstep-level (or
> a switch between them)? How much state gets dedicated LEDs vs a multiplexed
> "selected register" display?

---

## 7. Peripherals required for FUZIX

The minimum board to boot FUZIX to a shell (goal **G3**):

- **Console:** a serial UART (e.g. a 16C550-class part) — the FUZIX `tty`.
- **Timer:** a periodic interrupt source for the scheduler tick (FUZIX wants a
  steady tick, conventionally a multiple of 10 Hz).
- **Storage:** a block device — CompactFlash/IDE or an SD interface — for the
  root filesystem and swap.
- **Interrupts:** `IRQ`/`FIRQ`/`NMI` lines (see [isa §6](isa.md#6-system--privileged-behaviour-for-fuzix))
  with a simple priority/vectoring scheme; a small interrupt controller or
  daisy-chain. **TBD.**
- **Boot ROM:** holds the microcode image (for the WCS boot-copy, §4) and an
  initial bootstrap/monitor.

> **Open:** are these support chips (UART, CF/IDE, interrupt glue) acceptable as
> non-CPU peripherals under G1's "support functions" allowance? (They were never
> the point of the build, but they are not 74-series.) Confirm the line.

---

## 8. Subsystem responsibility map

| Subsystem | Realizes goal | Key open question |
|-----------|---------------|-------------------|
| Discrete 74AHCT datapath | G1, G6 | bus count (§2) |
| Register file with self-inc/dec 16-bit regs | G2 | — |
| 8-bit ALU + carry-sequenced 16-bit ops | G2 | ALU implementation (§2/§9) |
| Internal MMU (logical→physical) | G3, G4 | per-page protection bits (§3) |
| Microsequencer + writable control store | G5, G6 | microcode width, pipelining (§4) |
| Boot-copy ROM→SRAM circuit | G5 | — |
| Front panel + bus mastering | G7 | step granularity (§6) |
| UART / timer / storage / IRQ | G3 | parts allowance under G1 (§7) |

---

## 9. Open questions for this document

1. **Bus architecture:** one shared 8-bit bus vs two/three buses (microcycles
   per instruction vs part count). *Most impactful single decision here.*
2. **ALU implementation:** discrete adders + logic mux vs 74-181/381 slices; how
   16-bit ops are sequenced; is there a dedicated 16-bit increment path for
   addresses?
3. **MMU:** *(decided: 8 KB pages, 16 MB physical, kernel/user map sets.)*
   Remaining: translation-only vs per-page protection bits.
4. **Microcode:** control-word width and field layout; horizontal vs two-level;
   pipeline depth.
5. **Front panel:** instruction-step vs microstep default; dedicated vs
   multiplexed register display.
6. **Peripherals & G1 boundary:** confirm which non-74-series support chips are
   acceptable.
7. **Realization:** *(decided: simulation-first, then hardware.)*
8. **Privilege model:** confirm supervisor/user modes + banked `SSP`/`USP`
   (assumed throughout) — adds microcode/state.
