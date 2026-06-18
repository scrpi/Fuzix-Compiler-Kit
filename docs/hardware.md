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
- **Legible at the component level** (goal **G5**): the architectural registers,
  the ALU, and the internal buses are *individually visible discrete parts*
  (R-HW-4) — never collapsed into an addressed register-file SRAM. You can point at
  each register and watch it change; this is why the datapath uses discrete
  registers rather than a RAM file.
- **Everything is displayable** (goal **G6**): every bus and architectural
  register is latched/buffered so the value driving the LEDs is stable and
  legible. This biases the datapath toward *registered* points rather than long
  combinational chains.
- **Microcoded** (goal **G8**): the control unit is a small writable-control-
  store sequencer, not a sea of random logic. New behaviour = new microcode.

---

## 2. Datapath overview

BLIP has a **16-bit core**: one 16-bit ALU and 16-bit internal buses, with 8-bit
operations (`A`, `B`) using the low lane. Most architectural registers are 16-bit,
so a 16-bit datapath keeps pointer and effective-address math single-pass (G2, G9),
and the register set is **discrete and individually visible** (G5 / R-HW-4) — no RAM
register file. (Architecture decided in D-34.)

```
   S  ========================================================  (16-bit source)
      |     |     |     |     |     |     |     |
    D=A:B   X     Y    USP   SSP    PC   MAR  TEMP   discrete 16-bit registers
      |     |     |     |     |     |     |     |    (each: drive S, latch R)
   R  ========================================================  (16-bit result)
                                                    ^
                          +------------+            |
              S ---> in-1 |  16-bit    | result --> R
              L ---> in-2 |    ALU     |--> flags --> CC
                          | +-&|^ <<>> |
                          |  inc/dec   |
                          +------------+
              L = ALU operand latch (loaded from S a microcycle earlier)

   +1 incrementer --> PC, MAR   (off-bus: PC++ and 16-bit byte-stepping)
   MAR (16-bit logical) --> [ MMU: 8 KB pages, SRAM table ] --> physical A[23:0]
   MDR (8-bit) <--> external D[7:0]    (16-bit transfer = two byte cycles)
```

- **16-bit core (D-34).** One 16-bit ALU and 16-bit buses; 8-bit ops use the low
  lane. The 16-bit register set (D-07) makes this the natural fit and keeps
  pointer/EA math single-pass (G2, G9), with one uniform ALU primitive for microcode
  (G8 / R-CTRL-4).
- **Discrete register file (G5 / R-HW-4 / D-33).** Each register is its own latch
  with its own display buffer: `D`(=`A:B`), `X`, `Y`, `USP`/`SSP` (active `SP` gated
  by `CC.M`), `PC`, the working `MAR` and `TEMP` (16-bit), and `IR` / postbyte
  (8-bit). No addressed RAM file — every register is a point you can watch.
- **Two buses (D-34).** A 16-bit **source bus S** (any register drives) and a 16-bit
  **result bus R** (any register latches). The ALU reads input 1 live from S and
  input 2 from an **operand latch L** (loaded from S a microcycle earlier), result to
  R. A register move is an ALU pass-through (S->R); a two-operand op (e.g. EA `X+n`)
  is two microcycles — load `L`, then operate. Two buses rather than three because
  the 8-bit external memory makes the machine **memory-bound**, so a third bus's
  parallelism would rarely show in wall-clock, while two keep the drivers and the
  front panel simpler.
- **16-bit ALU.** add/sub, logic, shifts, inc/dec, compare; 8-bit mode on the low
  lane; flags `N Z V C` + half-carry -> `CC`. One ALU serves data math, pointer math,
  *and* effective-address computation — the 16-bit core removes the need for a
  separate address adder. Part choice (cascaded adders + logic mux vs ALU slices) is
  TBD (§9).
- **Dedicated address incrementer (D-34).** `PC` and `MAR` have a +1 incrementer off
  the S/R buses, so `PC++` on every fetch and the byte-stepping inside a 16-bit
  (two-byte) access happen without occupying the ALU or buses — overlapping the memory
  cycle (G9). This keeps fetch and pointer loads/stores cheap on a 2-bus datapath.
