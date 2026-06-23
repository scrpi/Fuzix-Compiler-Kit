# tools/fcc — BLIP ISA-level toolchain (Fuzix Compiler Kit)

The C compiler, assembler, linker, librarian and relocatable object format for
BLIP programs, built on the **Fuzix Compiler Kit** and **Fuzix-Bintools**. This
is the ISA-level toolchain (programs that run *on* BLIP); it is unrelated to the
microcode assembler in `tools/uasm/`.

> Status: the **assembler** is fully retargeted and assembles the entire
> `isa/opcodes.toml` instruction set correctly. The **C compiler** compiles real
> C — native arithmetic/loads/stores, compound assignment, 32-bit `long`, a
> `switch` helper, plus a support/runtime library (`libblip.a` + `crt0`) —
> through `cc1.blip`/`cc2.blip`/`asblip`/`ldblip` into images that **link and
> run** under the `emublip` emulator (the `ctests`/`lib_*` suites pass end to
> end). The backend is §7-conformant across the ABI: all arguments on the stack
> (D-51), and returns in `B` (8-bit) / `X` (16-bit) / the `D:Y` pair (32-bit, D-52),
> with no by-value aggregate return — no outstanding §7 gap (see "C compiler
> status"). Tracked by the plan in `docs/plans/fck-toolchain.md` (non-normative).

## Layout

```
tools/fcc/
  bintools/      submodule: Fuzix-Bintools (assembler/linker), tracks the 'blip' branch
  compiler-kit/  submodule: Fuzix-Compiler-Kit (cc0/cc1/cc2), tracks the 'blip' branch
  build.sh       build the whole toolchain into bin/
  test/          assembler round-trip + full opcode test
  bin/           build output (gitignored): cc, cc0, cc1.blip, cc2.blip,
                 asblip, ldblip, nmblip, osizeblip, dumprelocsblip
```

## Submodules (the `blip` branch)

Each submodule is one of our forks, and the BLIP port lives on a **`blip`
branch** of that fork (`.gitmodules` sets `branch = blip`; the superproject pins
a specific commit on it). The forks are:

- `git@github.com:scrpi/Fuzix-Bintools.git`
- `git@github.com:scrpi/Fuzix-Compiler-Kit.git`

(forks of the canonical Codeberg upstreams, which aren't reachable from the
build environment). Keeping the changes on a branch — rather than as patches
applied at build time — means the submodule checkout is the real source, builds
standalone, and the port can be rebased onto upstream `main` and offered back as
an ordinary PR. The clone URL is SSH because the forks aren't anonymously
cloneable (an anonymous https fetch 404s, so `git submodule update` would
otherwise stall on a credential prompt); a checkout — and pushing the `blip`
branch — authenticates with the maintainer's SSH key.

Each toolchain builds *in-tree* (the kit's Makefiles compile next to their
sources), so a build leaves untracked executables (`cc1.blip`, `asblip`, …) in
the submodule working trees. These are never committed — `*.o`/`*.a` are already
ignored, matching upstream, and the final binaries are left untracked as upstream
does. The superproject sets `ignore = untracked` on both submodules so those
build artifacts don't show it as dirty (while real edits to tracked submodule
files still do); add the binary names to each submodule's `.git/info/exclude` to
quiet its own `git status` locally.

To advance the pinned commit after new work lands on a fork's `blip` branch:
`git submodule update --remote tools/fcc/<sub>` then commit the superproject.

## Build

```sh
git submodule update --init tools/fcc/bintools tools/fcc/compiler-kit
sh tools/fcc/build.sh                 # -> tools/fcc/bin/ (compiler + assembler)
sh tools/fcc/test/roundtrip.sh        # assembler byte-level smoke test
python3 tools/fcc/test/opcodes_test.py # every opcode vs isa/opcodes.toml
```

`build.sh` regenerates `blip-optab.h` from `isa/opcodes.toml` (the one generated
artifact — the assembler's opcode table, kept in lockstep with the ratified
opcode map), then builds both toolchains. No patching step.

Compiling a C file (the `cc` driver expects tools installed under `/opt/fcc`; to
run the stages from `bin/` directly, note they `lseek`+`read` on **stdout**, so
redirect with `1<>file`, not `>file`):

```sh
cc0 sym 1<>x.at  <x.c       # tokenize
cc1.blip 9000 0  1<>x.hash <x.at    # parse  (9000 = BLIP cpucode)
cc2.blip sym 9000 0 0 1<>x.s <x.hash # generate BLIP asm
asblip x.s                  # assemble -> x.o
```

## What the assembler port adds (bintools `blip` branch)

- `obj.h`: a BLIP architecture id (`OA_BLIP`).
- `as.h`: a `TARGET_BLIP` config block — symbol-type codes, the §8.4 register
  codes, and little-endian byte order.
- `as6-blip.c`: the symbol table — directives plus the instruction verbs (each
  tagged `TINST`; no opcode baked in here).
- `as1-blip.c`: a **table-driven encoder**. It parses a line into a normalized
  key (verb + operand form, e.g. `LD A,(SP+n)`), looks it up in the generated
  `blip-optab.h`, and emits the `0x80` page-1 prefix + opcode byte + operand
  bytes (little-endian), choosing the 8- vs 16-bit offset form by range.
- `Makefile`: `asblip`/`ldblip`/`nmblip`/`osizeblip`/`dumprelocsblip` rules
  built with `-DTARGET_BLIP`.

