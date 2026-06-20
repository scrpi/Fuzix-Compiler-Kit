# BLIP — Instruction Set Architecture

> The programmer's / compiler's contract. For *why these goals* see
> [docs/goals.md](goals.md); for *how the silicon realizes this* see
> [docs/hardware.md](hardware.md).
>
> **Status:** the rationale, register model, addressing modes, and encoding map
> below are a **v0 proposal** under active design review. The §8 opcode set is the flat
> **two-page** instruction inventory (D-41, after removing the indexed postbyte —
> superseding the single-page postbyte table of D-20/D-21). It is a **flat one-dimensional
> list** — no opcode grids — since the opcode→start-address map (D-40) decouples the opcode
> number from the microroutine, so concrete byte values are a mechanical sequential
> assignment. The assembly notation follows the house style of §4.1 (D-25).

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
- **Atomicity.** At minimum, disabling interrupts around critical sections; a
  test-and-set-like primitive is a possible convenience (TBD).

---

## 7. Calling convention (ABI)

> The single, stable convention that the C toolchain and hand-written assembly
> both follow (R-ABI-1) — fixed, not an implementation detail free to drift.

**Reentrancy & locals.** Parameters, locals, and return linkage live on a
per-call stack; locals are reached by `(SP+n)` displacement, with no frame-pointer
register (R-ISA-1, R-ISA-2, R-ISA-8).

**Argument passing.** Leading scalar arguments go in registers; the rest are
pushed on the stack **right-to-left** (R-ABI-2; right-to-left so a variadic callee
finds its fixed arguments at known low offsets):
- first 8-bit argument → `B`;
- first 16-bit argument → `X`;
- a second scalar fills the still-free class (`A` for a byte, or `B` if the first
  was 16-bit). There is **no** second 16-bit register slot — `Y` is reserved (see
  save discipline) — so a second 16-bit argument goes on the stack;
- `struct`/`union` arguments, and **all** arguments of a variadic function, go on
  the stack.

**Return values.**
- 8-bit → `B`; 16-bit → `X` (an address-capable register, so a returned pointer is
  usable immediately — R-ABI-3);
- 32-bit, `struct`, and `union` → **hidden pointer**: the caller allocates the
  result space and passes its address as an implicit first argument in `X`; the
  callee writes the result there.

**Register save discipline.**
- **Callee-saved (preserved across a call): `Y`.** A function that uses `Y` saves
  and restores it. This gives the compiler one 16-bit register to hold a value —
  typically a loop-carried pointer — live across a call without spilling (R-ABI-4).
- **Caller-saved (clobberable): `A`, `B`/`D`, `X`, `CC`.** The caller preserves any
  it needs across a call.

**Stack cleanup.** The **caller** removes arguments after the call (keeps variadic
calls simple and the convention uniform).

**Why the boundary registers.** `D = A:B`, so an 8-bit value in `B` (the low half)
widens to 16-bit by just setting `A` — cheap C integer promotion (R-ISA-7). 16-bit
values are usually pointers, so passing/returning them in `X` lets them be
dereferenced or indexed with no move (R-ABI-3, R-ISA-5). Reserving `Y` rather than
spending it as a second argument register is what lets the convention satisfy
R-ABI-2 *and* R-ABI-4 together; BLIP can afford it because the 16-bit `SP`
displacement removes any need for `Y` as a frame pointer (R-ISA-2).

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

The complete instruction set, grouped by family. **Page 0 = 231 opcodes** (24 free of
the 255 usable after `0x80` is reserved as the page-1 prefix); **page 1 = 231 opcodes**
(25 free of 256). Each entry is one opcode; operand bytes (offset / immediate / mask)
follow per §8.1. This is a **flat list** (no opcode grids, §8.1): byte values run
sequentially in listing order — on page 0, `0x80` is reserved for the page-1 prefix and the
unused high values are the free slots. The *set* is verified for budget, hot/cold placement,
and requirement coverage (D-41 build pass). Placement rationale:
[d41-isa-refinement.md](d41-isa-refinement.md).

#### Page 0 — hot (no prefix), 231 opcodes

