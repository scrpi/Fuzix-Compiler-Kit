# supportblip — BLIP C support/runtime library

The runtime helper routines the BLIP C backend (`backend-blip.c`) emits
`JSR __op` for, archived into `libblip.a`, plus a `crt0`. This bring-up set
covers the common integer "hard ops" — multiply, divide, remainder and switch
dispatch — so C using `*`, `/`, `%` and `switch` links and runs on the BLIP
emulator. (32-bit `long` and floating-point helpers are a documented follow-on
and are intentionally out of scope here.)

## Calling convention (discovered from backend-blip.c + the emitted .s)

Two distinct conventions, both verified by compiling sample C and reading the
assembly:

### Binary ops (`__mul`, `__div`, `__divu`, `__rem`, `__remu`)
The backend emits, for `a OP b`:

    LD D,(SP+2)        ; LHS
    PSHS $06           ; push LHS (D = A:B) -> at (SP+2) above the return addr
    LD D,<rhs>         ; RHS in the working register D
    JSR __op           ; no caller cleanup follows

So on entry: **LHS is on the stack at `(SP+2)`** (above the 2-byte JSR return
address at `(SP)`), **RHS is in `D`**, the **result is returned in `D`**, and the
**helper pops its own LHS + return address** (there is no caller `LEA SP`). The
return tail is:

    LD X,(SP)          ; X = return address
    LEA SP,SP+4        ; drop return(2) + LHS(2)
    ADD D,$0000        ; set N,Z from the 16-bit result
    JMP X

`ADD D,$0000` re-establishes N,Z over the full 16-bit word (BLIP has no `TST D`;
register moves and `LEA` do not set N,Z — isa.md §8.5), keeping the helper safe
for an immediately following conditional branch.

### Switch (`__switch`, `__switchc`)
The backend emits the table pointer as **inline data after the call**:

    LD D,<value>       ; int switch value in D   (char value in B for __switchc)
    JSR __switch
    .word Sw<n>        ; inline pointer to the jump table

The table `Sw<n>` (from `gen_switchdata`/`gen_case_data`) is:

    .word count                       ; number of case entries
    .word value0  .word target0       ; int form: 2-byte value, 2-byte target
    ...                               ; (__switchc: .byte value, .word target)
    .word default                     ; default target (always present)

The helper reads the JSR return address (which points at `.word Sw<n>`), loads
the table base from it, then **drops that return word** (`LEA SP,SP+2`) because
it transfers control straight into the case body — the case body ends in `RTS`,
which must pop the *function's* own return address, not the switch table
pointer. It then linearly scans the table and `JMP`s to the matching target, or
to `default`.

## Helpers implemented

| Symbol | Op | Algorithm / notes |
|--------|----|-------------------|
| `__mul` | 16x16 -> 16 | Composes the 8x8 hardware `MUL` (D = A*B): `result = Llo*Rlo + ((Lhi*Rlo + Llo*Rhi) & 0xFF) << 8`. The two cross terms contribute only their low byte to the result's high byte (bits above 15 are discarded for a 16-bit product). N,Z from result. |
| `div16x16` | unsigned core | Classic restoring shift/subtract, 16 iterations: shift the (work:dividend) pair left one bit (carry chains dividend bit15 -> work bit0 via `ASL B`/`ROL A`/`XCHG D,X`/`ROL B`/`ROL A`), tentatively set the quotient bit, `SUB D` the divisor, and on borrow add it back and clear the bit. Returns X = quotient, D = remainder. Internal (not a backend symbol). |
| `__divu` / `__remu` | unsigned / , % | Load dividend from `(SP+2)` into X, divisor stays in D, call `div16x16`; `__divu` returns the quotient (X->D), `__remu` the remainder (already in D). |
| `__div` / `__rem` | signed / , % | Take \|dividend\|/\|divisor\| via `div16x16`, then fix the sign: quotient sign = sign(L) XOR sign(R); remainder sign = sign(L) (C99 truncation toward zero). Sign parity is tracked in `Y`, which is saved/restored (`Y` is the one callee-saved register, §7). |
| `__switch` / `__switchc` | int / char switch | Walk the inline table (see above); `JMP` to the matching or default target. `Y` is used as the loop counter and not preserved — the helper never returns (control leaves through the case body). |

All set N,Z from their result where they return a value (the comparison/bool
helpers that the README's N,Z invariant targets are not in this bring-up set).

## crt0

`crt0.s` mirrors `tools/fcc/test/testcrt0_blip.s`: set `SP = $FEFF` (just below
the I/O page), `JSR _main`, then exit with the low byte of main's 16-bit return
value (returned in `X` per §7) through the emulator exit port `$FF03`. The
acceptance harness links `testcrt0_blip.o` explicitly, so `libblip.a` itself
contains only the helpers; `crt0.o` is built for standalone use and is *not* put
in the archive (it is named on the link line, like `testcrt0_blip.o`).

## Division by zero (decision)

**Defined, non-trapping.** `div16x16` performs no zero check: with divisor 0 the
restoring subtract never borrows, so every quotient bit is set. The result is
**quotient = 0xFFFF, remainder = dividend** (and the signed wrappers then apply
their sign fix-up to those). This is cheap (no per-call test in the hot path) and
deterministic; a trapping variant can be added later if a requirement calls for
it. Verified on the emulator.

## Building the archive

`build.sh` assembles each `.s` with the kit's own `asblip` and archives the
objects with the system `ar` (Unix `ar` format `!<arch>\n`, which `ldblip`
reads — see `bintools/ar.h`). Member order matters for the one-pass linker: a
member is only pulled when it resolves an already-undefined symbol, so a member
that *defines* a symbol must come *after* the members that reference it.
`divide.o` (which defines `div16x16`) is therefore placed **last**, after
`__div.o`/`__divu.o`.

    sh build.sh        # -> libblip.a and crt0.o

## Linking

Object(s) first, library last:

    ldblip -b -C0 testcrt0_blip.o prog.o -o prog.bin libblip.a

## Acceptance tests (run on emublip, all exit 0)

In `tools/fcc/test/`: `lib_mul.c`, `lib_div.c`, `lib_switch.c`, `lib_mix.c`,
driven by `run-libtest.sh`. Each is self-checking (returns 0 on success, else
the index of the first failing check). They cover 16-bit multiply (including
both partial products and high-bit truncation), signed/unsigned divide and
remainder (including negative operands and large unsigned values), int and char
switch with several cases plus default, and mixed expressions like
`(a*b)/c % d`.
