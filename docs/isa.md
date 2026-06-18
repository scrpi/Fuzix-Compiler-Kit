# BLIP — Instruction Set Architecture

> The programmer's / compiler's contract. For *why these goals* see
> [docs/goals.md](goals.md); for *how the silicon realizes this* see
> [docs/hardware.md](hardware.md).
>
> **Status:** the rationale, register model, addressing modes, and encoding map
> below are a **v0 proposal** under active design review. The §8 opcode table is the
> full 256-entry assignment (generated and adversarially checked — D-20), and the
> assembly notation follows the house style of §4.1 (D-25).

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
the blinkenlights: `MAR` (memory address register, 16-bit logical), `IR`
(instruction register), `µPC` (microprogram counter), and ALU operand/temp
latches `TA`/`TB`. See [docs/hardware.md](hardware.md).

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
| Indexed: indirect | `((X+n))` `((X++))` | pointer-to-pointer, jump tables |
| PC-relative | `(PC+n)` `((PC+n))` | position-independent code/data |
| Relative (branch) | `label` | conditional/unconditional branches (8- and 16-bit) |

The two that earn their keep for C:

- **`(SP+n)`** — a local at frame offset *n* is one instruction, no frame-pointer
  setup tax. This is the single biggest win over a frame-pointer machine.
- **`LEA`** (load effective address, §7) — computes `r = address(mode)` so
  `p += n`, `&local`, and `&array[i]` are single instructions; it's how pointer
  arithmetic stays cheap. `LEA` names the *address*, so its operand is written
  **bare** (`LEA X,X+4`), not parenthesised.

Constant offsets come in **5-bit**, **8-bit**, and **16-bit** widths (chosen by
the postbyte, §5.2) so small frames and struct accesses stay compact while large
frames still work.

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
   (`(X+B)`), an auto-inc/dec form (`(X+)`, `(-X)`), an absolute address (`($1234)`),
   or a further indirection (`((X+6))`). An operand that *names an address* rather
   than dereferencing it stays bare — a `LEA` result and a jump/branch target (so
   `JMP X` jumps to the address in `X`, whereas `JMP (X)` jumps *through* it).
4. **Register↔register moves are `LD` / `XCHG`.** A copy is `LD dst,src`; a swap is
   `XCHG`. The assembler selects the opcode from the operand kinds (register,
   immediate, or memory), so the one `LD` verb covers them all.

---

## 5. Instruction encoding

### 5.1 Opcode space — a single page
There is exactly **one 256-entry opcode page** — no prefix bytes. Every instruction
is one opcode byte followed by 0–3 trailing bytes: an optional indexed postbyte,
then 0–2 offset / immediate / address bytes. Decode is microcoded, so the opcode
byte need not be bit-field-structured; the full table is §8.

```
[ opcode ] [ postbyte? ] [ operand bytes 0..2 ]
```

### 5.2 The indexed **postbyte**
Indexed-mode instructions carry one postbyte that selects the index register and
the sub-mode (zero/constant/accumulator offset, auto inc/dec, indirect, PC-rel).
The full bit layout is specified in §8.3; the *set* of modes it must encode is
fixed by §4.

### 5.3 Branch offsets
Short (conditional) branches use an 8-bit signed offset (`Bcc`, `0x20–0x2F`); long
branches use a 16-bit signed offset (`LBcc`, `0xB0–0xBF`) so the compiler is never
boxed in by ±128 bytes.

> **Resolved:** single opcode page (no prefix pages); the postbyte bit layout is in
> §8.3 and operands are little-endian (§3).

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
- **Interrupts.** One maskable `IRQ` (mask `CC.I`) plus a non-maskable `NMI`. Entry
  stacks a **minimal frame** (`PC` and `CC`) on `SSP`; the handler saves any other
  registers it uses with `PSHS`/`PULS` (matching the caller-saves ABI). `RTI`
  restores `CC` (hence the mode) and `PC`.
- **System call / trap.** A software interrupt (`SWI`, possibly `SWI2`/`SWI3`) is
  FUZIX's kernel-entry trap: it enters supervisor mode with a saved frame.
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
- **Reset.** On reset the CPU enters supervisor mode with interrupts masked and
  begins at a fixed reset vector (R-CPU-7). **There is no "translation off" state —
  only the identity map.** Address translation is always active; at reset it is the
  transparent **identity map of the low 64 KB** (logical = physical for
  `0x0000–0xFFFF`), so the machine runs before software has configured any map
  (R-MEM-7). The kernel later replaces it with real per-process maps via
  `LDMMU`/`STMMU`.
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

