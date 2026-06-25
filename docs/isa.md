# BLIP — Instruction Set Architecture

> The programmer's / compiler's contract. For *why these goals* see
> [docs/goals.md](goals.md); for *how the silicon realizes this* see
> [docs/hardware.md](hardware.md).
>
> **Status:** the rationale, register model, addressing modes, and encoding map below
> are **ratified**. The §8 opcode set is the flat **two-page** instruction inventory
> (D-41, after removing the indexed postbyte — superseding the single-page postbyte table
> of D-20/D-21). It is a **flat one-dimensional list** — no opcode grids — since the
> opcode→start-address map (D-40) decouples the opcode number from the microroutine.
> **Concrete opcode bytes are assigned in [isa/opcodes.toml](../isa/opcodes.toml)** — the
> single source of truth the §8.2 table is generated from (`tools/isa/gen_opcodes.py`;
> D-48). The assembly notation follows the house style of §4.1 (D-25).

---

## 1. Design rationale

### 1.1 The ISA serves the compiler
BLIP's instruction set is designed backwards from a single question: *what does
an optimizing C compiler want to emit?* (See goal **G2**.) That means the
machine must natively support the three things C leans on hardest:

1. **Stack-relative locals.** A C function's locals and spilled temporaries live
   in its stack frame. The CPU must address them directly as *(stack pointer +
   displacement)* with no per-access address arithmetic.
2. **Pointer arithmetic and dereference.** Pointers are 16-bit values that get
   added to, indexed, auto-incremented, and dereferenced constantly. The machine
   needs real 16-bit address registers, 16-bit add, and an
   address-of/effective-address operation.
3. **Reentrancy.** A real hardware stack with `CALL`/`RET`/interrupt framing so
   the same code is correct in interrupts, recursion, and across FUZIX tasks.

### 1.2 Why a 6809-flavoured, register-memory machine
The 6809 is the historical high-water mark for 8-bit C, *not* because of folklore
(OS-9/6809 was actually written in **assembly** — the C rewrite came later, on
other CPUs), but because it was deliberately designed for high-level languages,
reentrancy, and position-independent code (Ritter & Boney, *BYTE*, 1979). Its
two stack pointers, index registers with displacement/auto-inc/dec/accumulator
offsets, and a load-effective-address instruction are exactly the primitives a C
code generator wants. BLIP adopts that *shape* (not its encodings).

Contrast with the **Z80**, the other obvious 8-bit C target: the Z80 has no
SP-relative addressing, so compilers must burn an index register (`IX`) as a
frame pointer and pay a slow, prefixed `(IX+d)` for every local — convenient but
costly, and only one good 16-bit adder (`HL`). BLIP avoids both warts.

### 1.3 Toolchain: a new SDCC backend (STM8-derived)
Because BLIP is a clean-sheet ISA, **no existing toolchain works out of the box
for any choice** — a backend must be written regardless. The plan is a new
**SDCC** port:

- SDCC is a retargetable optimizing C compiler purpose-built for constrained
  8-bit machines; its register allocator and peephole optimizer are
  target-agnostic.
- The **STM8** backend is the closest architectural relative (stack-relative,
  16-bit index registers, index+displacement) and the recommended base to clone.
  SDCC's maintainer has stated on record that 6809-class stack-relative machines
  map well onto SDCC, citing STM8 as the proof.
- **GCC** (à la `gcc6809`) would give stronger codegen but is a multi-month
  first-time effort; **LLVM** is the worst fit for register-scarce 8-bit. Both
  are documented alternatives, not the plan.

A consequence for the ISA: every addressing mode and the calling convention
should map cleanly onto things an SDCC/STM8-style code generator already knows
how to choose. We co-design the ISA *and* the backend.

### 1.4 FUZIX shapes the system instructions
Running FUZIX (goal **G3**) means the ISA must include the machinery an OS needs:
maskable interrupts with a clean save/restore frame, a software interrupt /
trap for system calls, atomic-enough primitives for the scheduler, and a way to
reprogram the MMU page table on a context switch (see §6).

---

## 2. Programming model (register file v0)

All registers are programmer-visible unless noted. 8-bit unless a width is given.

**User-mode programmer registers:**

| Reg | Width | Role |
|-----|-------|------|
| `A` | 8 | Primary accumulator |
| `B` | 8 | Secondary accumulator |
| `D` | 16 | The pair `A:B` (A = high) used as a 16-bit accumulator |
| `X` | 16 | Index/pointer register |
| `Y` | 16 | Index/pointer register |
| `SP`| 16 | **Stack pointer** — C call frames; *banked by privilege* (see below) |
| `PC`| 16 | Program counter (logical address) |
| `CC`| 8 | Condition codes / processor state |