**Byte load/store (A, B) — 38.**
`LD A,$nn`, `LD A,(SP+n8)`, `LD A,(SP)`, `LD A,(X)`, `LD A,(X+n8)`, `LD A,(X+)`, `LD A,(X+D)`, `LD A,($nnnn)`, `LD A,(Y)`, `LD A,(Y+)`, `LD A,(Y+n8)`, `LD B,$nn`, `LD B,(SP+n8)`, `LD B,(SP)`, `LD B,(X)`, `LD B,(X+n8)`, `LD B,(X+)`, `LD B,(X+D)`, `LD B,($nnnn)`, `LD B,(Y)`, `LD B,(Y+)`, `LD B,(Y+n8)`, `ST A,(SP+n8)`, `ST A,(X)`, `ST A,(X+n8)`, `ST A,(X+)`, `ST A,($nnnn)`, `ST A,(Y)`, `ST A,(Y+n8)`, `ST A,(Y+)`, `ST B,(SP+n8)`, `ST B,(X)`, `ST B,(X+n8)`, `ST B,(X+)`, `ST B,($nnnn)`, `ST B,(Y)`, `ST B,(Y+n8)`, `ST B,(Y+)`.

**16-bit load/store (D, X, Y, SP) — 28.**
`LD D,$nnnn`, `LD X,$nnnn`, `LD Y,$nnnn`, `LD SP,$nnnn`, `LD D,($nnnn)`, `LD X,($nnnn)`, `LD Y,($nnnn)`, `ST D,($nnnn)`, `ST X,($nnnn)`, `ST Y,($nnnn)`, `LD D,(X)`, `ST D,(X)`, `LD D,(X+n8)`, `ST D,(X+n8)`, `LD D,(X++)`, `ST D,(X++)`, `LD D,(SP+n8)`, `LD X,(SP+n8)`, `LD Y,(SP+n8)`, `ST D,(SP+n8)`, `ST X,(SP+n8)`, `ST Y,(SP+n8)`, `LD D,(X+D)`, `ST D,(X+D)`, `LD D,(Y)`, `ST D,(Y)`, `LD D,(Y+n8)`, `ST D,(Y+n8)`.

**Byte ALU (ADD/SUB/CMP/AND/OR on A, B) — 67.**
`ADD A,$nn`, `ADD A,(X)`, `ADD A,(X+n8)`, `ADD A,(X+D)`, `ADD A,(SP+n8)`, `ADD A,($nnnn)`, `ADD A,(X+)`, `ADD A,(Y)`, `ADD B,$nn`, `ADD B,(X)`, `ADD B,(X+n8)`, `ADD B,(X+D)`, `ADD B,(SP+n8)`, `ADD B,($nnnn)`, `ADD B,(X+)`, `ADD B,(Y)`, `SUB A,$nn`, `SUB A,(X)`, `SUB A,(X+n8)`, `SUB A,(X+D)`, `SUB A,(SP+n8)`, `SUB A,($nnnn)`, `SUB A,(X+)`, `SUB A,(Y)`, `SUB B,$nn`, `SUB B,(X)`, `SUB B,(X+n8)`, `SUB B,(X+D)`, `SUB B,(SP+n8)`, `SUB B,($nnnn)`, `SUB B,(X+)`, `SUB B,(Y)`, `CMP A,$nn`, `CMP A,(X)`, `CMP A,(X+n8)`, `CMP A,(SP+n8)`, `CMP A,($nnnn)`, `CMP A,(Y)`, `CMP B,$nn`, `CMP B,(X)`, `CMP B,(X+n8)`, `CMP B,($nnnn)`, `CMP B,(Y)`, `AND A,$nn`, `AND A,(X)`, `AND A,(X+n8)`, `AND A,($nnnn)`, `AND A,(X+)`, `AND A,(Y)`, `AND B,$nn`, `AND B,(X)`, `AND B,(X+n8)`, `AND B,($nnnn)`, `AND B,(X+)`, `AND B,(Y)`, `OR A,$nn`, `OR A,(X)`, `OR A,(X+n8)`, `OR A,($nnnn)`, `OR A,(X+)`, `OR A,(Y)`, `OR B,$nn`, `OR B,(X)`, `OR B,(X+n8)`, `OR B,($nnnn)`, `OR B,(X+)`, `OR B,(Y)`.

