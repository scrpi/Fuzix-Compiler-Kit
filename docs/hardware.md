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

- **74-series only for the CPU** (goal **G1**). Working families: **74AHCT** for SSI
  (gates, buffers, registers, latches) and **74ACT** for the MSI parts AHCT does not offer
  (counters, and the ALU/adder slices). Both are 5 V with TTL-compatible inputs, so they
  share one signaling regime and mix with the slower glue and memory; a few ns/gate, fast
  enough to chase 10 MHz (D-02, D-37).
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
  plus 8-bit `IR`. The scratch registers can drive LEFT, RIGHT, or both at once.
- **Asymmetric source buses.** Putting *all* registers only on LEFT and limiting RIGHT to
  the scratch registers + constants is the cheap part of a third source bus — RIGHT carries
  a handful of drivers, so it avoids a second bus buffer on every register (see the
  chip-count reasoning, §8/§9). The trade: `anyreg OP scratch` and `anyreg OP const` are
  **one** microcycle, but `anyreg OP anyreg` is **two** (stage the second operand into a
  scratch first).
- **Constant generator.** A small unit places `-2`, `-1`, `0`, `+1`, or `+2` on RIGHT, so
  `reg±1`, `reg±2`, and `reg+0` (= move) are single ALU ops on *any* register, with no
  register tied up holding a small constant. The `±2` cases cover 16-bit stack steps
  (`SP±2`) and word-pointer `++`/`--` (D-36).
- **16-bit ALU.** add/sub, logic, shifts, inc/dec, compare; flags `N Z V C` + half-carry
  --> `CC`. Part choice TBD (§9).
- **Memory interface.** `MDR` interfaces the **8-bit** external data bus `D[7:0]`; 16-bit
  values move as two byte cycles (little-endian, D-09). `MAR` (16-bit logical) feeds the
  MMU (§3). To keep the front-panel shadow display (§6) correct, **every register write is
  posted on the Z bus** — including `MDR` on a memory read.

> **Decided (D-36):** address increment — off-bus `+1` up-counters on `PC`/`MAR`/`X`/`Y`;
> `USP`/`SSP` and all `+2`/`-1`/`-2` via the ALU + constant generator (§2.1).
>
> **Open:** one scratch register or two? Two allow holding two staged operands (and
> `scratch OP scratch`); one may suffice — decide once the microcode shows real demand.

### 2.1 Address increment — off-bus counters

**Decided (D-36):** `PC`, `MAR`, `X`, and `Y` are **loadable synchronous up-counters**, so
`+1` is a control line on the register — internal to the chip and clear of the LEFT/RIGHT/Z
buses and the ALU. `USP`/`SSP` and all `+2`/`-1`/`-2` steps use the ALU + constant generator
instead (see *which registers, and why only `+1`* below). The off-bus incrementer is **not**
a separate adder block — the count is folded into the register.

- **Per register:** 4× **74ACT163** (4-bit synchronous binary counter with synchronous
  load), cascaded via the terminal-count → count-enable chain into one 16-bit counter, plus
  a `'244` pair to gate the value onto LEFT. Three operations:
  - **load** (`/PE`) — parallel-load from Z (branch, computed `EA`, reset vector);
  - **count** (`CEP`/`CET`) — `+1`, off the buses and the ALU;
  - **hold** — neither.
  The `'163` outputs are permanent, so they feed the LEDs / shadow directly. The counters
  are **up-only**; decrements are not a counter operation here.
- **Cost:** ~4 chips for a 16-bit counter vs ~2 for a plain latch — about **+2 chips per
  register** (on top of the `'244` both need anyway), plus one count strobe routed to the
  panel shadow (below).
- **Shadow.** A counter's `+1` never appears on Z, so each panel shadow for a counter
  register is *itself* a counter, advanced by the same count strobe (routed to the panel
  alongside Z and the load strobes, §6) — keeping the shadow correct without giving up the
  off-bus increment.
- **Shared-adder alternative (rejected):** one 16-bit `'283`-based adder with a constant on
  one input and the selected register muxed onto the other — more chips and muxing, only
  worth it as a shared `+N` unit. Counters are cleaner for plain `+1`.

**Which registers, and why only `+1`.** A `'163` counter is a `+1`, up-only, off-bus device,
so it earns its place only where `+1` dominates; for `+2`/`-1`/`-2` the ALU + constant
generator already does the job in one cycle and a counter offers nothing.

- **`PC`, `MAR` — pure `+1`.** Fetch walks the instruction stream byte-by-byte (`PC+1`); a
  multi-byte access walks consecutive bytes (`MAR+1`). ~100% `+1` → the counter is ideal.
- **`X`, `Y` — `+1` for byte pointers.** `char *p++` and byte copy/compare loops
  (`*d++ = *s++`) step `+1`; making *both* index registers counters lets them advance
  off-bus and overlap the memory access — the hot FUZIX idiom. Word `*p++` (`+2`) and
  pre-decrement fall back to the ALU.
