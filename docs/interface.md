# BLIP — CPU/System Interface

> The **functional interface**: the fixed set of external signals through which the
> CPU connects to memory and I/O. This signal set *is* the boundary between the CPU
> and the rest of the machine (goal **G6**). For *why* this boundary exists see
> [docs/goals.md](goals.md); for the programmer's model see [docs/isa.md](isa.md);
> for the internals behind these signals see [docs/hardware.md](hardware.md).
>
> **Status:** a **v0 draft** under active design review. The signal set and the
> design choices behind it (bus timing, strobes, bus layout, interrupts, clock,
> arbitration) are confirmed; the exact CLK-edge timing numbers wait on the datapath
> bus-count decision (still pending), and the **privileged debug interface**
> ([D-13](decision-log.md)) is deferred to a later revision — see §7.

---

## 1. The boundary

The CPU is a self-contained module. Every interaction with the *functional* parts
of the system — memory, and (because I/O is memory-mapped, [D-28](decision-log.md))
peripherals — happens through the signals defined here, and **no functional
peripheral depends on any signal internal to the CPU** (satisfies `R-IF-1`).

The interface is **stable**: the CPU's internals may be revised or reimplemented
without changing this signal set or its timing contract, so existing peripherals
keep working (satisfies `R-IF-6`). That stability is the contract — everything in
this document is what a peripheral or board designer may rely on.

A single privileged exception, the front panel, reaches *past* this boundary
through a separate debug interface (§7). No functional peripheral may use it.

---

## 2. Signal summary

Active-low signals are written with a leading `/`. Directions are relative to the
CPU. "Z on grant" means the signal is tri-stated while the bus is granted to an
external master (§4.6).

| Signal | Width | Dir | Z on grant | Purpose |
|--------|:-----:|:---:|:----------:|---------|
| `A[23:0]` | 24 | out | yes | Physical address ([D-14](decision-log.md)) |
| `D[7:0]`  | 8  | in/out | yes | Data; CPU drives on write, device drives on read |
| `/RD`     | 1  | out | yes | Read strobe |
| `/WR`     | 1  | out | yes | Write strobe |
| `/WAIT`   | 1  | in  | — | Hold request: extend the current bus cycle |
| `CLK`     | 1  | in  | — | Master timing reference |
| `/RESET`  | 1  | in  | — | Reset request → the reset state of §4.4 |
| `/IRQ`    | 1  | in  | — | Maskable interrupt, level-sensitive |
| `/NMI`    | 1  | in  | — | Non-maskable interrupt, edge-triggered |
| `/BUSREQ` | 1  | in  | — | External master requests the buses |
| `/BUSGRANT` | 1 | out | — | CPU has released the buses |

Forty-one architectural signals (plus power and ground, which are not part of the
contract). This is the *whole* functional interface — see §6 for what is
deliberately **absent**.

---

## 3. Signal groups

### 3.1 Address bus — `A[23:0]` (output)
The CPU emits a **24-bit physical address** (16 MB, [D-11](decision-log.md)).
Address translation and protection are internal, so this bus already carries the
final physical address; it conveys no logical address, privilege level, or
translation fault ([D-14](decision-log.md)). The bus is non-multiplexed and held
valid for the whole cycle, so it is always legible to the front panel and
blinkenlights (goal **G5**). Tri-stated on bus grant (§4.6).

### 3.2 Data bus — `D[7:0]` (bidirectional)
Eight bits, one byte per transfer; multi-byte values are little-endian in memory
([D-09](decision-log.md)), assembled by successive byte cycles. The CPU drives `D`
only while `/WR` is asserted (a write); on a read it floats `D` and the addressed
device drives it. Tri-stated on bus grant.