> The full instruction encoding, on a **single 256-opcode page** (no prefix pages —
> see [decision-log.md](decision-log.md) D-21). It was generated exhaustively and
> checked by independent adversarial passes (collisions/coverage, flag-effect
> consistency, addressing/operand lengths, completeness); coverage is **256/256,
> collision-free**, and the fixes applied are recorded in D-20. **Byte lengths and
> flag effects are exact**; cycle counts are deferred until the datapath bus count
> ([hardware.md](hardware.md) §9) is settled, since they depend on it.

### 8.1 Encoding model

Every instruction is **one opcode byte** plus 0–3 trailing bytes: an optional
indexed postbyte (§8.3), then 0–2 offset/immediate/address bytes. No prefix bytes;
maximum length is 4 (opcode + postbyte + 2). Decode is microcoded, so the opcode
need not be bit-structured — but the regular grids below are kept because they let
shared microcode serve a whole band.

| Band | Contents |
|------|----------|
| `0x00–0x1F` | Inherent / system / inter-register (incl. relocated `SEI/CLI`, USP banking, `LDMMU/STMMU`, `TAS`) |
| `0x20–0x2F` | Short branches `Bcc rel8` — **low nibble = condition** |
| `0x30–0x3F` | Effective address, `JMP`, and the wide compares `CMP D/CMP Y/CMP SP` |
| `0x40–0x7F` | Read-modify-write unary ops — a **4×16 grid**: high nibble = operand (`4`=A, `5`=B, `6`=indexed, `7`=extended), low nibble = operation |
| `0x80–0xAF` | A/D ALU & load group — **3×16**: high nibble = mode (`8`=immediate, `9`=indexed, `A`=extended), low nibble = operation |
| `0xB0–0xBF` | Long branches `LBcc rel16` — **low nibble = condition** (mirrors `0x20–0x2F`) |
| `0xC0–0xEF` | B / wide-register group — **3×16**: (`C`=immediate, `D`=indexed, `E`=extended) |
| `0xF0–0xFF` | 16-bit wide ops: `SP` load/store (`0xF0–0xF4`), `ADC D`/`SBC D` (`0xF5–0xFA`), `D` multi-bit shifts (`0xFB–0xFD`); `0xFE/0xFF` reserved |

Stores (low nibble `7`/`D`/`F`) and `JSR` (low nibble `D`) exist only in the
memory-operand rows; the immediate rows leave those slots reserved (store-immediate
and JSR-immediate are meaningless) — intentional, not a gap.

### 8.2 Primary opcode matrix (the whole 256-byte page)

Rows = high nibble, columns = low nibble; `—` = reserved. A cell shows the operation
and (where it has one) its target register in the house style of §4.1 — e.g. `LD A`,
`SUB D`, `CMP SP`. As in any `LD`-unified ISA the `LD` verb appears in several cells:
the memory/immediate loads (`LD A`, `LD X`, …), the register-move at `0x06`, and the
USP-banking form at `0x1A`; the assembler picks the opcode from the operands. Addressing
mode and length are given per band below.

|       | x0 | x1 | x2 | x3 | x4 | x5 | x6 | x7 | x8 | x9 | xA | xB | xC | xD | xE | xF |
|-------|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|
| **0x**| NOP | SYNC | DAA | SEX | MUL | ABX | LD | XCHG | PSHS | PULS | ANDCC | ORCC | SEI | CLI | — | — |
| **1x**| RTS | RTI | SWI | SWI2 | SWI3 | CWAI | BSR | LBSR | HALT | TAS | LD | XCHG | LDMMU | STMMU | — | — |
| **2x**| BRA | BRN | BHI | BLS | BCC | BCS | BNE | BEQ | BVC | BVS | BPL | BMI | BGE | BLT | BGT | BLE |
| **3x**| LEA X | LEA Y | LEA SP | CMP D | CMP Y | CMP SP | JMP | JMP | CMP D | CMP D | CMP Y | CMP Y | CMP SP | CMP SP | — | — |
| **4x**| NEG A | — | — | COM A | LSR A | — | ROR A | ASR A | ASL A | ROL A | DEC A | — | INC A | TST A | — | CLR A |
| **5x**| NEG B | — | — | COM B | LSR B | — | ROR B | ASR B | ASL B | ROL B | DEC B | — | INC B | TST B | — | CLR B |
| **6x**| NEG | — | — | COM | LSR | — | ROR | ASR | ASL | ROL | DEC | — | INC | TST | — | CLR |
| **7x**| NEG | — | — | COM | LSR | — | ROR | ASR | ASL | ROL | DEC | — | INC | TST | — | CLR |
| **8x**| SUB A | CMP A | SBC A | SUB D | AND A | BIT A | LD A | — | EOR A | ADC A | OR A | ADD A | CMP X | — | LD X | — |
| **9x**| SUB A | CMP A | SBC A | SUB D | AND A | BIT A | LD A | ST A | EOR A | ADC A | OR A | ADD A | CMP X | JSR | LD X | ST X |
| **Ax**| SUB A | CMP A | SBC A | SUB D | AND A | BIT A | LD A | ST A | EOR A | ADC A | OR A | ADD A | CMP X | JSR | LD X | ST X |
| **Bx**| LBRA | LBRN | LBHI | LBLS | LBCC | LBCS | LBNE | LBEQ | LBVC | LBVS | LBPL | LBMI | LBGE | LBLT | LBGT | LBLE |
| **Cx**| SUB B | CMP B | SBC B | ADD D | AND B | BIT B | LD B | — | EOR B | ADC B | OR B | ADD B | LD D | — | LD Y | — |
| **Dx**| SUB B | CMP B | SBC B | ADD D | AND B | BIT B | LD B | ST B | EOR B | ADC B | OR B | ADD B | LD D | ST D | LD Y | ST Y |
| **Ex**| SUB B | CMP B | SBC B | ADD D | AND B | BIT B | LD B | ST B | EOR B | ADC B | OR B | ADD B | LD D | ST D | LD Y | ST Y |
| **Fx**| LD SP | LD SP | ST SP | ST SP | LD SP | ADC D | ADC D | ADC D | SBC D | SBC D | SBC D | ASL D | LSR D | ASR D | — | — |

