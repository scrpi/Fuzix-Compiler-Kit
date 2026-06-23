# tools/fcc — BLIP ISA-level toolchain (Fuzix-Bintools)

The assembler, linker, librarian and relocatable object format for BLIP
programs, built on the **Fuzix-Bintools**. This is the ISA-level toolchain
(programs that run *on* BLIP); it is unrelated to the microcode assembler in
`tools/uasm/`.

> Status: bring-up. This tree sets up the toolchain and a BLIP assembler
> *target wiring*. The target currently carries a faithful 6809 clone as its
> starting point; the real ISA retarget is in progress (see "BLIP target
> status"). Tracked by the plan in `docs/plans/fck-toolchain.md` (non-normative).

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
sh tools/fcc/build.sh        # -> tools/fcc/bin/{asblip,ldblip,nmblip,...}
sh tools/fcc/test/roundtrip.sh
```

`build.sh` applies `patches/*.patch` into the submodule only if the target isn't
already staged, then runs the per-target Makefile rules.

## What the BLIP port adds (patches/0001-blip-target.patch)

- `obj.h`: a BLIP architecture id (`OA_BLIP`).
- `as.h`: a `TARGET_BLIP` config block.
- `as1-blip.c` / `as6-blip.c`: the per-CPU encoder and symbol/mnemonic table,
  cloned from the 6809 target (BLIP's addressing modes are 6809-derived).
- `Makefile`: `asblip`/`ldblip`/`nmblip`/`osizeblip`/`dumprelocsblip` rules
  built with `-DTARGET_BLIP`.

The linker, librarian and relocatable object format are inherited unchanged.

## BLIP target status

The initial patch is a **6809 clone** that builds and round-trips, to validate
the target wiring end to end. Still to do, retargeting to `docs/isa.md` §4 and
`isa/opcodes.toml`:

- byte order → little-endian (drop `TARGET_BIGENDIAN`, clear `ARCH_FLAGS`);
- rewrite the `sym[]` mnemonic→opcode table to BLIP's opcode map;
- drop 6809-isms BLIP lacks (the `U` stack, the `DP` direct page);
- retarget the addressing-mode encoders to BLIP's modes;
- cross-check emitted bytes against the simulator's functional suite.

## License / provenance

Upstream Fuzix-Bintools (per its `LICENCE`): the assembler updates are under a
3-clause BSD licence; the other tools (linker, librarian, etc.) are under the
GPL. The submodule carries that licence in-tree. This is an isolated build tool
under `tools/`; it does not touch BLIP hardware or microcode.
