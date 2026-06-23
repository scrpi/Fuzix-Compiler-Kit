# tools/fcc — BLIP ISA-level toolchain (Fuzix Compiler Kit)

The C compiler, assembler, linker, librarian and relocatable object format for
BLIP programs, built on the **Fuzix Compiler Kit** and **Fuzix-Bintools**. This
is the ISA-level toolchain (programs that run *on* BLIP); it is unrelated to the
microcode assembler in `tools/uasm/`.

> Status: the **assembler** is fully retargeted and assembles the entire
> `isa/opcodes.toml` instruction set correctly. The **C compiler** is at a
> bring-up milestone: `cc1.blip`/`cc2.blip` compile real C to BLIP assembly that
> the assembler accepts end to end; native arithmetic, the §7 register-argument
> ABI, and a support/runtime library are the next steps (see "C compiler
> status"). Tracked by the plan in `docs/plans/fck-toolchain.md` (non-normative).

## Layout

```
tools/fcc/
  bintools/      submodule: Fuzix-Bintools (assembler/linker), pinned pristine
  compiler-kit/  submodule: Fuzix-Compiler-Kit (cc0/cc1/cc2), pinned pristine
  patches/
    bintools/      the BLIP assembler port, applied onto bintools at build time
    compiler-kit/  the BLIP compiler port, applied onto compiler-kit at build time
  build.sh       apply patches + build the whole toolchain into bin/
  test/          assembler round-trip + full opcode test
  bin/           build output (gitignored): cc, cc0, cc1.blip, cc2.blip,
                 asblip, ldblip, nmblip, osizeblip, dumprelocsblip
```

## Submodules + patches (why no forks)

Both submodules are pinned to pristine upstream commits. The BLIP-specific
changes live as patches under `patches/<submodule>/` and are applied into each
submodule by `build.sh`. We deliberately **do not maintain forks carrying our
changes**: pinning a commit + patching on top keeps the BLIP port reviewable in
this repo, lets us rebase onto a newer upstream by re-pinning and refreshing the
patch, and avoids extra repositories to publish to.

The pinned mirrors are `https://github.com/scrpi/Fuzix-Bintools.git` and
`https://github.com/scrpi/Fuzix-Compiler-Kit.git` (public mirrors of the
canonical Codeberg upstreams, which aren't reachable from the build environment).

## Build

```sh
git submodule update --init tools/fcc/bintools tools/fcc/compiler-kit
sh tools/fcc/build.sh                 # -> tools/fcc/bin/ (compiler + assembler)
sh tools/fcc/test/roundtrip.sh        # assembler byte-level smoke test
python3 tools/fcc/test/opcodes_test.py # every opcode vs isa/opcodes.toml
```

`build.sh` applies `patches/<submodule>/*.patch` (if not already staged),
regenerates `blip-optab.h` from `isa/opcodes.toml`, then builds both toolchains.

Compiling a C file (the `cc` driver expects tools installed under `/opt/fcc`; to
run the stages from `bin/` directly, note they `lseek`+`read` on **stdout**, so
redirect with `1<>file`, not `>file`):

```sh
cc0 sym 1<>x.at  <x.c       # tokenize
cc1.blip 9000 0  1<>x.hash <x.at    # parse  (9000 = BLIP cpucode)
cc2.blip sym 9000 0 0 1<>x.s <x.hash # generate BLIP asm
asblip x.s                  # assemble -> x.o
```

## What the assembler port adds (patches/bintools/0001-blip-target.patch)

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

## What the compiler port adds (patches/compiler-kit/0001-blip-compiler.patch)

- `cc.c`: a `blip` row in the driver's CPU table (set `blip`, cpudot `.blip`,
  cpucode `9000`, `has_reloc=0` since bintools has no `relocblip`).
- `target-blip.c`: the cc1 (front-end) target — type sizes (char 1, int 2,
  long 4, ptr 2; little-endian), no alignment, byte args as bytes. Register
  variables are disabled for now.
- `backend-blip.c`: the cc2 code generator, derived from `backend-default.c`
  (BLIP is little-endian, the kit default). The working value lives in `D`
  (16-bit/pointer) or `B` (8-bit). Native: segments, the `LEA SP` stack frame,
  `RTS` with the §7 return register (`LD X,D` for value returns), `JMP`/`LBEQ`/
  `LBNE` branches, little-endian data, and constant loads. Arithmetic, loads and
  stores currently fall back to helper calls (`JSR __op`).
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

Bring-up milestone (verified by adversarial review). `cc1.blip`/`cc2.blip`
compile real C — functions, locals, `while`/`if`/`return`, constants, globals —
to BLIP assembly that `asblip` assembles end to end. Argument offsets
(`frame_len + ARGBASE`), the §7 16-bit-return-in-`X`, little-endian data, the
`(SP+n)` frame, and `sp` accounting are all correct.

Still to do (in rough order):

- **A BLIP support/runtime library** (`__plus`, `__deref`, `__bool`, `__cc*`,
  mul/div, long/float, `crt0`, …) honoring the helper ABI above. Until it
  exists, compiler output assembles but does not link.
- **Native arithmetic / loads / stores** in `gen_node`/`gen_rewrite_node` to
  replace the helper calls (the `T_NREF`/`T_LREF`/… fusions the 6809 backend
  uses), exploiting `(X+n)`/`(SP+n)`/auto-inc addressing.
- **The §7 register-argument ABI**: leading scalar args in `B`/`X`. The backend
  currently passes *all* args on the stack — self-consistent for compiler-built
  code, but not yet the documented ABI for interop with hand-written assembly.
- Register variables (hand `Y` out in `target-blip.c`), and 32-bit
  (`long`/`float`) returns via the §7 hidden pointer.

## License / provenance

Upstream Fuzix-Bintools (per its `LICENCE`): the assembler updates are 3-clause
BSD; the other tools (linker, librarian, …) are GPL. The Fuzix Compiler Kit is
GPL. Both submodules carry their licences in-tree. This is an isolated build tool
under `tools/`; it does not touch BLIP hardware or microcode.