`blip-optab.h` is **generated** from `isa/opcodes.toml` by
`tools/isa/gen_opcodes.py emit-asmtab` (build.sh runs it), so the assembler can
never drift from the ratified opcode map. The linker, librarian and relocatable
object format are inherited from upstream unchanged.

## What the compiler port adds (compiler-kit `blip` branch)

- `cc.c`: a `blip` row in the driver's CPU table (set `blip`, cpudot `.blip`,
  cpucode `9000`, `has_reloc=0` since bintools has no `relocblip`).
- `target-blip.c`: the cc1 (front-end) target — type sizes (char 1, int 2,
  long 4, ptr 2; little-endian), no alignment, byte args as bytes. Register
  variables are disabled for now.
- `backend-blip.c`: the cc2 code generator, derived from `backend-default.c`
  (BLIP is little-endian, the kit default). The working value lives in `D`
  (16-bit/pointer) or `B` (8-bit), with 32-bit `long` in the `D:Y` pair. Native:
  segments, the `LEA SP` stack frame, `RTS` with the §7 return register
  (`LD X,D`), `JMP`/`LBEQ`/`LBNE` branches, little-endian data and constant
  loads, the arithmetic/bitwise/compare/shift operators, loads and stores (fused
  onto `(X+n)`/`(SP+n)`/auto-inc addressing), compound assignment, and 32-bit
  `long`. Only `*`/`/`/`%`, variable-count shifts, long mul/div, and `switch`
  fall back to library helpers (`JSR __op`).
- `Makefile`: `cc1.blip` and `cc2.blip` rules.

### BLIP helper ABI (so conditional branches are correct)

The backend emits `LBEQ`/`LBNE` immediately after a condition, relying on the
N,Z flags. Native `LD`/`ALU` set them (isa.md §8.5), but the boolean/comparison
results come from helper calls — so the BLIP support library, when written,
**must make `__bool*`, `__not*` and the `__cc*` comparison helpers return with
N,Z set from their result word** (`LBEQ` = branch if Z = false; `LBNE` = true).
A helper that builds its result with a register move or `LEA` (which don't touch
flags, §8.5) would silently break every `if`/`while`. Any helper that uses `Y`
must save it (`Y` is the one callee-saved register, §7).

## Assembler status

Retargeted and verified: **all 462 instructions in `isa/opcodes.toml` assemble
to the correct opcode bytes and page-1 prefix** (`opcodes_test.py`), operands are
little-endian (§3), the register-move selector follows §8.4, and the `U`/`DP`
6809-isms are gone. Assemble→link round-trips through `ldblip` with relocations.

Still to do: confirm the **branch-offset base** against the sim (R-SIM-4); a
`PSHS`/`PULS` register-list syntax; wider operand diagnostics.

## C compiler status

`cc1.blip`/`cc2.blip` compile real C — functions, locals, `while`/`if`/`for`/
`switch`/`return`, constants, globals, pointers and arrays — to BLIP assembly
that `asblip` assembles, `ldblip` links against `libblip.a`, and `emublip` runs.
The `ctests/*.c` (native) and `lib_*.c` (library) suites pass end to end (run
`test/run-ctests.sh` and `test/run-libtest.sh`); each program asserts its own
results and exits 0. Argument offsets (`frame_len + ARGBASE`), the §7
16-bit-return-in-`X`, little-endian data, the `(SP+n)` frame, and `sp`
accounting are all correct.

Done since the bring-up milestone:

- **Native arithmetic / loads / stores** in `gen_node`/`gen_direct` — the
  arithmetic, bitwise, comparison and shift operators, loads and stores fused
  onto `(X+n)`/`(SP+n)`/auto-inc addressing, replacing the old helper calls.
- **Compound assignment** (`+=` … `>>=`) and complex `++`/`--` lowered natively.
- **32-bit `long`** in the `D:Y` pair — arithmetic with carry/borrow across the
  word boundary, signed/unsigned compare, casts, shifts, and `*`/`/`/`%` via the
  `__mull`/`__divl`/`__divul` helpers.
- **A support/runtime library** (`libblip.a` + `crt0`): the `__mul`/`__div`/
  `__rem`/shift/`switch` helpers honoring the helper ABI above. Compiler output
  now links **and runs**.
- **§7 argument passing**: all arguments on the stack, right-to-left, caller
  cleans up — this **is** the §7 convention as of **D-51** (the spec was aligned
  to the toolchain's uniform stack passing, superseding D-19's register-argument
  rule, rather than teaching the front end to pass leading args in `B`/`X`).
- **§7 return values**: 8-bit in `B`, 16-bit in `X`, 32-bit in the `D:Y` pair
  (**D-52** aligned the spec to the `D:Y` working pair, dropping D-19's
  hidden-pointer return; by-value `struct`/`union` return is unsupported, which the
  front end already enforces). The `long`-return round trip is covered by
  `lib_long.c`. No §7 ABI gap remains.

Still to do (non-ABI):
- Register variables (hand `Y` out in `target-blip.c`).
- Confirm the **branch-offset base** against the sim (R-SIM-4).

## License / provenance

Upstream Fuzix-Bintools (per its `LICENCE`): the assembler updates are 3-clause
BSD; the other tools (linker, librarian, …) are GPL. The Fuzix Compiler Kit is
GPL. Both submodules carry their licences in-tree. This is an isolated build tool
under `tools/`; it does not touch BLIP hardware or microcode.