- **`USP`, `SSP` — no counter.** Stack traffic is `±2`-and-decrement dominated (every call
  is `SP-2`; 16-bit save/restore is `±2`; frame setup/teardown is `±N`). The only `+1` case
  (8-bit pull) is a minority, and its partner 8-bit push is a `-1` a counter can't do. So
  `SP` steps through the ALU + constant generator (`±1`/`±2`) and the ALU (`±N`).

**`±1` vs `±2` frequency** (the basis for the split): `+1` dominates raw counts — fetch
(every byte) and multi-byte byte-stepping are the highest-frequency steps in the machine.
`+2` is the main non-unit step (word pointers, 16-bit stack); `-1`/`-2` are rarer
(pre-decrement). The constant generator covers all of `{-2, -1, 0, +1, +2}` in one ALU
cycle, so the non-`+1` cases need no dedicated hardware.

### 2.2 Why a memory-address register (MAR)

`MAR` holds the 16-bit logical address presented to the MMU for a memory access. It earns
a dedicated register on three grounds:

- **A computed address has no other home.** The common access `LD A,(X+n)` forms its
  address as `X + offset` in the ALU — a transient value on Z, held in no architectural
  register. Capturing it in `MAR` frees Z and the ALU the instant the access starts, so the
  datapath can move on while memory responds.
- **The address must stay valid across the whole access.** External memory is 8-bit, so a
  16-bit access is two byte-cycles, and any access can be stretched by `/WAIT`. A latched
  `MAR` holds the address stable for the full (possibly multi-cycle) access without freezing
  a bus or tying up an architectural register.
- **It decouples the address from its source.** Latching the address into `MAR` lets `PC`
  advance (and the datapath begin the next step) while the read is in flight, and gives the
  MMU one well-defined input to translate and to display.

**Why `MAR` increments.** A 16-bit memory access touches two consecutive bytes — the
address and the address + 1 — because the external bus is 8-bit. The running address lives
only in `MAR`: for a computed effective address there is no register to recompute `+1`
from, and for a register base (`(X)`) stepping the base would clobber the register. So
`MAR` must **step itself by +1** to reach the second (and any further) byte while
preserving the source — the byte-stepping §2.1 identifies as the dominant `+1` case. `MAR`
only ever counts **up** (multi-byte operands are walked low-to-high; decrements belong to
`SP` and the index registers). `MAR` is realised as an off-bus `+1` up-counter (§2.1,
D-36).

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
field directly enables a datapath action), with a **writable control store**. The
word is **88 bits / 11 bytes**, split into two clean chip-aligned sections — a 24-bit
**sequencer section** (WCS SRAMs 0–2) and a 64-bit **datapath section** (SRAMs 3–10),
with no field shared between them. Its full field map, the sequencer detail, and worked
microroutines are specified in [microcode.md](microcode.md) (D-39, refining D-38). This
section is the engine in outline.

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
- **Dispatch — how `µPC` reaches a routine (concrete).** A routine is selected through an
  **opcode→start-address map**: the opcode in `IR` (with the 1-bit `DISPATCH_PAGE`) indexes
  a small **boot-loaded SRAM** of 512 entries whose 13-bit output is the routine's start
  microaddress, loaded into `µPC` (D-40; D-41 added the page bit and removed the indexed
  postbyte). Microroutines are placed **freely and densely** in the WCS — no fixed
  per-opcode block, no word cap — and many opcodes can share a routine by holding the same
  map entry. The map read is **pipelined into the fetch cycle** (opcode→`IR`→map→registered
  start address) on a fast (~10 ns) SRAM, so dispatch adds no steady-state cycle and the
  lookup stays off the cycle-time budget (R-CTRL-2). The ISA is **two opcode pages** (D-41):
  page 0 is the base; page 1 is reached by the prefix byte `0x80`, an ordinary page-0 opcode
  whose one-step routine re-fetches the next byte into `IR` and re-dispatches with
  `DISPATCH_PAGE=1` — page-0 decode pays nothing, a page-1 instruction costs +1 byte and
  +1 cycle. There is **no indexed postbyte**; addressing modes are distinct opcodes. Both
  the map SRAM and the WCS are loaded at reset by the boot-copy circuit from EEPROM, so
  routine placement (the map) is patchable in the field (R-CTRL-1, R-CTRL-3).
- **Control word:** wide (horizontal) so most datapath actions are one microstep;
  fields gate bus drivers, latch registers, select the ALU op, drive `MAR`/MMU,
  and assert memory read/write. **Decided (D-41, refining D-39/D-38):** an **88-bit /
  11-byte** word in **two clean sections** — a 24-bit **sequencer section** (`USEQ_OP`, a
  single 13-bit `NEXT_ADDR`, `UCOND_SEL`, `UCOND_POL`, the `ULOOP` loop counter, and the
  1-bit `DISPATCH_PAGE`) and a 64-bit **datapath section**
  (everything that drives a register/bus/ALU/memory/flag/MMU). No field is shared and
  there is no overlay; per-flag flag control is direct. Full field map and budget in
  [microcode.md](microcode.md) §3.
