# BLIP — Instruction Set Architecture

> The programmer's / compiler's contract. For *why these goals* see
> [docs/goals.md](goals.md); for *how the silicon realizes this* see
> [docs/hardware.md](hardware.md).
>
> **Status:** the rationale, register model, addressing modes, and encoding map
> below are a **v0 proposal** under active design review. The opcode table in
> §7 is a representative first draft, not the final 256-entry assignment — the
> full enumeration is the next step once the register model is signed off.

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

**`CC` layout (proposed):** ALU flags `N Z V C`, half-carry `H`, interrupt masks
`I`/`F`, an "entire-frame" bit `E` (so `RTI` knows how much to restore), and the
**`M` supervisor/user mode bit**. (Exact bit positions / whether mode lives in
`CC` or separate state is [open](#8-open-questions-for-this-document).)

**Why this set.** Two 8-bit accumulators that pair into 16-bit `D` give cheap
`char` math *and* 16-bit `int`/pointer math. `X` and `Y` plus stack-relative
addressing (`n,SP`) cover C's pointer and locals needs — this is exactly the
**STM8** register shape (`X`, `Y`, `SP`), which SDCC already targets well, so the
backend has a proven template. The banked `SSP`/`USP` give the FUZIX kernel a
stack a misbehaving process literally cannot reach, turning the MMU's per-process
isolation into genuine kernel protection.

**Why no `U` and no `DP`.** We drop the 6809's second user stack `U` (a third
live pointer is a luxury; `X`/`Y`/`n,SP` suffice, per STM8) — the second stack
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
| Immediate | `#imm8` / `#imm16` | constants |
| Extended | `addr16` | absolute 16-bit address |
| Indexed: constant offset | `n,X` `n,Y` `n,SP` | **stack-relative locals**, struct fields |
| Indexed: zero offset | `,X` | pointer dereference |
| Indexed: accumulator offset | `A,X` `B,X` `D,X` | `array[i]` in one instruction |
| Indexed: auto inc/dec | `,X+` `,X++` `,-X` `,--X` | `*p++`, stack-walks |
| Indexed: indirect | `[n,X]` `[,X++]` | pointer-to-pointer, jump tables |
| PC-relative | `n,PCR` `[n,PCR]` | position-independent code/data |
| Relative (branch) | `label` | conditional/unconditional branches (8- and 16-bit) |

The two that earn their keep for C:

- **`n,SP`** — a local at frame offset *n* is one instruction, no frame-pointer
  setup tax. This is the single biggest win over the Z80.
- **`LEA`** (load effective address, §7) — computes `r = address(mode)` so
  `p += n`, `&local`, and `&array[i]` are single instructions; it's how pointer
  arithmetic stays cheap.

Constant offsets come in **5-bit**, **8-bit**, and **16-bit** widths (chosen by
the postbyte, §5.2) so small frames and struct accesses stay compact while large
frames still work.

---

## 5. Instruction encoding

### 5.1 Opcode space and prefix pages
Instructions are variable length. The first byte is the **primary opcode**, a
256-entry map (§7). Two **prefix bytes** (working names `P2`, `P3`) open two
additional 256-entry pages for less-common operations (wide ops, the second set
of conditional branches, system instructions) — the same technique the 6809 uses
with its `$10`/`$11` prefixes. This keeps common instructions one byte while
leaving room to grow.

```
[ prefix? ] [ opcode ] [ postbyte? ] [ operand bytes 0..2 ]
```

### 5.2 The indexed **postbyte**
Indexed-mode instructions carry one postbyte that selects the index register and
the sub-mode (zero/constant/accumulator offset, auto inc/dec, indirect, PC-rel).
The postbyte layout is a BLIP design choice (it need not copy the 6809 bit-for-
bit) and is **TBD**; the *set* of modes it must encode is fixed by §4.

### 5.3 Branch offsets
Short (conditional) branches use an 8-bit signed offset; long branches use a
16-bit signed offset (via a prefix page) so the compiler is never boxed in by
±128 bytes.

> **Open:** prefix-page assignment, the exact postbyte bit layout, and whether
> immediate/branch operands are little- or big-endian (ties to §3 endianness).

---

## 6. System / privileged behaviour (for FUZIX)

BLIP has two CPU modes, **supervisor** and **user**, selected by the `CC.M` mode
bit (see [§2](#2-programming-model-register-file-v0)). User code runs in user
mode on `USP`; the kernel runs in supervisor mode on `SSP`. This gives a real
hardware kernel/user boundary on top of the per-process address map.

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
  **privilege-violation trap**): MMU control (`LDMMU`/`STMMU`), `RTI`,
  interrupt-mask changes, halt/`SYNC`, and the `SSP`/`USP` banking moves. `SWI`
  and everything a process needs for ordinary computation stay unprivileged.
- **Interrupts.** Maskable `IRQ` (mask `CC.I`) and a faster `FIRQ` (mask `CC.F`)
  that stacks a minimal frame; a non-maskable `NMI`. The frame is pushed on
  `SSP`; `RTI` restores per `CC.E`.
- **System call / trap.** A software interrupt (`SWI`, possibly `SWI2`/`SWI3`) is
  FUZIX's kernel-entry trap: it enters supervisor mode with a saved frame.
- **MMU control.** Address translation is internal to the CPU (see
  [docs/hardware.md](hardware.md) §3); its page table is an internal privileged
  register file, written only in supervisor mode by dedicated instructions
  (`LDMMU`/`STMMU`). It is reprogrammed on a context switch. A region of memory
  stays mapped at a fixed location in every map set, for the always-resident
  kernel code and the inter-map copy routines (R-MEM-4); the active map set follows
  the privilege mode (R-MEM-5).
- **Reset.** On reset the CPU enters supervisor mode with interrupts masked and
  begins at a fixed reset vector (R-CPU-7); the page table comes up as an identity
  map of the low 64 KB (logical = physical), so the machine runs before any
  translation is configured (R-MEM-7).
- **Atomicity.** At minimum, disabling interrupts around critical sections; a
  test-and-set-like primitive is a possible convenience (TBD).

---

## 7. Calling convention (ABI)

> The single, stable convention that the C toolchain and hand-written assembly
> both follow (R-ABI-1) — fixed, not an implementation detail free to drift.

**Reentrancy & locals.** Parameters, locals, and return linkage live on a
per-call stack; locals are reached by `n,SP` displacement, with no frame-pointer
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

## 8. Opcode table (DRAFT v0 — representative, not final)

> This section lays out the **map** (how the 256-entry primary space is carved
> up) and lists representative instructions per group with their addressing
> modes. Exact opcode byte values, cycle counts, and flag effects are filled in
> once the register model (§2) and encoding (§5) are locked. **Do not treat the
> hex values as final** — several are placeholders to show the layout.

### 8.1 Primary opcode map (how the 256 bytes are grouped)

| Range (hex) | Group |
|-------------|-------|
| `00–0F` | Inherent / system (`NOP`, `RTS`, `RTI`, `SWI`, `SYNC`, `SEI`/`CLI`, …) |
| `10–11` | **Prefix bytes** `P2` / `P3` (open pages 2 and 3) |
| `12–1F` | Inter-register ops (`TFR`, `EXG`, `LEA`, `PSH`/`PUL`) |
| `20–2F` | Short conditional branches (`BEQ`, `BNE`, `BCC`, `BCS`, `BGE`, …) |
| `30–3F` | Stack / address (`LEAX/Y`, `LEASP`, `PSHS/PULS`) |
| `40–5F` | Accumulator inherent ops on `A`/`B` (`NEG`, `COM`, `INC`, `DEC`, `ASL`, `LSR`, `ROL`, `ROR`, `CLR`, `TST`) |
| `60–7F` | Memory/indexed read-modify-write (same ops as `40–5F`, indexed & extended) |
| `80–BF` | `A`/`D`-oriented ALU & loads (`SUB`,`CMP`,`SBC`,`AND`,`BIT`,`LD`,`EOR`,`ADC`,`OR`,`ADD`, `LDX/Y`, `JSR`, …) across immediate/indexed/extended |
| `C0–FF` | `B`-oriented ALU & loads + 16-bit (`LDD`,`STD`,`LDX`,`STX`,`LDY`,`STY`,`LDSP`,`STSP`, stores) across the same mode families |

(This is intentionally 6809-shaped so the structure is familiar and regular for
microcode and for the assembler; the exact assignments are ours to set.)

### 8.2 Representative instructions

**Data movement**
```
LD{A,B,D,X,Y,SP}  <ea>       ; load   (imm/indexed/extended)
ST{A,B,D,X,Y,SP}  <ea>       ; store
TFR  r1,r2                   ; register -> register (like sizes)
EXG  r1,r2                   ; exchange
LEA{X,Y,SP} <ea>             ; r = effective address  (pointer arithmetic!)
CLR  <ea> / CLRA / CLRB      ; zero
```

**ALU (8-bit on A/B, 16-bit on D)**
```
ADD/ADC/SUB/SBC  {A,B} ,<ea> ; +, +carry, -, -borrow
ADDD/SUBD        <ea>        ; 16-bit add/sub into D (pointer/int math)
AND/OR/EOR/BIT   {A,B},<ea>
CMP{A,B,D,X,Y}   <ea>        ; compare (sets flags, no writeback)
INC/DEC/NEG/COM  <ea>        ; read-modify-write
ASL/LSR/ASR/ROL/ROR <ea>     ; shifts/rotates
TST <ea>                     ; set N,Z from operand
```

**Stack & frames**
```
PSHS/PULS {regset}           ; push/pull any register subset on the active stack
JSR <ea> / BSR rel           ; call (push return addr)
RTS                          ; return
```

**Control flow**
```
JMP <ea>
Bcc rel8 / LBcc rel16        ; cc in {RA,EQ,NE,CC,CS,PL,MI,GE,LT,GT,LE,HI,LS,VC,VS}
```

**System**
```
NOP
SWI / SWI2 / SWI3            ; software interrupt / syscall trap (-> supervisor)
RTI                          ; return from interrupt (restores mode per CC.E)
SEI / CLI                    ; set/clear IRQ mask            [privileged]
CWAI / SYNC                  ; wait-for-interrupt
TFR USP,r / TFR r,USP        ; kernel access to the user stack [privileged]
LDMMU / STMMU                ; read/write a page-table entry  [privileged] (§6)
```

> **Open — the full table.** The next deliverable is the complete primary +
> P2/P3 page enumeration with: assigned opcode bytes, exact addressing-mode
> availability per instruction, byte counts, microcycle/T-state counts, and the
> precise flag effects of each instruction. That is a focused design pass best
> done after §2 and §5 are confirmed (and a good candidate to generate and then
> adversarially check for encoding collisions and flag-effect consistency).

---

## 9. Open questions for this document

1. **Postbyte layout & prefix-page assignment (§5).**
2. **Mode/reset encoding (§2/§6):** exact `CC.M` mode-bit position and the
   reset-vector location.
3. **Then:** freeze the full 256-entry opcode table (§8).

*Decided so far:* registers `A B D X Y SP` (no `U`/`DP`); little-endian; privilege
with banked `SSP`/`USP`; internal MMU (physical external bus, 16 MB / 8 KB pages,
identity-mapped at reset, programmed by `LDMMU`/`STMMU`); calling convention (§7).