**16-bit ALU, wide compare & D shifts — 18.**
`ADD D,$nnnn`, `ADD D,($nnnn)`, `ADD D,(SP+n8)`, `ADD D,(X)`, `ADD D,(X+n8)`, `ADD D,(X+D)`, `SUB D,$nnnn`, `SUB D,($nnnn)`, `SUB D,(SP+n8)`, `CMP D,$nnnn`, `CMP D,($nnnn)`, `CMP D,(SP+n8)`, `CMP X,$nnnn`, `CMP Y,$nnnn`, `CMP SP,$nnnn`, `ASL D,$n`, `LSR D,$n`, `ASR D,$n`.

**RMW & register-direct unary — 26.**
`INC A`, `DEC A`, `CLR A`, `TST A`, `LSR A`, `ASR A`, `ASL A`, `INC B`, `DEC B`, `CLR B`, `TST B`, `LSR B`, `ASR B`, `ASL B`, `INC (X)`, `INC (X+n8)`, `INC (SP+n8)`, `DEC (X)`, `DEC (X+n8)`, `DEC (SP+n8)`, `CLR (X)`, `CLR (X+n8)`, `TST (X)`, `TST (X+n8)`, `INC ($nnnn)`, `DEC ($nnnn)`.

**Control flow — 29.**
`BRA rel8`, `BRN rel8`, `BHI rel8`, `BLS rel8`, `BCC rel8`, `BCS rel8`, `BNE rel8`, `BEQ rel8`, `BVC rel8`, `BVS rel8`, `BPL rel8`, `BMI rel8`, `BGE rel8`, `BLT rel8`, `BGT rel8`, `BLE rel8`, `BSR rel8`, `RTS`, `JMP $nnnn`, `JMP X`, `JMP Y`, `JMP (X)`, `JMP (X+n8)`, `JMP (X+D)`, `JSR $nnnn`, `JSR (X)`, `JSR Y`, `JSR (X+n8)`, `JSR (X+D)`.

**System / inherent / LEA / moves — 25.**
`NOP`, `SEX`, `MUL`, `ABX`, `PSHS mask8`, `PULS mask8`, `ANDCC $nn`, `ORCC $nn`, `LD reg,reg`, `XCHG reg,reg`, `TAS (X)`, `TAS (X+n8)`, `LEA X,X+n8`, `LEA X,X+A`, `LEA X,X+B`, `LEA X,X+D`, `LEA X,X+`, `LEA X,X++`, `LEA X,-X`, `LEA X,Y+n8`, `LEA X,SP+n8`, `LEA Y,Y+n8`, `LEA Y,SP+n8`, `LEA SP,SP+n8`, `LEA SP,X+n8`.

#### Page 1 — cold (`0x80` prefix), 231 opcodes

**System / privileged / cold TAS & LEA — 31.**
`DAA`, `SYNC`, `RTI`, `SWI`, `SWI2`, `SWI3`, `CWAI $nn`, `SEI`, `CLI`, `HALT`, `LDMMU $nn`, `STMMU $nn`, `LD USP,X`, `LD USP,Y`, `LD USP,D`, `LD X,USP`, `LD Y,USP`, `LD D,USP`, `XCHG X,USP`, `XCHG Y,USP`, `XCHG D,USP`, `TAS (Y)`, `TAS (Y+n8)`, `TAS (SP+n8)`, `TAS ($nnnn)`, `LEA X,X+n16`, `LEA Y,Y+n16`, `LEA SP,SP+n16`, `LEA X,PC+n8`, `LEA Y,PC+n8`, `LEA SP,Y+n8`.