**Privilege mode & the banked stack pointer.** BLIP has two CPU modes,
**supervisor** and **user** (a real hardware kernel/user split — see
[§6](#6-system--privileged-behaviour-for-fuzix)). The name `SP` always refers to
the *active* stack pointer, but there are physically two:

| Reg | Width | Role |
|-----|-------|------|
| `USP` | 16 | User stack pointer — active in user mode |
| `SSP` | 16 | Supervisor stack pointer — active in supervisor mode |

A trap/interrupt switches to supervisor mode (so the kernel runs on `SSP`, which
user code cannot name or corrupt); `RTI` restores the saved mode. The kernel can
read/write `USP` explicitly to set up a user stack (68000-style). MMU control and
other privileged operations are legal only in supervisor mode.

**`CC` layout (decided):** 8 bits `M – H I N Z V C` (bit7→bit0): `M` supervisor/user
**mode** (1 = supervisor), bit6 reserved, `H` half-carry, `I` IRQ mask, and the ALU
flags `N`/`Z`/`V`/`C`. Holding the mode in `CC` lets it save/restore automatically
with `CC` on a trap/`RTI`; `M` is supervisor-write-only (user-mode `CC` writes can't
change it). See §8.4.

**Why this set.** Two 8-bit accumulators that pair into 16-bit `D` give cheap
`char` math *and* 16-bit `int`/pointer math. `X` and `Y` plus stack-relative
addressing `(SP+n)` cover C's pointer and locals needs — this is exactly the
**STM8** register shape (`X`, `Y`, `SP`), which SDCC already targets well, so the
backend has a proven template. The banked `SSP`/`USP` give the FUZIX kernel a
stack a misbehaving process literally cannot reach, turning the MMU's per-process
isolation into genuine kernel protection.

**Why no `U` and no `DP`.** We drop the 6809's second user stack `U` (a third
live pointer is a luxury; `X`/`Y`/`(SP+n)` suffice, per STM8) — the second stack
pointer instead earns its keep as the *supervisor* stack. We drop the direct-page
register `DP` because it solves a different problem than the MMU and pays off
little for C: direct/zero-page addressing buys code density for *hot globals*, but
C keeps its hot data (locals) on the stack, not in a fixed global page. (If we
later want the density win for I/O or kernel globals, a *fixed* zero page —
automatically per-process via the MMU — is the cheaper way to get it; see
[§4](#4-addressing-modes).)

### 2.1 Internal (non-programmer-visible) registers
Used by microcode only; documented here for completeness and because they drive
the blinkenlights: `MAR` (memory address register, 16-bit logical), `MDR` (memory
data register, 8-bit, to the external bus), `IR` (instruction register), `µPC`
(microprogram counter), and the scratch registers `SCR1`/`SCR2` (ALU operand
staging). See [docs/hardware.md](hardware.md) §2 and the control-word format in
[docs/microcode.md](microcode.md).

---

## 3. Data types and the C model

| C type | Size | Held in / notes |
|--------|------|-----------------|
| `char` | 8 | `A`/`B`, or memory |
| `int`, `short` | 16 | `D`/`X`/`Y`; **little-endian** in memory |
| `long` | 32 | register pair + memory, or memory |
| pointer | 16 | **near**: a flat logical address within the process's 64 KB view |
| `enum` | 16 | as `int` |

`float`/`double` and `long long` are library/soft-float; FUZIX itself leans on
`char`/`int`/`long` and 16-bit pointers, which is BLIP's sweet spot.

> **Decided — byte order: little-endian.** It matches every existing SDCC port,
> minimizing backend friction; we accept this over 6809-style big-endian.

---

## 4. Addressing modes

These are the C-critical modes; they mirror the 6809's model because it is the
one proven to make a code generator happy.

| Mode | Syntax | Use |
|------|--------|-----|
| Inherent | `NOP`, `RTS` | no operand |
| Immediate | `$nn` / `$nnnn` | constants (bare `$`-hex, no `#`) |
| Extended (absolute) | `($nnnn)` | absolute 16-bit address |
| Indexed: constant offset | `(X+n)` `(Y+n)` `(SP+n)` | **stack-relative locals**, struct fields |
| Indexed: zero offset | `(X)` | pointer dereference |
| Indexed: accumulator offset | `(X+A)` `(X+B)` `(X+D)` | `array[i]` in one instruction |
| Indexed: auto inc/dec | `(X+)` `(X++)` `(-X)` `(--X)` | `*p++`, stack-walks |
| PC-relative | `(PC+n)` | position-independent code/data |
| Relative (branch) | `label` | conditional/unconditional branches (8- and 16-bit) |

The two that earn their keep for C:

- **`(SP+n)`** — a local at frame offset *n* is one instruction, no frame-pointer
  setup tax. This is the single biggest win over a frame-pointer machine.
- **`LEA`** (load effective address, §7) — computes `r = address(mode)` so
  `p += n`, `&local`, and `&array[i]` are single instructions; it's how pointer
  arithmetic stays cheap. `LEA` names the *address*, so its operand is written
  **bare** (`LEA X,X+4`), not parenthesised.

Constant offsets come in **8-bit** and **16-bit** widths — the width is part of the
opcode (there is no postbyte; D-41) — so small frames and struct accesses stay compact
while large frames still work. **Indirect addressing is not provided:** a
pointer-to-pointer dereference or a jump through a memory slot is an explicit extra
`LD` (D-41 §3.1).

### 4.1 Assembly notation

BLIP assembly follows four conventions — the house style. (For how it compares to
other architectures see the non-normative [isa-comparison.md](isa-comparison.md).)

1. **The register is an operand, not part of the verb.** `LD A,$05`, `SUB A,(X+6)`,
   `NEG B`, `LEA X,X+4` — the mnemonic is the operation; the target register is its
   first operand.
2. **Immediates are bare `$`-hex.** A constant is written `$05` / `$1000`, with no
   `#` prefix.
3. **Parentheses mean memory.** `(addr)` is the *contents* at `addr`; a bare token
   is the value itself. The address inside may be a register (register-indirect,
   `(X)`), register + displacement (`(X+6)`, `(SP-8)`), register + accumulator
   (`(X+B)`), an auto-inc/dec form (`(X+)`, `(-X)`), or an absolute address (`($1234)`).
   An operand that *names an address* rather
   than dereferencing it stays bare — a `LEA` result and a jump/branch target (so
   `JMP X` jumps to the address in `X`, whereas `JMP (X)` jumps *through* it).
4. **Register↔register moves are `LD` / `XCHG`.** A copy is `LD dst,src`; a swap is
   `XCHG`. The assembler selects the opcode from the operand kinds (register,
   immediate, or memory), so the one `LD` verb covers them all.

---

## 5. Instruction encoding

### 5.1 Opcode space — two pages
There are **two 256-entry opcode pages**, page 0 (base) and page 1 (cold), reached
through the opcode→microinstruction map (D-40, D-41). A page-0 instruction needs no
prefix; a page-1 instruction is reached by the single prefix byte **`0x80`**, whose
microroutine re-enters decode on page 1. **There is no postbyte** (D-41): each
addressing mode is its own opcode. Every instruction is one opcode byte (preceded by
the `0x80` prefix on page 1) followed by 0–2 offset / immediate / address bytes;
decode is microcoded, so the opcode byte need not be bit-field-structured.

```
page 0:  [ opcode ] [ operand bytes 0..2 ]
page 1:  [ 0x80 ]   [ opcode ] [ operand bytes 0..2 ]
```

Page 0 holds the hot instructions (no decode tax); page 1 holds the cold tail at a
cost of **+1 byte and +1 cycle**. The hot/cold split criteria and the full per-page
inventory are §8 (full opcode set) and [d41-isa-refinement.md](d41-isa-refinement.md)
(the placement rationale).

### 5.2 Addressing is in the opcode (no postbyte)
With the indexed postbyte removed (D-41), an indexed instruction's index register and
sub-mode (zero / constant / accumulator offset, auto inc/dec) are encoded by the
**opcode itself**, not a trailing selector byte. Indirect addressing is dropped
(programmer-explicit, §4) and the 5-bit constant offset folds into the 8-bit form. The
trailing **selector bytes that remain are not the indexed postbyte**: the register-move
byte for `LD`/`XCHG reg,reg` and the `PSHS`/`PULS` mask (§8.4) are operand data and are
retained.

### 5.3 Branch offsets
Short (conditional) branches use an 8-bit signed offset (`Bcc`, page 0); long branches
use a 16-bit signed offset (`LBcc`, page 1 — a function large enough to need the longer
reach tolerates the prefix) so the compiler is never boxed in by ±128 bytes.

> **Resolved:** two opcode pages (page 0 + the `0x80`-prefixed page 1, D-41); no
> postbyte; operands are little-endian (§3).

---

## 6. System / privileged behaviour (for FUZIX)

BLIP has two CPU modes, **supervisor** and **user**, selected by the `M` bit in
`CC` (supervisor-write-only; see [§2](#2-programming-model-register-file-v0) and
§8.4). User code runs in user mode on `USP`; the kernel runs in supervisor mode on
`SSP`. This gives a real hardware kernel/user boundary on top of the per-process
address map.

Process isolation rests on two cheap mechanisms: each process's map only covers
its own pages (R-MEM-3), and the instructions that could change a map or otherwise
escape the sandbox are privileged (below) — together satisfying R-CPU-4. Per-page
access protection (read-only / no-access faulting) is a **non-goal** (decision log
D-18).

- **Mode entry/exit.** Every trap or interrupt switches to **supervisor** mode,
  switches the active stack to `SSP`, and selects the kernel MMU map set —
  atomically, in microcode. `RTI` restores the saved mode (hence the user stack
  bank and user map set). A user program cannot raise its own privilege except by
  trapping into the kernel.
- **Privileged operations** (supervisor-only; attempted in user mode → a
  **privilege-violation trap**): MMU control (`LDMMU`/`STMMU`), `RTI`, the
  interrupt-mask instructions (`SEI`/`CLI`), `HALT`/`SYNC`, and the `SSP`/`USP`
  banking moves. `SWI` and everything a process needs for ordinary computation stay
  unprivileged. So a process can't change its own mode or unmask interrupts,
  user-mode `CC` writes (`ANDCC`/`ORCC`/`CWAI`/`PULS CC`) cannot alter the `M` or
  `I` bits (see §8.7).
- **Interrupts.** One maskable `IRQ` (mask `CC.I`) plus a non-maskable `NMI`. `IRQ`
  is level-sensitive — devices wire-OR onto it and the handler polls each source —
  and `NMI` is edge-triggered (see [interface.md](interface.md) §3.5). Entry stacks
  a **minimal frame** (`PC` and `CC`) on `SSP` and then **sets `CC.I`**, so the
  handler runs with `IRQ` masked and is not re-entered until it clears the mask or
  returns. The handler saves any other registers it uses with `PSHS`/`PULS`
  (matching the caller-saves ABI). `RTI` restores `CC` (hence the prior mask and
  mode) and `PC`.
- **System call / trap.** A software interrupt (`SWI`, possibly `SWI2`/`SWI3`) is
  FUZIX's kernel-entry trap: it enters supervisor mode with a saved frame, likewise
  **setting `CC.I`** so the kernel begins with interrupts masked and re-enables them
  (`CLI`) when ready.
- **Exception vectors.** Every interrupt and trap reaches its handler through a
  **fixed table of pointer slots** — one each for `NMI`, `IRQ`, `SWI` (and
  `SWI2`/`SWI3` if kept), and the fault traps (illegal opcode, privilege violation) —
  each holding the handler's address. On acceptance the CPU loads `PC` from the slot,
  resolved in the kernel map that entry has already selected, so the kernel installs
  its own handlers simply by writing the table at init. **`RESET` is the exception:**
  RAM is not valid at reset, so it uses a fixed hardwired entry into boot ROM rather
  than a slot (R-CPU-7). The table sits at the top of the resident common region
  (logical `0xFFE0–0xFFFF`; D-30, D-31).
- **MMU control.** Address translation is internal to the CPU (see
  [docs/hardware.md](hardware.md) §3); its page table is an internal privileged
  register file, written only in supervisor mode by dedicated instructions
  (`LDMMU`/`STMMU`). It is reprogrammed on a context switch. A region of memory
  stays mapped at a fixed location in every map set, for the always-resident
  kernel code and the inter-map copy routines (R-MEM-4); the active map set follows
  the privilege mode (R-MEM-5).
- **Inter-map copy is software, not an instruction.** BLIP provides no block-move
  instruction. Bulk copies — including the kernel's cross-map `copyin`/`copyout`
  between a user map and the kernel (R-MEM-4) — are interruptible software loops over
  the auto-increment addressing modes (§4). A cross-map copy runs in the
  always-resident region and reaches the other map set by temporarily windowing the
  target page into a scratch slot with `LDMMU`, copying a bounded chunk, then
  advancing. Because it is a loop it never delays an interrupt by more than one
  iteration (R-CPU-3) and spends no opcode slot; a hardware block move would instead
  either stall interrupts for the whole transfer or require restartable microcode,
  so it is deliberately not provided.
- **Reset.** On reset the CPU enters supervisor mode with interrupts masked, `SSP` set
  below the I/O page (`0xE000`), and `PC` at the fixed, hardwired reset entry —
  **physical `0x000000`**, the start of boot ROM (R-CPU-7; not a vector-table slot —
  see *Exception vectors* above). **There is no "translation off" state — only the
  identity map.** Address translation is always active; at reset it is the transparent
  **identity map of the low 64 KB** (logical = physical for `0x0000–0xFFFF`), so the
  machine runs before software has configured any map (R-MEM-7). Boot ROM holds a
  **firmware monitor/loader** that initialises hardware, **loads the FUZIX kernel from
  a block device** into RAM, builds the kernel map (`LDMMU`), populates the exception
  vector table, and enters the kernel — which re-enables interrupts and replaces the
  identity map with per-process maps. The physical memory map (boot ROM / RAM / I/O
  page) is fixed in D-31.
- **Memory-mapped I/O.** Peripherals have no separate address space and no I/O
  instructions: they are decoded (outside the CPU) from a reserved region of the
  **physical** space — a single 8 KB **I/O page** at physical `0x00E000–0x00FFFF`,
  device registers at fixed offsets within it. A device access is an ordinary
  `LD`/`ST` that the MMU translates like any other access; software reaches a device
  by mapping the I/O page into a logical window, so the same map mechanism that
  isolates memory also gates device access — a user map that omits the I/O page
  cannot touch hardware (D-18). The I/O page sits inside the reset identity window
  (above), so the boot ROM reaches the console and storage with no MMU setup
  (R-MEM-7). The external decode is part of the functional interface (D-28).
- **Atomicity.** Disabling interrupts around critical sections, plus an atomic **`TAS`**
  (test-and-set) for kernel locks (R-CPU-6): `TAS` reads a lock byte — setting `N` from its
  high bit and `Z` if it was zero — then sets the byte, so a handler takes the lock iff it
  read it clear, uninterruptibly (§8.2, §8.5; D-48).

---

## 7. Calling convention (ABI)

> The single, stable convention that the C toolchain and hand-written assembly
> both follow (R-ABI-1) — fixed, not an implementation detail free to drift.

**Reentrancy & locals.** Parameters, locals, and return linkage live on a
per-call stack; locals are reached by `(SP+n)` displacement, with no frame-pointer
register (R-ISA-1, R-ISA-2, R-ISA-8).

**Argument passing.** **All** arguments are pushed on the stack, **right-to-left**,
under one rule that does not vary with the function's arity, its argument types, or
whether it is variadic (R-ABI-1, R-ABI-2). Right-to-left places the first declared
argument at the lowest argument offset, so a callee — variadic or not — reaches
argument *n* at a fixed `(SP+n)` displacement, the same frame addressing it uses for
locals (R-ISA-2). `struct`/`union` arguments are passed the same way, by value on
the stack. No argument is passed in a register, so a callee begins with the whole
register file free for evaluation, subject to the save discipline below.

**Return values.**
- 8-bit → `B`; 16-bit → `X` (an address-capable register, so a returned pointer is
  usable immediately — R-ABI-3);
- 32-bit (`long`/`float`) → the `D:Y` working pair: low word in `D`, high word in
  `Y` — returned in the same register pair where 32-bit values are computed (§8.5),
  so no store through a result pointer is needed (R-ABI-3);
- `struct`/`union` are **not returned by value**: an aggregate result is delivered
  through a pointer the caller passes explicitly as an ordinary argument (so it
  follows the stack argument rule above), not as a register or stack return value.

**Register save discipline.**
- **Callee-saved (preserved across a call): `Y`.** A function that uses `Y` saves
  and restores it. This gives the compiler one 16-bit register to hold a value —
  typically a loop-carried pointer — live across a call without spilling (R-ABI-4).
- **Caller-saved (clobberable): `A`, `B`/`D`, `X`, `CC`.** The caller preserves any
  it needs across a call.

**Stack cleanup.** The **caller** removes arguments after the call (keeps variadic
calls simple and the convention uniform).

**Why these registers.** A stacked argument is reached by the same 16-bit `(SP+n)`
frame displacement as a local (R-ISA-2), so one uniform stack rule is a
single-instruction access for the small and leaf calls that matter (R-ABI-2),
without the prologue spill a register-passed argument would need before it is
addressable. `D = A:B`, so an 8-bit return in `B` (the low half) widens to 16-bit by
just setting `A` — cheap C integer promotion (R-ISA-7). 16-bit return values are
usually pointers, so returning them in `X` lets them be dereferenced or indexed with
no move (R-ABI-3, R-ISA-5). Because no argument occupies a register, the file is free
to give returns their registers (R-ABI-3) and still keep `Y` preserved across calls
(R-ABI-4) without contention.

---

## 8. Opcode table

> The full instruction set, on **two 256-opcode pages** — page 0 (hot, no prefix) and
> page 1 (cold, reached by the `0x80` prefix) — after the indexed postbyte was removed
> and addressing was flattened into the opcode (D-41, superseding the single-page
> postbyte model of D-20/D-21). §8.2 is the **complete instruction inventory** per page,
> verified for budget, hot/cold placement, and requirement coverage (D-41 build pass);
> the placement rationale is [d41-isa-refinement.md](d41-isa-refinement.md). The set is a
> **flat one-dimensional list** (no opcode grids — see §8.1); concrete byte values are a
> mechanical sequential assignment. Flag effects are per §8.5; cycle counts are deferred
> until the datapath bus count ([hardware.md](hardware.md) §9) is settled.

### 8.1 Encoding model

Every instruction is **one opcode byte** plus 0–2 trailing offset/immediate/address
bytes, preceded by the `0x80` prefix byte on page 1 (§5.1). There is no postbyte;
addressing modes are distinct opcodes (D-41). Maximum length is **3 on page 0**
(opcode + 2) and **4 on page 1** (prefix + opcode + 2). Decode is microcoded, so the
opcode need not be bit-structured.

The opcode set is a **flat one-dimensional list** (§8.2) — there are **no opcode grids**.
The single-page table used nibble-aligned grids so direct microaddress formation (D-24) could
let one decoded band share microcode; the opcode→start-address map (D-40) removed that
coupling — shared microcode now comes from several map entries pointing at one routine,
independent of the opcode number — so byte values are assigned sequentially down §8.2 with no
geometry to satisfy. The conventions:

- **Lengths.** inherent = 1; `imm8` / mask / `rel8` / entry-selector = 2; `imm16` /
  extended / `rel16` = 3; an 8-bit indexed offset adds 1 byte, a 16-bit indexed offset
  adds 2. Add 1 byte to any **page-1** instruction for the `0x80` prefix.
- **Stores and `JSR`** exist only in the memory-operand forms; there is no
  store-immediate or `JSR`-immediate (meaningless) — intentional, not a gap.

### 8.2 Instruction inventory (the two pages)

The complete instruction set, grouped by family. **Page 0 = 232 opcodes** (23 free of
the 255 usable after `0x80` is reserved as the page-1 prefix); **page 1 = 230 opcodes**
(26 free of 256). Each entry is one opcode; operand bytes (offset / immediate / mask)
follow per §8.1. This is a **flat list** (no opcode grids, §8.1). **Concrete byte values —
the two-hex-digit prefix on each entry below — are assigned in
[isa/opcodes.toml](../isa/opcodes.toml), the single source of truth this table is generated
from** (`tools/isa/gen_opcodes.py`; D-48); on page 0, `0x80` is reserved for the page-1
prefix and the unused high values are the free slots. The set is verified for budget,
hot/cold placement, and requirement coverage (D-41 build pass; `JSR X` promoted to page 0 in
D-48). Placement rationale: [d41-isa-refinement.md](d41-isa-refinement.md).

<!-- BEGIN opcode-inventory (generated from isa/opcodes.toml by tools/isa/gen_opcodes.py — do not edit by hand) -->

#### Page 0 — hot (no prefix), 232 opcodes

**Byte load/store (A, B) — 38.**
`00 LD A,$nn`, `01 LD A,(SP+n8)`, `02 LD A,(SP)`, `03 LD A,(X)`, `04 LD A,(X+n8)`, `05 LD A,(X+)`, `06 LD A,(X+D)`, `07 LD A,($nnnn)`, `08 LD A,(Y)`, `09 LD A,(Y+)`, `0A LD A,(Y+n8)`, `0B LD B,$nn`, `0C LD B,(SP+n8)`, `0D LD B,(SP)`, `0E LD B,(X)`, `0F LD B,(X+n8)`, `10 LD B,(X+)`, `11 LD B,(X+D)`, `12 LD B,($nnnn)`, `13 LD B,(Y)`, `14 LD B,(Y+)`, `15 LD B,(Y+n8)`, `16 ST A,(SP+n8)`, `17 ST A,(X)`, `18 ST A,(X+n8)`, `19 ST A,(X+)`, `1A ST A,($nnnn)`, `1B ST A,(Y)`, `1C ST A,(Y+n8)`, `1D ST A,(Y+)`, `1E ST B,(SP+n8)`, `1F ST B,(X)`, `20 ST B,(X+n8)`, `21 ST B,(X+)`, `22 ST B,($nnnn)`, `23 ST B,(Y)`, `24 ST B,(Y+n8)`, `25 ST B,(Y+)`

**16-bit load/store (D, X, Y, SP) — 28.**
`26 LD D,$nnnn`, `27 LD X,$nnnn`, `28 LD Y,$nnnn`, `29 LD SP,$nnnn`, `2A LD D,($nnnn)`, `2B LD X,($nnnn)`, `2C LD Y,($nnnn)`, `2D ST D,($nnnn)`, `2E ST X,($nnnn)`, `2F ST Y,($nnnn)`, `30 LD D,(X)`, `31 ST D,(X)`, `32 LD D,(X+n8)`, `33 ST D,(X+n8)`, `34 LD D,(X++)`, `35 ST D,(X++)`, `36 LD D,(SP+n8)`, `37 LD X,(SP+n8)`, `38 LD Y,(SP+n8)`, `39 ST D,(SP+n8)`, `3A ST X,(SP+n8)`, `3B ST Y,(SP+n8)`, `3C LD D,(X+D)`, `3D ST D,(X+D)`, `3E LD D,(Y)`, `3F ST D,(Y)`, `40 LD D,(Y+n8)`, `41 ST D,(Y+n8)`

**Byte ALU (ADD/SUB/CMP/AND/OR on A, B) — 67.**
`42 ADD A,$nn`, `43 ADD A,(X)`, `44 ADD A,(X+n8)`, `45 ADD A,(X+D)`, `46 ADD A,(SP+n8)`, `47 ADD A,($nnnn)`, `48 ADD A,(X+)`, `49 ADD A,(Y)`, `4A ADD B,$nn`, `4B ADD B,(X)`, `4C ADD B,(X+n8)`, `4D ADD B,(X+D)`, `4E ADD B,(SP+n8)`, `4F ADD B,($nnnn)`, `50 ADD B,(X+)`, `51 ADD B,(Y)`, `52 SUB A,$nn`, `53 SUB A,(X)`, `54 SUB A,(X+n8)`, `55 SUB A,(X+D)`, `56 SUB A,(SP+n8)`, `57 SUB A,($nnnn)`, `58 SUB A,(X+)`, `59 SUB A,(Y)`, `5A SUB B,$nn`, `5B SUB B,(X)`, `5C SUB B,(X+n8)`, `5D SUB B,(X+D)`, `5E SUB B,(SP+n8)`, `5F SUB B,($nnnn)`, `60 SUB B,(X+)`, `61 SUB B,(Y)`, `62 CMP A,$nn`, `63 CMP A,(X)`, `64 CMP A,(X+n8)`, `65 CMP A,(SP+n8)`, `66 CMP A,($nnnn)`, `67 CMP A,(Y)`, `68 CMP B,$nn`, `69 CMP B,(X)`, `6A CMP B,(X+n8)`, `6B CMP B,($nnnn)`, `6C CMP B,(Y)`, `6D AND A,$nn`, `6E AND A,(X)`, `6F AND A,(X+n8)`, `70 AND A,($nnnn)`, `71 AND A,(X+)`, `72 AND A,(Y)`, `73 AND B,$nn`, `74 AND B,(X)`, `75 AND B,(X+n8)`, `76 AND B,($nnnn)`, `77 AND B,(X+)`, `78 AND B,(Y)`, `79 OR A,$nn`, `7A OR A,(X)`, `7B OR A,(X+n8)`, `7C OR A,($nnnn)`, `7D OR A,(X+)`, `7E OR A,(Y)`, `7F OR B,$nn`, `81 OR B,(X)`, `82 OR B,(X+n8)`, `83 OR B,($nnnn)`, `84 OR B,(X+)`, `85 OR B,(Y)`

**16-bit ALU, wide compare & D shifts — 18.**
`86 ADD D,$nnnn`, `87 ADD D,($nnnn)`, `88 ADD D,(SP+n8)`, `89 ADD D,(X)`, `8A ADD D,(X+n8)`, `8B ADD D,(X+D)`, `8C SUB D,$nnnn`, `8D SUB D,($nnnn)`, `8E SUB D,(SP+n8)`, `8F CMP D,$nnnn`, `90 CMP D,($nnnn)`, `91 CMP D,(SP+n8)`, `92 CMP X,$nnnn`, `93 CMP Y,$nnnn`, `94 CMP SP,$nnnn`, `95 ASL D,$n`, `96 LSR D,$n`, `97 ASR D,$n`

**RMW & register-direct unary — 26.**
`98 INC A`, `99 DEC A`, `9A CLR A`, `9B TST A`, `9C LSR A`, `9D ASR A`, `9E ASL A`, `9F INC B`, `A0 DEC B`, `A1 CLR B`, `A2 TST B`, `A3 LSR B`, `A4 ASR B`, `A5 ASL B`, `A6 INC (X)`, `A7 INC (X+n8)`, `A8 INC (SP+n8)`, `A9 DEC (X)`, `AA DEC (X+n8)`, `AB DEC (SP+n8)`, `AC CLR (X)`, `AD CLR (X+n8)`, `AE TST (X)`, `AF TST (X+n8)`, `B0 INC ($nnnn)`, `B1 DEC ($nnnn)`

**Control flow — 30.**
`B2 BRA rel8`, `B3 BRN rel8`, `B4 BHI rel8`, `B5 BLS rel8`, `B6 BCC rel8`, `B7 BCS rel8`, `B8 BNE rel8`, `B9 BEQ rel8`, `BA BVC rel8`, `BB BVS rel8`, `BC BPL rel8`, `BD BMI rel8`, `BE BGE rel8`, `BF BLT rel8`, `C0 BGT rel8`, `C1 BLE rel8`, `C2 BSR rel8`, `C3 RTS`, `C4 JMP $nnnn`, `C5 JMP X`, `C6 JMP Y`, `C7 JMP (X)`, `C8 JMP (X+n8)`, `C9 JMP (X+D)`, `CA JSR $nnnn`, `CB JSR (X)`, `CC JSR Y`, `CD JSR X`, `CE JSR (X+n8)`, `CF JSR (X+D)`

**System / inherent / LEA / moves — 25.**
`D0 NOP`, `D1 SEX`, `D2 MUL`, `D3 ABX`, `D4 PSHS mask8`, `D5 PULS mask8`, `D6 ANDCC $nn`, `D7 ORCC $nn`, `D8 LD reg,reg`, `D9 XCHG reg,reg`, `DA TAS (X)`, `DB TAS (X+n8)`, `DC LEA X,X+n8`, `DD LEA X,X+A`, `DE LEA X,X+B`, `DF LEA X,X+D`, `E0 LEA X,X+`, `E1 LEA X,X++`, `E2 LEA X,-X`, `E3 LEA X,Y+n8`, `E4 LEA X,SP+n8`, `E5 LEA Y,Y+n8`, `E6 LEA Y,SP+n8`, `E7 LEA SP,SP+n8`, `E8 LEA SP,X+n8`

#### Page 1 — cold (`0x80` prefix), 230 opcodes

**System / privileged / cold TAS & LEA — 31.**
`00 DAA`, `01 SYNC`, `02 RTI`, `03 SWI`, `04 SWI2`, `05 SWI3`, `06 CWAI $nn`, `07 SEI`, `08 CLI`, `09 HALT`, `0A LDMMU $nn`, `0B STMMU $nn`, `0C LD USP,X`, `0D LD USP,Y`, `0E LD USP,D`, `0F LD X,USP`, `10 LD Y,USP`, `11 LD D,USP`, `12 XCHG X,USP`, `13 XCHG Y,USP`, `14 XCHG D,USP`, `15 TAS (Y)`, `16 TAS (Y+n8)`, `17 TAS (SP+n8)`, `18 TAS ($nnnn)`, `19 LEA X,X+n16`, `1A LEA Y,Y+n16`, `1B LEA SP,SP+n16`, `1C LEA X,PC+n8`, `1D LEA Y,PC+n8`, `1E LEA SP,Y+n8`

**Control flow — long branches & cold JMP/JSR — 39.**
`1F LBRA rel16`, `20 LBRN rel16`, `21 LBHI rel16`, `22 LBLS rel16`, `23 LBCC rel16`, `24 LBCS rel16`, `25 LBNE rel16`, `26 LBEQ rel16`, `27 LBVC rel16`, `28 LBVS rel16`, `29 LBPL rel16`, `2A LBMI rel16`, `2B LBGE rel16`, `2C LBLT rel16`, `2D LBGT rel16`, `2E LBLE rel16`, `2F LBSR rel16`, `30 JMP (X+n16)`, `31 JMP (X+A)`, `32 JMP (X+B)`, `33 JMP (Y)`, `34 JMP (Y+n8)`, `35 JMP (Y+n16)`, `36 JMP (Y+A)`, `37 JMP (Y+B)`, `38 JMP (Y+D)`, `39 JMP (PC+n8)`, `3A JMP (PC+n16)`, `3B JSR (X+n16)`, `3C JSR (X+A)`, `3D JSR (X+B)`, `3E JSR (Y)`, `3F JSR (Y+n8)`, `40 JSR (Y+n16)`, `41 JSR (Y+A)`, `42 JSR (Y+B)`, `43 JSR (Y+D)`, `44 JSR (PC+n8)`, `45 JSR (PC+n16)`

**Byte load/store (cold modes) — 36.**
`46 ST A,(SP)`, `47 ST B,(SP)`, `48 LD A,(X++)`, `49 LD B,(X++)`, `4A LD A,(--X)`, `4B LD B,(--X)`, `4C LD A,(-X)`, `4D LD B,(-X)`, `4E ST A,(X++)`, `4F ST B,(X++)`, `50 ST A,(--X)`, `51 ST B,(--X)`, `52 ST A,(-X)`, `53 ST B,(-X)`, `54 LD A,(X+A)`, `55 LD A,(X+B)`, `56 LD B,(X+A)`, `57 LD B,(X+B)`, `58 ST A,(X+A)`, `59 ST A,(X+B)`, `5A ST A,(X+D)`, `5B ST B,(X+A)`, `5C ST B,(X+B)`, `5D ST B,(X+D)`, `5E LD A,(X+n16)`, `5F LD B,(X+n16)`, `60 ST A,(X+n16)`, `61 ST B,(X+n16)`, `62 LD A,(SP+n16)`, `63 LD B,(SP+n16)`, `64 ST A,(SP+n16)`, `65 ST B,(SP+n16)`, `66 LD A,(-Y)`, `67 LD B,(-Y)`, `68 ST A,(-Y)`, `69 ST B,(-Y)`

**16-bit load/store (cold modes) — 42.**
`6A LD X,(Y)`, `6B ST X,(Y)`, `6C LD Y,(X)`, `6D ST Y,(X)`, `6E LD D,(SP)`, `6F LD X,(SP)`, `70 LD Y,(SP)`, `71 ST D,(SP)`, `72 ST X,(SP)`, `73 ST Y,(SP)`, `74 LD X,(X++)`, `75 LD Y,(X++)`, `76 ST Y,(X++)`, `77 LD D,(Y++)`, `78 ST D,(Y++)`, `79 LD X,(Y++)`, `7A ST X,(Y++)`, `7B LD D,(--X)`, `7C ST D,(--X)`, `7D ST Y,(--X)`, `7E LD D,(--Y)`, `7F ST D,(--Y)`, `80 ST X,(--Y)`, `81 LD Y,(X+n8)`, `82 ST Y,(X+n8)`, `83 LD X,(Y+n8)`, `84 ST X,(Y+n8)`, `85 LD D,(X+n16)`, `86 LD X,(X+n16)`, `87 ST D,(X+n16)`, `88 ST X,(X+n16)`, `89 LD D,(SP+n16)`, `8A LD X,(SP+n16)`, `8B LD Y,(SP+n16)`, `8C ST D,(SP+n16)`, `8D ST X,(SP+n16)`, `8E ST Y,(SP+n16)`, `8F LD Y,(X+D)`, `90 ST Y,(X+D)`, `91 LD D,(Y+D)`, `92 LD SP,($nnnn)`, `93 ST SP,($nnnn)`

**Byte ALU (cold modes + ADC/SBC/EOR/BIT) — 46.**
`94 ADD A,(SP)`, `95 ADD B,(SP)`, `96 SUB A,(SP)`, `97 SUB B,(SP)`, `98 CMP A,(SP)`, `99 CMP B,(SP)`, `9A AND A,(SP)`, `9B AND B,(SP)`, `9C OR A,(SP)`, `9D OR B,(SP)`, `9E ADC A,$nn`, `9F ADC B,$nn`, `A0 ADC A,($nnnn)`, `A1 ADC B,($nnnn)`, `A2 ADC A,(X)`, `A3 ADC B,(X)`, `A4 ADC A,(X+n8)`, `A5 ADC B,(X+n8)`, `A6 ADC A,(SP+n8)`, `A7 ADC B,(SP+n8)`, `A8 SBC A,$nn`, `A9 SBC B,$nn`, `AA SBC A,($nnnn)`, `AB SBC B,($nnnn)`, `AC SBC A,(X)`, `AD SBC B,(X)`, `AE SBC A,(X+n8)`, `AF SBC B,(X+n8)`, `B0 SBC A,(SP+n8)`, `B1 SBC B,(SP+n8)`, `B2 EOR A,$nn`, `B3 EOR B,$nn`, `B4 EOR A,($nnnn)`, `B5 EOR B,($nnnn)`, `B6 EOR A,(X)`, `B7 EOR B,(X)`, `B8 EOR A,(X+n8)`, `B9 EOR B,(X+n8)`, `BA BIT A,$nn`, `BB BIT B,$nn`, `BC BIT A,($nnnn)`, `BD BIT B,($nnnn)`, `BE BIT A,(X)`, `BF BIT B,(X)`, `C0 BIT A,(X+n8)`, `C1 BIT B,(X+n8)`

**16-bit ALU & wide compare (cold) — 22.**
`C2 ADC D,$nnnn`, `C3 ADC D,($nnnn)`, `C4 ADC D,(SP+n8)`, `C5 ADC D,(X)`, `C6 ADC D,(X+n8)`, `C7 SBC D,$nnnn`, `C8 SBC D,($nnnn)`, `C9 SBC D,(SP+n8)`, `CA SBC D,(X)`, `CB SBC D,(X+n8)`, `CC ADD D,(X++)`, `CD ADD D,(--X)`, `CE SUB D,(X)`, `CF SUB D,(X+n8)`, `D0 SUB D,(X+D)`, `D1 CMP D,(X)`, `D2 CMP D,(X+n8)`, `D3 CMP X,($nnnn)`, `D4 CMP Y,($nnnn)`, `D5 CMP SP,($nnnn)`, `D6 CMP X,(SP+n8)`, `D7 CMP X,(X)`

**RMW & register-direct unary (cold ops) — 14.**
`D8 NEG A`, `D9 COM A`, `DA ROL A`, `DB ROR A`, `DC NEG B`, `DD COM B`, `DE ROL B`, `DF ROR B`, `E0 INC (X+)`, `E1 DEC (X+)`, `E2 INC (Y)`, `E3 DEC (Y)`, `E4 CLR (Y)`, `E5 TST (Y)`

<!-- END opcode-inventory -->

### 8.3 Indexed addressing (encoded in the opcode)

There is no indexed postbyte (D-41): the index register and sub-mode are part of the
**opcode**, so a given (operation, register, mode) is one opcode (§8.2). The sub-modes:

| Mode | Syntax | Extra bytes |
|------|--------|-------------|
| zero offset | `(R)` | 0 |
| 8-bit signed offset | `(R+n8)` | 1 |
| 16-bit signed offset | `(R+n16)` | 2 (LE) |
| auto-inc by 1 / by 2 (post) | `(R+)` / `(R++)` | 0 |
| auto-dec by 1 / by 2 (pre) | `(-R)` / `(--R)` | 0 |
| accumulator offset | `(R+A)` `(R+B)` `(R+D)` | 0 |
| PC-relative (load / `JMP` only) | `(PC+n8)` `(PC+n16)` | 1 / 2 |

The index register `R` is `X`, `Y`, or `SP` as the opcode names it (and `PC` for the
PC-relative forms); which (register × mode × operation) combinations exist, and on which
page, is the §8.2 inventory. **Indirect addressing is not provided** (D-41 §3.1) — `((…))`
becomes an explicit second `LD` — and the **5-bit constant offset** folds into the 8-bit
form (no postbyte to pack it).

The privileged USP-banking moves and the plain register moves use no indexed encoding —
they carry the register-move selector byte (§8.4), which is operand data, not a postbyte,
and is retained.

### 8.4 Register & flag encoding

**`CC` (8 bits, MSB→LSB):** `M – H I N Z V C` — bit7 `M` supervisor/user mode
(1 = supervisor), bit6 reserved, bit5 `H` half-carry, bit4 `I` IRQ mask, bit3 `N`,
bit2 `Z`, bit1 `V`, bit0 `C`. `M` lives in `CC` so it saves/restores automatically
with `CC` on trap/`RTI`, and it is **supervisor-write-only** (user-mode `CC` writes
can't change it — §8.7).

**Register-move (`LD`/`XCHG`) selector byte:** `src(7:4) | dst(3:0)`, each a 4-bit register
code; source and destination must be the same width. (A copy is written
destination-first, `LD dst,src`, but the selector keeps `src` in the high nibble;
`XCHG` is symmetric.) This byte is operand data, not the indexed postbyte (which is gone,
D-41); it is retained.
- 16-bit: `D`=0, `X`=1, `Y`=2, `SP`=3, `PC`=4. (e.g. `LD X,D` = `0x01`.)
- 8-bit: `A`=8, `B`=9, `CC`=`0xA`. (e.g. `XCHG A,B` = `0x89`.)
- `USP`=`0xF` — referencing it is the **privileged** USP-banking form (a page-1 opcode,
  §8.2), which traps in user mode. Codes `5`,`6`,`7`,`B`–`E` reserved.
- `PC` (code 4) is valid only as a move **source** — `LD X,PC` / `LD D,PC` reads the program
  counter; `PC` as a move **destination**, and `XCHG` with `PC`, are not provided, so a
  computed transfer is always a `JMP`/`JSR`, never a second `LD` encoding (D-48).

**`PSHS`/`PULS` mask byte** (one bit per register; push high-address-first, pull
reverse, so the same mask round-trips): bit0 `CC`, bit1 `A`, bit2 `B`, bit3
*reserved*, bit4 `X`, bit5 `Y`, bit6 `SP` (the other/banked `SP` image), bit7 `PC`.
`D` is pushed/pulled as `A`+`B` (bits 1+2). The implicit stack is the active one
(`USP` in user mode, `SSP` in supervisor), so user code can't reach the kernel stack.

### 8.5 Flag effects by operation class

Notation: `*` set from result, `0`/`1` forced, `-` unaffected, `?` undefined.

| Class | N | Z | V | C | H |
|-------|---|---|---|---|---|
| `LD` / `ST` (memory/immediate) | * | * | 0 | - | - |
| `LD` / `XCHG` (register↔register) | - | - | - | - | - |
| `CLR` | 0 | 1 | 0 | 0 | - |
| `ADD`/`ADC` (8-bit) | * | * | * | * | * |
| `ADD D`/`ADC D` (16-bit) | * | * | * | * | - |
| `SUB`/`SBC`/`CMP` (8-bit) | * | * | * | * | ? |
| `SUB D`/`SBC D`/`CMP D`/`CMP X`/`CMP Y`/`CMP SP` | * | * | * | * | - |
| `AND`/`OR`/`EOR`/`BIT`/`TST` | * | * | 0 | - | - |
| `INC`/`DEC` | * | * | * | - | - |
| `NEG` | * | * | * | * | ? |
| `COM` | * | * | 0 | 1 | - |
| `ASL`/`ROL`/`LSR`/`ROR`/`ASR`, `ASL D`/`LSR D`/`ASR D` | * | * | * | * | ? |
| `TAS` | * | * | 0 | - | - |
| `LEA X`/`LEA Y` | - | * | - | - | - |
| `LEA SP`, `JMP`/`JSR`/`BSR`/`LBSR`/`RTS`, `Bcc`/`LBcc`, `ABX`, `NOP`, `SYNC`, `HALT` | - | - | - | - | - |
| `PSHS`/`PULS` (registers other than `CC`) | - | - | - | - | - |
| `SEI`/`CLI` | - | - | - | - | - |
| `LDMMU`/`STMMU` | - | - | - | - | - |
| `SEX` | * | * | 0 | - | - |
| `MUL` | - | * | - | * | - |
| `DAA` | * | * | ? | * | - |
| `ANDCC`/`ORCC`/`CWAI` | per mask byte | | | | |
| `RTI`, `PULS CC` | all `CC` restored from stack | | | | |
| `SWI`/`SWI2`/`SWI3` | set `I`; no N/Z/V/C/H | | | | |

### 8.6 Free slots & growth

The two pages each leave room for growth: **page 0 has 23 free slots** (of the 255
usable, `0x80` being spent as the page-1 prefix) and **page 1 has 26 free** (of 256). The
single-page "pack the prefix-page ops into holes" exercise (the former D-20/D-21
constraint) is retired — the cold tail (long branches, the cold ALU/wide-compare modes,
the privileged ops, …) lives on page 1 rather than competing for page-0 holes (§8.2).
Because the instruction set is microcode-defined and reflashable (R-CTRL-1), the page
assignment can be re-carved without rewiring; the free slots are residual headroom, not a
forced reserve ([d41-isa-refinement.md](d41-isa-refinement.md) §4.4).

### 8.7 Privilege & the user-mode `CC` mask

Privileged instructions (trap in user mode): `SYNC`, `RTI`, `SEI`/`CLI`, `HALT`, the
USP-banking `LD`/`XCHG` (the `USP`-referencing register moves, §8.4), and `LDMMU`/`STMMU`
— all page-1 opcodes (§8.2). `SWI`/`SWI2`/`SWI3` are **unprivileged** — the syscall
gateway. The plain register moves `LD`/`XCHG` stay unprivileged; only the USP-banking
variants are privileged.

Because `ANDCC`/`ORCC`/`CWAI` and `PULS CC` write `CC` directly, they would
otherwise let user code change its own **mode** (`M`) or clear the **`I`** interrupt
mask. So **in user mode those instructions cannot alter the `M` or `I` bits** —
attempts are ignored (only `H N Z V C` are writable). `M` and `I` change only in
supervisor mode (and via `RTI`/trap entry, which is itself privileged). This is what
makes the mode bit and "interrupt-mask changes are privileged" (R-CPU-4, R-CPU-6)
actually hold.

### 8.8 Multi-word arithmetic and wide shifts

`ADC D`/`SBC D` are 16-bit add/subtract **with carry-in** — the chaining partners of
`ADD D`/`SUB D` (which deposit `C`, §8.5). A 32-bit or wider integer is then added or
subtracted 16 bits at a time — `ADD D` the low halves, `ADC D` the high halves —
instead of dropping to the 8-bit `ADC`/`SBC` and threading the carry through four
steps. This keeps multi-word integer add/subtract on the non-emulated 16-bit path
(R-ISA-6) and makes the compiler's `long` helpers compact (R-BUILD-1). Their flags
follow `ADD D`/`SUB D` (§8.5).

`ASL D,$n` / `LSR D,$n` / `ASR D,$n` shift the 16-bit accumulator `D` by an immediate
count `n` in one instruction: left (logical = arithmetic), logical right (unsigned
`>>`), and arithmetic right (signed `>>`). They close two gaps — the base set has
**no** 16-bit shift on `D` at all (it otherwise costs an `ASL B`+`ROL A`-style pair
*per bit*), and a constant multi-bit shift (scaling by a power of two, field
extraction — the dominant C case) collapses to a single instruction (R-ISA-6,
R-BUILD-1). The count is an immediate byte; the microcode shifts `n` positions for
`n` in `0..16`. Larger counts are **don't-care, not clamped** — the loop counter
takes `n` modulo its width, because C leaves shifts ≥ the operand width undefined, so
conforming code never emits a larger count.

A **runtime-variable** shift count is deliberately not encoded: the value occupies
`D = A:B`, so a register-held count would have to live in `X`/`Y` — the pointer and
return registers — which is too costly to standardise. The constant-count form
captures the dominant case; a register-count form remains a future option if
profiling shows runtime-variable shifts are hot.

---

## 9. Open questions for this document

None outstanding at this tier — the instruction set is **ratified** (D-48): the §8.2
inventory, the concrete opcode bytes ([isa/opcodes.toml](../isa/opcodes.toml)), the atomic
`TAS`, and the assembly notation are all settled.

*Decided:* registers `A B D X Y SP` (no `U`/`DP`); little-endian; privilege with
banked `SSP`/`USP` and the mode bit in `CC` (D-22); internal MMU
(physical external bus, 16 MB / 8 KB pages, identity-mapped at reset, programmed by
privileged `LDMMU`/`STMMU`); memory-mapped I/O in a single physical I/O page reached
through the MMU (D-28); reset vector and physical memory map (reset entry `0x000000`,
common at `0xE000`, vector table at `0xFFE0`; firmware monitor/loader boots the kernel
from a block device — D-31); calling convention (§7); the **two-page** flat encoding
(no postbyte) and the instruction inventory (§8; D-41), with the concrete opcode bytes
assigned in [isa/opcodes.toml](../isa/opcodes.toml) and `JSR X` promoted to page 0 (D-48);
the atomic **`TAS`** test-and-set for kernel locks (§6; D-48); and the assembly
notation house style (§4.1 — verb/register split, bare `$`-hex immediates,
parenthesised memory, `LD`/`XCHG` register moves; D-25).
