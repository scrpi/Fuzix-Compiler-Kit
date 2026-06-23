# tools/fcc — BLIP ISA-level toolchain (Fuzix-Bintools)

The assembler, linker, librarian and relocatable object format for BLIP
programs, built on the **Fuzix-Bintools**. This is the ISA-level toolchain
(programs that run *on* BLIP); it is unrelated to the microcode assembler in
`tools/uasm/`.

> Status: the assembler is retargeted to BLIP and assembles the full
> `isa/opcodes.toml` instruction set correctly (see "BLIP target status"). The
> compiler backend is future work. Tracked by the plan in
> `docs/plans/fck-toolchain.md` (non-normative).

## Layout

```
tools/fcc/
  bintools/   submodule: Fuzix-Bintools, pinned to a fixed upstream commit (pristine)
  patches/    the BLIP port, applied onto the submodule at build time
  build.sh    apply patches + build asblip/ldblip/nmblip/... into bin/
  test/       round-trip smoke test
  bin/        build output (gitignored)
```

## Submodule + patches (why no fork)

`bintools/` is pinned to a pristine upstream commit. The BLIP-specific changes
live as patches under `patches/` and are applied into the submodule by
`build.sh`. We deliberately **do not maintain a Bintools fork carrying our
changes**: pinning a commit + patching on top keeps the BLIP port reviewable in
this repo, lets us rebase onto a newer upstream by re-pinning and refreshing the
patch, and avoids a second repository to publish to.

The pinned mirror is `https://github.com/scrpi/Fuzix-Bintools.git` (a public
mirror of the canonical Codeberg upstream, which isn't reachable from the build
environment).

## Build

```sh
git submodule update --init tools/fcc/bintools
sh tools/fcc/build.sh                 # -> tools/fcc/bin/{asblip,ldblip,nmblip,...}
sh tools/fcc/test/roundtrip.sh        # byte-level smoke test
python3 tools/fcc/test/opcodes_test.py # every opcode vs isa/opcodes.toml
```

`build.sh` applies `patches/*.patch` into the submodule (if not already staged),
regenerates `blip-optab.h` from `isa/opcodes.toml`, then runs the per-target
Makefile rules.

## What the BLIP port adds (patches/0001-blip-target.patch)

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

## BLIP target status

The assembler is retargeted to BLIP and verified: **all 462 instructions in
`isa/opcodes.toml` assemble to the correct opcode bytes and page-1 prefix**
(`opcodes_test.py`), operands are emitted little-endian (isa.md §3), the
register-move selector follows §8.4, and the `U`/`DP` 6809-isms are gone.
Assemble→link round-trips through `ldblip` with relocations.

Still to do:

- **Branch-offset base** is encoded relative to the end of the branch
  instruction; confirm this matches the microcode's PC semantics against the
  simulator's functional suite (R-SIM-4).
- **`PSHS`/`PULS`** take a bare mask byte (`PSHS $3F`); a register-list syntax
  (`PSHS A,B,X`) could be added.
- Wider operand diagnostics (e.g. immediate-too-large messages per operand).
- The compiler backend (`backend-blip.c`) in the Compiler-Kit, later.

## License / provenance

Upstream Fuzix-Bintools (per its `LICENCE`): the assembler updates are under a
3-clause BSD licence; the other tools (linker, librarian, etc.) are under the
GPL. The submodule carries that licence in-tree. This is an isolated build tool
under `tools/`; it does not touch BLIP hardware or microcode.