**Control flow — long branches & cold JMP/JSR — 40.**
`LBRA rel16`, `LBRN rel16`, `LBHI rel16`, `LBLS rel16`, `LBCC rel16`, `LBCS rel16`, `LBNE rel16`, `LBEQ rel16`, `LBVC rel16`, `LBVS rel16`, `LBPL rel16`, `LBMI rel16`, `LBGE rel16`, `LBLT rel16`, `LBGT rel16`, `LBLE rel16`, `LBSR rel16`, `JMP (X+n16)`, `JMP (X+A)`, `JMP (X+B)`, `JMP (Y)`, `JMP (Y+n8)`, `JMP (Y+n16)`, `JMP (Y+A)`, `JMP (Y+B)`, `JMP (Y+D)`, `JMP (PC+n8)`, `JMP (PC+n16)`, `JSR (X+n16)`, `JSR (X+A)`, `JSR (X+B)`, `JSR X`, `JSR (Y)`, `JSR (Y+n8)`, `JSR (Y+n16)`, `JSR (Y+A)`, `JSR (Y+B)`, `JSR (Y+D)`, `JSR (PC+n8)`, `JSR (PC+n16)`.

**Byte load/store (cold modes) — 36.**
`ST A,(SP)`, `ST B,(SP)`, `LD A,(X++)`, `LD B,(X++)`, `LD A,(--X)`, `LD B,(--X)`, `LD A,(-X)`, `LD B,(-X)`, `ST A,(X++)`, `ST B,(X++)`, `ST A,(--X)`, `ST B,(--X)`, `ST A,(-X)`, `ST B,(-X)`, `LD A,(X+A)`, `LD A,(X+B)`, `LD B,(X+A)`, `LD B,(X+B)`, `ST A,(X+A)`, `ST A,(X+B)`, `ST A,(X+D)`, `ST B,(X+A)`, `ST B,(X+B)`, `ST B,(X+D)`, `LD A,(X+n16)`, `LD B,(X+n16)`, `ST A,(X+n16)`, `ST B,(X+n16)`, `LD A,(SP+n16)`, `LD B,(SP+n16)`, `ST A,(SP+n16)`, `ST B,(SP+n16)`, `LD A,(-Y)`, `LD B,(-Y)`, `ST A,(-Y)`, `ST B,(-Y)`.

**16-bit load/store (cold modes) — 42.**
`LD X,(Y)`, `ST X,(Y)`, `LD Y,(X)`, `ST Y,(X)`, `LD D,(SP)`, `LD X,(SP)`, `LD Y,(SP)`, `ST D,(SP)`, `ST X,(SP)`, `ST Y,(SP)`, `LD X,(X++)`, `LD Y,(X++)`, `ST Y,(X++)`, `LD D,(Y++)`, `ST D,(Y++)`, `LD X,(Y++)`, `ST X,(Y++)`, `LD D,(--X)`, `ST D,(--X)`, `ST Y,(--X)`, `LD D,(--Y)`, `ST D,(--Y)`, `ST X,(--Y)`, `LD Y,(X+n8)`, `ST Y,(X+n8)`, `LD X,(Y+n8)`, `ST X,(Y+n8)`, `LD D,(X+n16)`, `LD X,(X+n16)`, `ST D,(X+n16)`, `ST X,(X+n16)`, `LD D,(SP+n16)`, `LD X,(SP+n16)`, `LD Y,(SP+n16)`, `ST D,(SP+n16)`, `ST X,(SP+n16)`, `ST Y,(SP+n16)`, `LD Y,(X+D)`, `ST Y,(X+D)`, `LD D,(Y+D)`, `LD SP,($nnnn)`, `ST SP,($nnnn)`.

**Byte ALU (cold modes + ADC/SBC/EOR/BIT) — 46.**
`ADD A,(SP)`, `ADD B,(SP)`, `SUB A,(SP)`, `SUB B,(SP)`, `CMP A,(SP)`, `CMP B,(SP)`, `AND A,(SP)`, `AND B,(SP)`, `OR A,(SP)`, `OR B,(SP)`, `ADC A,$nn`, `ADC B,$nn`, `ADC A,($nnnn)`, `ADC B,($nnnn)`, `ADC A,(X)`, `ADC B,(X)`, `ADC A,(X+n8)`, `ADC B,(X+n8)`, `ADC A,(SP+n8)`, `ADC B,(SP+n8)`, `SBC A,$nn`, `SBC B,$nn`, `SBC A,($nnnn)`, `SBC B,($nnnn)`, `SBC A,(X)`, `SBC B,(X)`, `SBC A,(X+n8)`, `SBC B,(X+n8)`, `SBC A,(SP+n8)`, `SBC B,(SP+n8)`, `EOR A,$nn`, `EOR B,$nn`, `EOR A,($nnnn)`, `EOR B,($nnnn)`, `EOR A,(X)`, `EOR B,(X)`, `EOR A,(X+n8)`, `EOR B,(X+n8)`, `BIT A,$nn`, `BIT B,$nn`, `BIT A,($nnnn)`, `BIT B,($nnnn)`, `BIT A,(X)`, `BIT B,(X)`, `BIT A,(X+n8)`, `BIT B,(X+n8)`.