- **Writable control store (WCS):** the control word ROM image lives in **fast
  static RAM** at runtime. This (a) keeps the control-store access fast enough to
  chase 10 MHz, and (b) lets microcode be patched at the bench instead of burning
  ROMs.
- **Boot-copy circuit:** at power-on/reset, a small hardware state machine copies
  the microcode image from a non-volatile **ROM/EEPROM** into the WCS SRAM **and the
  opcode→start-address map SRAM** (D-40), then releases the CPU to run. (Independent of
  the CPU — it's just a counter + the ROM + the SRAM + a little sequencing.) This is the
  mechanism behind goal G8's
  "fast at runtime, hackable at the bench."
- **Privilege & traps in microcode:** the user→supervisor switch on traps/
  interrupts (and its reversal on `RTI`), the `SSP`/`USP` bank select, the MMU
  map-set switch, and privileged-instruction checks are all handled in microcode
  at fetch/trap time — no extra random logic.
- **Pipelining for speed:** the control word is **registered** (latched) so the
  WCS lookup for microstep *n+1* overlaps the execution of microstep *n*, keeping
  the SRAM access off the critical path. Instruction fetch likewise overlaps
  where possible. (Goal G9.)

> **Decided (D-41, refining D-39/D-38):** horizontal, single-level, **88-bit / 11-byte**
> word in two clean chip-aligned sections (sequencer 3 SRAMs + datapath 8 SRAMs), no shared
> field, no overlay, with a single 13-bit `NEXT_ADDR` (8192-word store) and a 1-bit
> `DISPATCH_PAGE` for the two-page opcode map; the indexed postbyte is removed. See
> [microcode.md](microcode.md). **Open:** how deep to pipeline (microcode.md §7).

---

## 5. Clocking & timing (the 10 MHz aspiration)

- **Target:** 10 MHz (100 ns) is the *aspiration* (goal G9), not a gate.
- **Budget reality:** at ~5 ns/gate for 74AHCT/ACT, a 100 ns cycle allows perhaps a
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
  - *Correctness condition:* the shadows track only what appears on **Z**. The counter
    registers (`PC`/`MAR`/`X`/`Y`, D-36) increment *off* Z, so each of their shadows is
    itself a counter advanced by the same count strobe (routed to the panel alongside Z +
    the load strobes); every other register write is posted on Z.
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
| Discrete 74AHCT/ACT datapath (16-bit; LEFT/RIGHT/Z — tentative) | G1, G5, G9 | scratch count (§9) |
| Discrete register file (16-bit, + 2 scratch; PC/MAR/X/Y are counters) | G2, G5 | 1 vs 2 scratch (§9) |
| 16-bit ALU + constant generator (`-2..+2`) | G2, G9 | ALU parts (§9) |
| Internal MMU (logical→physical) | G3, G4 | extra map sets (§3) |
| Microsequencer + writable control store (88-bit word, 2 sections — [microcode.md](microcode.md)) | G8, G9 | pipeline depth (§4) |
| Boot-copy ROM→SRAM circuit | G8 | — |
| Front panel + bus mastering | G6 | step granularity (§6) |
| UART / timer / storage / IRQ | G3 | parts allowance under G1 (§7) |

---

## 9. Open questions for this document

1. **Datapath architecture (tentative — refines D-34, see §2):** 16-bit core; **LEFT**
   bus (all registers) + **RIGHT** bus (the two scratch registers + a constant generator
   `{-2,-1,0,+1,+2}`) into the ALU, results on the **Z** bus; discrete registers. Address
   increment is **decided** — off-bus `+1` counters on `PC`/`MAR`/`X`/`Y`, the rest via the
   ALU (D-36, §2.1). Still open: **two scratch registers or one?**
2. **ALU implementation:** discrete adders + logic-op mux vs 74-181/381 slices; flag
   generation; the constant generator on RIGHT.
3. **MMU:** *(decided: 8 KB pages, 16 MB physical, kernel/user map sets.)*
   Remaining: translation-only vs per-page protection bits.
4. **Microcode:** *(decided: horizontal 88-bit / 11-byte word in two clean sections
   (sequencer + datapath) — D-41 (refining D-39/D-38), [microcode.md](microcode.md);
   single 13-bit `NEXT_ADDR`, two-page opcode map (`DISPATCH_PAGE`), no postbyte,
   `PC`-direct fetch.)* Remaining: pipeline depth (microcode.md §7).
5. **Front panel:** instruction-step vs microstep default; **shadow-register**
   display (§6, leading) vs a multiplexed "selected register" display.
6. **Peripherals & G1 boundary:** confirm which non-74-series support chips are
   acceptable.
7. **Realization:** *(decided: simulation-first, then hardware.)*
8. **Privilege model:** confirm supervisor/user modes + banked `SSP`/`USP`
   (assumed throughout) — adds microcode/state.