### 3.3 Transfer control — `/RD`, `/WR` (output), `/WAIT` (input)
Reads and writes are framed by **separate strobes**: the asserted strobe encodes
both the direction and the timing of the transfer (satisfies `R-IF-2`). Because I/O
is memory-mapped ([D-28](decision-log.md)) there is no memory-vs-I/O qualifier, and
because there is no separate I/O space the strobes map directly onto memory and
peripheral control pins (e.g. an SRAM's output-enable and write-enable) with no
decode glue. `/RD` and `/WR` are tri-stated on bus grant.

`/WAIT` is an input by which slow memory or a slow device **stretches** a cycle: while
it is asserted at the sample point, the CPU inserts wait states and holds the bus
stable (§4.3). This keeps the fast common case at full clock speed (goal **G8**)
while still admitting slow devices.

### 3.4 Clock and reset — `CLK`, `/RESET` (inputs)
`CLK` is an **input**: a clock-generator module (a permitted support function, see
goals §3) supplies the single master timing reference to which all interface timing
is referenced (satisfies `R-IF-3`). Sourcing the clock externally lets it be gated
or single-stepped for bring-up and blinkenlights (goal **G5**).

`/RESET` is an asynchronous input that drives the CPU to its reset state (§4.4):
supervisor mode, interrupts masked, the low-64 KB identity map, and the reset
vector ([D-15](decision-log.md); satisfies `R-IF-3`, supports `R-CPU-7`).

### 3.5 Interrupts — `/IRQ`, `/NMI` (inputs)
Two asynchronous interrupt inputs (satisfies `R-IF-3`):

- **`/IRQ`** — maskable, **level-sensitive**. Multiple devices wire-OR onto it; the
  handler services sources until the line releases. Honoured only when `CC.I` is
  clear.
- **`/NMI`** — non-maskable, **edge-triggered** (a falling edge latches an internal
  pending flag). Honoured regardless of `CC.I`; the pending flag clears on accept.

Interrupts are **fixed-vector (software-polled)**: each transfers to a fixed handler
entry and the handler polls device status to find the source. There is no
interrupt-acknowledge cycle and no device-supplied vector on the bus (see §6). The
entry comes from a fixed in-memory pointer-slot table ([isa.md](isa.md) §6,
[D-30](decision-log.md)); only the table's physical location is deferred to the
reset-vector / memory-map decision. The fast/`FIRQ` input is **not** present — it was
dropped ([D-22](decision-log.md)). Acceptance behaviour (minimal frame, mode/stack/map
switch, auto-mask) is specified in [isa.md](isa.md) §6.

### 3.6 Bus arbitration — `/BUSREQ` (input), `/BUSGRANT` (output)
A two-line request/grant handshake lets an external master take the buses
(satisfies `R-IF-4`, supports `R-DBG-2`): the master asserts `/BUSREQ`; the CPU
finishes the current bus cycle, tri-states `A`, `D`, `/RD`, `/WR`, and asserts
`/BUSGRANT`; the master owns the bus until it releases `/BUSREQ`, whereupon the CPU
deasserts `/BUSGRANT` and resumes (§4.6).

---

## 4. Timing contract

All interface timing is referenced to the **rising edge of `CLK`** (single-phase;
the CPU may derive internal phases, but the interface sees one clock). A bus cycle
is a whole number of `CLK` periods; the **nominal length is fixed once the datapath
bus count is decided** (pending — see §8), with a minimum of two periods and the
`/WAIT` extension below.

### 4.1 Read cycle
1. On a rising edge, the CPU drives `A[23:0]` with the physical address, asserts
   `/RD`, and floats `D[7:0]`.
2. The addressed device decodes `A` and drives `D[7:0]`.
3. At the rising edge that would end the cycle the CPU samples `/WAIT` (§4.3).
4. On the terminating rising edge the CPU latches `D[7:0]`, then deasserts `/RD`.
   `A` may change on the following edge.

### 4.2 Write cycle
1. On a rising edge, the CPU drives `A[23:0]` and `D[7:0]`, and asserts `/WR`.
2. At the rising edge that would end the cycle the CPU samples `/WAIT` (§4.3).
3. On the terminating edge the CPU deasserts `/WR`; the **rising (deasserting) edge
   of `/WR`** is the device's capture reference. `A` and `D` are held valid through
   that edge and may change the following edge.

### 4.3 Wait states
`/WAIT` is sampled on a fixed rising edge of each cycle. While it is asserted the
CPU holds `A`, `D` (on a write), and the active strobe stable and inserts one `CLK`
period, re-sampling each period until `/WAIT` releases — then the cycle terminates
normally (§4.1/§4.2). `/WAIT` has no effect outside a bus cycle.

### 4.4 Reset
`/RESET` is asynchronous and must be held for at least a minimum number of `CLK`
periods (TBD with hardware) to be recognised. While asserted the CPU performs no
transfers (`/RD` and `/WR` held inactive). On release — internally synchronised to
`CLK` — the CPU is in the reset state ([D-15](decision-log.md)): supervisor mode,
`/IRQ` masked, the transparent identity map of the low 64 KB, and instruction fetch
beginning at the reset vector. `/RESET` does **not** tri-state the buses (only bus
grant does, §4.6). The reset-vector **address** is still open — see §8.

### 4.5 Interrupt sampling
`/IRQ` (level) and the latched `/NMI` (edge) are sampled at **instruction
boundaries**, never mid-instruction, so the saved frame is always well-defined.
`/IRQ` is taken only when `CC.I` is clear; `/NMI` is always taken. On acceptance the
CPU finishes the current instruction and performs the entry sequence specified in
[isa.md](isa.md) §6 (switch to supervisor mode and `SSP`, select the kernel map,
push the minimal `{PC, CC}` frame, jump to the fixed handler entry). While the bus
is granted (§4.6) a newly asserted interrupt is held pending — the CPU cannot
service it without the bus.

### 4.6 Bus arbitration
`/BUSREQ` is sampled at a **bus-cycle boundary**. The CPU completes any in-progress
cycle, tri-states `A[23:0]`, `D[7:0]`, `/RD`, and `/WR`, then asserts `/BUSGRANT`.
While `/BUSGRANT` is asserted the CPU initiates no cycles and stays off the bus, but
continues to monitor `/RESET`, `/NMI`, and `/IRQ` (latching any it cannot yet
service). When `/BUSREQ` deasserts, the CPU deasserts `/BUSGRANT` and resumes on the
next cycle. Because the CPU needs the bus to fetch and execute, a held grant stalls
it — this is the mechanism by which the front panel will halt the machine to examine
and deposit memory (supports `R-DBG-2`, `R-DBG-3`); the *internal*-state visibility
the panel also needs comes from the debug interface (§7), not from here.

---

## 5. Conventions

- **Active-low naming.** A leading `/` marks an active-low signal.
- **One clock.** All timing references the rising edge of `CLK`; there is a single
  interface clock phase.
- **Tri-state scope.** Only bus grant (§4.6) tri-states CPU outputs; the set is
  exactly `A[23:0]`, `D[7:0]`, `/RD`, `/WR`. Inputs are always monitored.
- **Data drive.** The CPU drives `D[7:0]` only while `/WR` is asserted; otherwise
  its data drivers are high-Z.

> *Flagged for review (minor conventions chosen as defaults):* `/NMI` active edge =
> falling; `/WAIT` asserted = low (insert wait); single-phase `CLK`; `/RESET`
> minimum hold = TBD. Say if you want any of these set differently.

---

## 6. What is *not* on the functional interface

The earlier decisions deliberately keep these off the boundary — their absence is
part of the contract:

- **No privilege/mode line and no translation-fault/abort line.** Translation and
  protection are internal; the bus carries the final physical address
  ([D-14](decision-log.md); `R-IF-5` retired).
- **No memory-vs-I/O qualifier.** I/O is memory-mapped; the system decodes
  peripherals from physical addresses ([D-28](decision-log.md)).
- **No interrupt-acknowledge cycle and no vector lines.** Interrupts are
  fixed-vector and software-polled (§3.5).
- **No address strobe / ALE.** The buses are separate and non-multiplexed; `/RD` and
  `/WR` frame every access (§3.3).

---

## 7. Debug interface (deferred)

Displaying and single-stepping the machine (goal **G5**) needs visibility of CPU
*internal* state — registers and sequencing — which the functional interface does
not expose. That is provided by a separate **privileged debug interface**, reachable
by the **front panel only** ([D-13](decision-log.md); satisfies `R-DBG-5`). Its
signal list and protocol are **out of scope for this revision** and will be
specified later. Note that the front panel reaches *memory* through the functional
bus-arbitration handshake of §3.6/§4.6; the debug interface adds only the internal
visibility and step control.

**Wish-list (to specify when this interface is designed):** in addition to register
and sequencer visibility and single-step control, expose —

- **Run/halt state** — whether the CPU is stopped (via a `HALT` instruction) or
  running. This is distinct from the bus-grant stall already visible on `/BUSGRANT`
  (§3.6).
- **Instruction-fetch (machine-cycle) marker** — which bus cycle is an opcode fetch,
  so the panel (or a logic analyser) can track instruction boundaries.

Both were considered for the *functional* interface and deliberately placed here: no
functional peripheral consumes them, and their value is observation (goal **G5**), so
they belong on the privileged debug channel rather than the stable functional
contract (`R-IF-1`, `R-IF-6`).

---

## 8. Open questions

1. **Exact CLK-edge timing.** The nominal bus-cycle length, the `/WAIT` sample edge,
   and minimum hold/setup numbers are pinned once the **datapath bus count** is
   decided (pending — [hardware.md](hardware.md) §9).
2. **Minor conventions** flagged in §5 (edge/polarity/hold defaults).

*Decided:* the reset-vector address and physical memory map (reset entry `0x000000`;
boot ROM / RAM / I/O-page layout; firmware monitor/loader boots the kernel from a
block device) — [D-31](decision-log.md).

---

## Requirement coverage

| Requirement | Satisfied by |
|-------------|--------------|
| `R-IF-1` — one documented signal set; no peripheral touches internals | §1, §2, §6 |
| `R-IF-2` — address bus, data bus, transfer-qualifying control | §3.1–3.3, §4.1–4.3 |
| `R-IF-3` — reset, interrupt, and clock inputs | §3.4–3.5, §4.4–4.5 |
| `R-IF-4` — bus request/grant with tri-state | §3.6, §4.6 |
| `R-IF-6` — stable signal set + timing contract | the document; §5 |
| `R-IF-5` — *retired* (translation is internal) | §6 |