**16-bit ALU & wide compare (cold) — 22.**
`ADC D,$nnnn`, `ADC D,($nnnn)`, `ADC D,(SP+n8)`, `ADC D,(X)`, `ADC D,(X+n8)`, `SBC D,$nnnn`, `SBC D,($nnnn)`, `SBC D,(SP+n8)`, `SBC D,(X)`, `SBC D,(X+n8)`, `ADD D,(X++)`, `ADD D,(--X)`, `SUB D,(X)`, `SUB D,(X+n8)`, `SUB D,(X+D)`, `CMP D,(X)`, `CMP D,(X+n8)`, `CMP X,($nnnn)`, `CMP Y,($nnnn)`, `CMP SP,($nnnn)`, `CMP X,(SP+n8)`, `CMP X,(X)`.

**RMW & register-direct unary (cold ops) — 14.**
`NEG A`, `COM A`, `ROL A`, `ROR A`, `NEG B`, `COM B`, `ROL B`, `ROR B`, `INC (X+)`, `DEC (X+)`, `INC (Y)`, `DEC (Y)`, `CLR (Y)`, `TST (Y)`.

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
| `SEI`/`CLI` | - | - | - | - | - |
| `LDMMU`/`STMMU` | - | - | - | - | - |
| `SEX` | * | * | 0 | - | - |
| `MUL` | - | * | - | * | - |
| `DAA` | * | * | ? | * | - |
| `ANDCC`/`ORCC`/`CWAI` | per mask byte | | | | |
| `RTI`, `PULS CC` | all `CC` restored from stack | | | | |
| `SWI`/`SWI2`/`SWI3` | set `I`; no N/Z/V/C/H | | | | |

### 8.6 Free slots & growth

The two pages each leave room for growth (D-41): **page 0 has 24 free slots** (of the 255
usable, `0x80` being spent as the page-1 prefix) and **page 1 has 25 free** (of 256). The
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
R-BUILD-1). The count is an immediate byte; the microcode shifts `n` positions and
saturates at 16 (C leaves shifts ≥ the operand width undefined, so conforming code
never relies on a larger count).

A **runtime-variable** shift count is deliberately not encoded: the value occupies
`D = A:B`, so a register-held count would have to live in `X`/`Y` — the pointer and
return registers — which is too costly to standardise. The constant-count form
captures the dominant case; a register-count form remains a future option if
profiling shows runtime-variable shifts are hot.

---

## 9. Open questions for this document

1. **Atomicity primitive (§6):** whether to add a test-and-set-like instruction for
   kernel locking, or rely on interrupt masking alone.

*Decided:* registers `A B D X Y SP` (no `U`/`DP`); little-endian; privilege with
banked `SSP`/`USP` and the mode bit in `CC` (D-22); internal MMU
(physical external bus, 16 MB / 8 KB pages, identity-mapped at reset, programmed by
privileged `LDMMU`/`STMMU`); memory-mapped I/O in a single physical I/O page reached
through the MMU (D-28); reset vector and physical memory map (reset entry `0x000000`,
common at `0xE000`, vector table at `0xFFE0`; firmware monitor/loader boots the kernel
from a block device — D-31); calling convention (§7); the **two-page** flat encoding
(no postbyte) and the instruction inventory (§8; D-41); and the assembly
notation house style (§4.1 — verb/register split, bare `$`-hex immediates,
parenthesised memory, `LD`/`XCHG` register moves; D-25).