Mode/length per cell where it isn't obvious from the band:

- **`3x`:** `0x33/0x38/0x39` = `CMP D` imm/indexed/extended; `0x34/0x3A/0x3B` = `CMP Y`
  imm/indexed/extended; `0x35/0x3C/0x3D` = `CMP SP` imm/indexed/extended; `0x36` = `JMP`
  indexed (bare target, e.g. `JMP X`), `0x37` = `JMP` extended (`JMP $nnnn`).
- **`1x` relocated system ops:** `0x19 TAS` indexed (atomic test-and-set);
  `0x1A`/`0x1B` = the privileged *USP-banking* moves — the `LD`/`XCHG` transfer/exchange
  opcode with `USP` as a register operand (`LD USP,X` / `XCHG X,USP`), distinct from the
  unprivileged register moves at `0x06`/`0x07`; `0x1C LDMMU`/`0x1D STMMU` take an `imm8`
  page-table entry index (bare `$`-hex; data via `D`).
- **`Fx`:** `0xF0` `LD SP` indexed, `0xF1` `LD SP` extended, `0xF2` `ST SP` indexed,
  `0xF3` `ST SP` extended, `0xF4` `LD SP,$nnnn` (immediate). `0xF5–0xF7` `ADC D`
  imm/indexed/extended, `0xF8–0xFA` `SBC D` imm/indexed/extended (16-bit
  add/subtract-with-carry on `D`). `0xFB` `ASL D,$n`, `0xFC` `LSR D,$n`, `0xFD`
  `ASR D,$n` — shift `D` by the immediate count `n` (length 2). See §8.8.
- **Lengths:** inherent = 1; `imm8` / mask / entry-selector = 2; `imm16` / extended /
  `rel16` = 3; `rel8` = 2; postbyte ops (`LD`/`XCHG reg,reg`, `PSHS`/`PULS`) = 2;
  **indexed = 2–4** (opcode + postbyte + 0/1/2 offset bytes).

### 8.3 Indexed postbyte

One postbyte follows the opcode for any indexed instruction; bit 7 picks the form.
Register field `RR`: `00`=X, `01`=Y, `10`=SP, `11`=PC.

**Form A — 5-bit constant offset (bit7 = 0):** `0 | RR(6:5) | nnnnn(4:0)` — signed
5-bit offset −16…+15, no extra bytes, no indirect. The assembler's densest case.

**Form B — general (bit7 = 1):** `1 | RR(6:5) | I(4) | TTTT(3:0)`, where `I` =
indirect (one extra level of dereference):

| `TTTT` | Mode | Extra bytes |
|--------|------|-------------|
| `0000` | `(R+)` auto-inc by 1 (post) | 0 — `I` must be 0 |
| `0001` | `(R++)` auto-inc by 2 (post) | 0 |
| `0010` | `(-R)` auto-dec by 1 (pre) | 0 — `I` must be 0 |
| `0011` | `(--R)` auto-dec by 2 (pre) | 0 |
| `0100` | `(R)` zero offset | 0 |
| `0101` | `(R+B)` accumulator-B offset | 0 |
| `0110` | `(R+A)` accumulator-A offset | 0 |
| `1000` | `(R+n)` 8-bit signed offset | 1 |
| `1001` | `(R+n)` 16-bit signed offset | 2 (LE) |
| `1011` | `(R+D)` accumulator-D offset | 0 |
| `1100` | `(PC+n)` 8-bit PC-relative | 1 (RR→PC) |
| `1101` | `(PC+n)` 16-bit PC-relative | 2 (RR→PC) |
| `1111` | `(($nnnn))` extended-indirect | 2 (requires `I`=1) |
| `0111`,`1010`,`1110` | reserved | — |