- **Memory interface.** `MDR` interfaces the **8-bit** external data bus `D[7:0]`;
  16-bit values move as two byte cycles (little-endian, D-09), the incrementer
  stepping `MAR` between them. `MAR` (16-bit logical) feeds the internal MMU (§3),
  which drives the 24-bit physical address off the CPU.

> **Decided (D-34):** 16-bit core; two buses (S + R, with an ALU operand latch);
> discrete registers; a dedicated address incrementer. The internal **bus count fell
> out** of this — *two*, because the 8-bit external memory makes the machine
> memory-bound. Remaining datapath detail (ALU parts, control-word width, pipeline
> depth) is in §9.

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
- **Dispatch — how `µPC` reaches a routine (concrete).** A routine is selected by
  *forming the microaddress from instruction bits*, not by a lookup table: the opcode
  in `IR` supplies the high bits of `µPC` (each opcode owns a fixed block of the
  control store) and the within-routine step supplies the low bits, so "dispatch on
  `IR`" is address wiring plus an increment — no decode memory in the path. The indexed
  **postbyte** is treated the same way: its mode field is OR'd into a base microaddress
  to land on the *shared* effective-address sub-routine, while its register-select field
  rides along as a datapath mux setting, so one EA routine serves every index register.
  There is deliberately **no mapping PROM/ROM** (and no separate lookup memory) on the
  dispatch path: a non-volatile lookup would reintroduce the per-cycle access latency
  that R-CTRL-2 — and the boot-copy of microcode into fast SRAM
  ([decision-log](decision-log.md) D-03) — exist to remove. Dispatch indexes the same
  fast WCS the rest of the microcode runs from, and routine placement (hence the "map")
  lives in the patchable boot-copied image (R-CTRL-1, R-CTRL-2, R-CTRL-3).
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
  ROM + the SRAM + a little sequencing.) This is the mechanism behind goal G8's
  "fast at runtime, hackable at the bench."
- **Privilege & traps in microcode:** the user→supervisor switch on traps/
  interrupts (and its reversal on `RTI`), the `SSP`/`USP` bank select, the MMU
  map-set switch, and privileged-instruction checks are all handled in microcode
  at fetch/trap time — no extra random logic.
- **Pipelining for speed:** the control word is **registered** (latched) so the
  WCS lookup for microstep *n+1* overlaps the execution of microstep *n*, keeping
  the SRAM access off the critical path. Instruction fetch likewise overlaps
  where possible. (Goal G9.)

> **Open:** horizontal vs partly-vertical microcode (width vs ROM size);
> single-level vs nano/two-level store; how deep to pipeline (more stages = more
> clock, more hazards to manage in microcode).

---

## 5. Clocking & timing (the 10 MHz aspiration)

- **Target:** 10 MHz (100 ns) is the *aspiration* (goal G9), not a gate.
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

The front panel is a first-class subsystem (goal **G6**), modeled on classic
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
- **Interrupts:** `IRQ`/`NMI` lines (see [isa §6](isa.md#6-system--privileged-behaviour-for-fuzix))
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
| Discrete 74AHCT datapath (16-bit, two-bus) | G1, G5, G9 | ALU parts (§9) |
| Discrete register file (16-bit) | G2, G5 | — |
| 16-bit ALU + dedicated address incrementer | G2, G9 | ALU parts (§9) |
| Internal MMU (logical→physical) | G3, G4 | extra map sets (§3) |
| Microsequencer + writable control store | G8, G9 | microcode width, pipelining (§4) |
| Boot-copy ROM→SRAM circuit | G8 | — |
| Front panel + bus mastering | G6 | step granularity (§6) |
| UART / timer / storage / IRQ | G3 | parts allowance under G1 (§7) |

---

## 9. Open questions for this document

1. **Datapath architecture:** *(decided — D-34: 16-bit core; two buses, S + R with
   an ALU operand latch; discrete registers; a dedicated address incrementer.)*
2. **ALU implementation:** discrete adders + logic-op mux vs 74-181/381 slices, and
   how the flags are generated. (16-bit width and the dedicated address incrementer
   are decided — D-34.)
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
