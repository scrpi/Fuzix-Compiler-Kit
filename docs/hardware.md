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

> **Status — tentative working direction** (refines D-34; under active iteration as the
> microcode and timing are worked out, so expect it to mutate). Open questions are flagged
> at the end of this section and in §9.

BLIP has a **16-bit core**: one 16-bit ALU and 16-bit internal buses, with 8-bit
operations (`A`, `B`) on the low lane. Registers are **discrete and individually visible**
(G5 / R-HW-4). Operands reach the ALU over an *asymmetric* pair of source buses and
results return on a third:

- **LEFT** — *any* register can drive it -> the ALU's left input.
- **RIGHT** — only the **two scratch registers** and a **constant generator** drive it ->
  the ALU's right input.
- **Z** (result) — the ALU drives it; *any* register latches from it. (Named **Z**, not
  R, to avoid confusion with RIGHT; it is the former D-34 "result bus".)

```
  LEFT  ===+====+====+====+====+====+====+====+====+==========   any register --> ALU left
       |   |    |    |    |    |    |    |    |    |
     D=A:B X    Y   USP  SSP   PC  MAR  SCR1 SCR2               discrete 16-bit registers
       |   |    |    |    |    |    |    |    |    |             (drive LEFT, latch Z)
  Z   ====+====+====+====+====+====+====+====+====+==========   ALU result --> any register

  RIGHT ===========================< SCR1 . SCR2 . const 0/1/2/-1 >   ALU right input
                                     (scratch registers + constants only)

           +------------------------------+
  LEFT  -->|          16-bit ALU          |
  RIGHT -->|  + - & | ^  << >>  inc/dec   |--> Z      flags --> CC
           +------------------------------+
```

- **16-bit core.** One 16-bit ALU and 16-bit buses; 8-bit ops on the low lane. The one
  ALU does data, pointer, and effective-address math.
- **Discrete register file (G5 / R-HW-4 / D-33).** `D`(=`A:B`), `X`, `Y`, `USP`/`SSP`
  (active `SP` gated by `CC.M`), `PC`, `MAR`, and **two scratch registers** `SCR1`/`SCR2`,
  plus 8-bit `IR` / postbyte. The scratch registers can drive LEFT, RIGHT, or both at once.
- **Asymmetric source buses.** Putting *all* registers only on LEFT and limiting RIGHT to
  the scratch registers + constants is the cheap part of a third source bus — RIGHT carries
  a handful of drivers, so it avoids a second bus buffer on every register (see the
  chip-count reasoning, §8/§9). The trade: `anyreg OP scratch` and `anyreg OP const` are
  **one** microcycle, but `anyreg OP anyreg` is **two** (stage the second operand into a
  scratch first).
- **Constant generator.** A small unit places `0`, `1`, `2`, or `-1` on RIGHT, so `reg+1`,
  `reg-1`, `reg+2`, and `reg+0` (= move) are single ALU ops on *any* register, with no
  register tied up holding a small constant.
- **16-bit ALU.** add/sub, logic, shifts, inc/dec, compare; flags `N Z V C` + half-carry
  --> `CC`. Part choice TBD (§9).
- **Memory interface.** `MDR` interfaces the **8-bit** external data bus `D[7:0]`; 16-bit
  values move as two byte cycles (little-endian, D-09). `MAR` (16-bit logical) feeds the
  MMU (§3). To keep the front-panel shadow display (§6) correct, **every register write is
  posted on the Z bus** — including `MDR` on a memory read.

> **Open (this direction):**
> - **Address increment vs overlap.** D-34 added a dedicated *off-bus* incrementer for
>   `PC`/`MAR`. The constant generator now does `reg+1`/`reg+2` through the ALU --> Z, which
>   is simpler and keeps the write visible on Z (the §6 shadow needs *all* writes on Z) —
>   but loses the off-bus overlap. Open: drop the incrementer, keep it for overlap, or have
>   it also post its result on Z.
> - **One scratch register or two?** Two allow holding two staged operands (and
>   `scratch OP scratch`); one may suffice. Decide once the microcode shows real demand.

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
- **Register display via shadow registers (tentative).** Rather than tap every CPU
  register independently (16 × N wires), the panel carries a bank of **shadow
  registers** that listen to the **Z (result) bus**: when a CPU register latches Z, its
  shadow latches the same value (driven by the same load strobe), and the panel drives
  its LEDs from the local shadows. This needs only the **Z bus + one load strobe per
  register + a clock** routed to the panel (tens of wires, not hundreds), and it lets the
  CPU's own registers keep **no permanent display tap** — so LEFT-only registers can stay
  efficient integrated latch+driver parts (§2). It also defines, cheaply, the
  register-visibility half of the privileged debug interface (D-13): the panel observes
  Z + the load strobes rather than every register.
  - *Correctness condition:* the shadows are accurate only if **every register write is
    posted on Z** (see §2) — which is why the address-increment question (§2) matters
    here too; an off-bus increment would silently desync the shadow.
- **Bus & sequencing display.** The LEFT, RIGHT, and Z buses plus key sequencing state
  (`IR`, `CC`, `µPC`, MMU page regs) are buffered to LED banks; because each displayed
  point is a latch output, the lights stay legible free-running, single-stepped, or
  stopped.

> **Open:** instruction-level vs microstep-level single-step default. **Shadow
> registers** (above) vs a multiplexed "selected register" display — shadow is the
> leading idea (every register visible continuously), conditional on §2's "all writes
> posted on Z".

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
| Discrete 74AHCT datapath (16-bit; LEFT/RIGHT/Z — tentative) | G1, G5, G9 | scratch count · incrementer (§9) |
| Discrete register file (16-bit, + 2 scratch) | G2, G5 | 1 vs 2 scratch (§9) |
| 16-bit ALU + constant generator (`0/1/2/-1`) | G2, G9 | ALU parts · incrementer (§9) |
| Internal MMU (logical→physical) | G3, G4 | extra map sets (§3) |
| Microsequencer + writable control store | G8, G9 | microcode width, pipelining (§4) |
| Boot-copy ROM→SRAM circuit | G8 | — |
| Front panel + bus mastering | G6 | step granularity (§6) |
| UART / timer / storage / IRQ | G3 | parts allowance under G1 (§7) |

---

## 9. Open questions for this document

1. **Datapath architecture (tentative — refines D-34, see §2):** 16-bit core; **LEFT**
   bus (all registers) + **RIGHT** bus (the two scratch registers + a constant generator
   `0/1/2/-1`) into the ALU, results on the **Z** bus; discrete registers. Open:
   **(a)** keep D-34's off-bus `PC`/`MAR` incrementer, drop it for `reg+const` through the
   ALU → Z, or have it post on Z (the §6 shadow needs every write on Z); **(b)** **two
   scratch registers or one?**
2. **ALU implementation:** discrete adders + logic-op mux vs 74-181/381 slices; flag
   generation; the constant generator on RIGHT.
3. **MMU:** *(decided: 8 KB pages, 16 MB physical, kernel/user map sets.)*
   Remaining: translation-only vs per-page protection bits.
4. **Microcode:** control-word width and field layout; horizontal vs two-level;
   pipeline depth.
5. **Front panel:** instruction-step vs microstep default; **shadow-register**
   display (§6, leading) vs a multiplexed "selected register" display.
6. **Peripherals & G1 boundary:** confirm which non-74-series support chips are
   acceptable.
7. **Realization:** *(decided: simulation-first, then hardware.)*
8. **Privilege model:** confirm supervisor/user modes + banked `SSP`/`USP`
   (assumed throughout) — adds microcode/state.