There is one canonical encoding per (mode, register, width, indirect) tuple, so the
assembler/disassembler round-trips. The privileged USP-banking moves (`0x1A`/`0x1B`)
do **not** use this postbyte — they use the register-move (`LD`/`XCHG`) register-code
postbyte (§8.4) with the `USP` code.

### 8.4 Register & flag encoding

**`CC` (8 bits, MSB→LSB):** `M – H I N Z V C` — bit7 `M` supervisor/user mode
(1 = supervisor), bit6 reserved, bit5 `H` half-carry, bit4 `I` IRQ mask, bit3 `N`,
bit2 `Z`, bit1 `V`, bit0 `C`. `M` lives in `CC` so it saves/restores automatically
with `CC` on trap/`RTI`, and it is **supervisor-write-only** (user-mode `CC` writes
can't change it — §8.7).

**Register-move (`LD`/`XCHG`) postbyte:** `src(7:4) | dst(3:0)`, each a 4-bit register
code; source and destination must be the same width. (A copy is written
destination-first, `LD dst,src`, but the postbyte keeps `src` in the high nibble;
`XCHG` is symmetric.)
- 16-bit: `D`=0, `X`=1, `Y`=2, `SP`=3, `PC`=4. (e.g. `LD X,D` = `0x01`.)
- 8-bit: `A`=8, `B`=9, `CC`=`0xA`. (e.g. `XCHG A,B` = `0x89`.)
- `USP`=`0xF` — referencing it is the **privileged** USP-banking form (`0x1A`/`0x1B`),
  which traps in user mode. Codes `5`,`6`,`7`,`B`–`E` reserved.

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

### 8.6 Relocations & reserved slots

Going single-page meant packing the ops that had been on prefix pages into holes:

- **Long branches** `LBcc` fill row `0xB0–0xBF` (low nibble = condition, mirroring
  `0x20–0x2F`), so one condition-decoder serves both.
- **Wide compares** `CMP D/CMP Y/CMP SP` (9 forms) take the `0x30`-row holes (`0x33–0x3D`).
- **Interrupt-mask** `SEI/CLI` → `0x0C/0x0D`; **USP banking** (the `LD`/`XCHG` USP
  forms) → `0x1A/0x1B`; **MMU** `LDMMU/STMMU` → `0x1C/0x1D`; **`TAS`** → `0x19`;
  **`HALT`** → `0x18`.

**Reserved (free for growth):** `0x0E/0x0F`; `0x1E/0x1F`; `0x3E/0x3F`; the RMW holes
(low nibbles `1/2/5/B/E` in each of `0x4x–0x7x`); the immediate-row holes
`0x87/0x8D/0x8F` (A/D) and `0xC7/0xCD/0xCF` (B/wide); and `0xFE/0xFF`. ~34 slots in
all — the hard 256 ceiling is accepted (D-21). (`0xF5–0xFD` now hold `ADC D`/`SBC D`
and the `D` shifts — D-23.)

### 8.7 Privilege & the user-mode `CC` mask

Privileged instructions (trap in user mode): `SYNC` (`0x01`), `RTI` (`0x11`),
`SEI`/`CLI` (`0x0C`/`0x0D`), `HALT` (`0x18`), the USP-banking `LD`/`XCHG`
(`0x1A`/`0x1B`), `LDMMU`/`STMMU` (`0x1C`/`0x1D`). `SWI`/`SWI2`/`SWI3` are
**unprivileged** — the syscall gateway. The plain register moves `LD`/`XCHG`
(`0x06`/`0x07`) stay unprivileged; only the USP-banking variants are privileged.

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

1. **Reset details (§6):** the reset-vector location and the exact reset values of
   `PC`/`SP`. The vector must lie **outside** `0xE000–0xFFFF`, which the boot
   identity map exposes as the memory-mapped I/O page (D-28).

*Decided:* registers `A B D X Y SP` (no `U`/`DP`); little-endian; privilege with
banked `SSP`/`USP` and the mode bit in `CC` (D-22); internal MMU
(physical external bus, 16 MB / 8 KB pages, identity-mapped at reset, programmed by
privileged `LDMMU`/`STMMU`); memory-mapped I/O in a single physical I/O page reached
through the MMU (D-28); calling convention (§7); the full **single-page**
encoding, indexed postbyte, and 256-entry opcode table (§8); and the assembly
notation house style (§4.1 — verb/register split, bare `$`-hex immediates,
parenthesised memory, `LD`/`XCHG` register moves; D-25).
