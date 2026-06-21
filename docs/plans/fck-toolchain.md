# PLAN — Adopt the Fuzix Compiler Kit; start the BLIP assembler

> **Status: TEMPORARY / NON-NORMATIVE planning document.** This is a working
> plan, not a tier-3 spec. It lives outside the three-tier justification chain
> ([AGENTS.md](../../AGENTS.md)) and **justifies nothing on its own**. When its
> decisions are ratified they move into [decision-log.md](../decision-log.md),
> [requirements.md](../requirements.md), and the specs ([isa.md](../isa.md),
> [toolchain.md](../toolchain.md), [goals.md](../goals.md)); this file is then
> deleted. Drafted 2026-06-21.
>
> **One-line summary:** replace the planned SDCC backend (D-06) with the **Fuzix
> Compiler Kit (FCK) + Fuzix-Bintools**, because it gives us a retargetable
> assembler, a relocating linker, and a relocatable object format for a bounded
> per-CPU cost — and is small enough to run on BLIP itself, so the OS can rebuild
> its own userland.

---

## 1. Why this plan exists

[D-06](../decision-log.md#d-06--toolchain-a-new-sdcc-backend) decided the C
toolchain would be a new **SDCC** backend cloned from STM8. New information: modern
FUZIX has moved off SDCC to the author's own **Fuzix Compiler Kit**, whose deciding
design property is that the whole chain is small enough to **self-host on the 8-bit
target under the OS**. That capability serves G3 ("a real computer") directly, and
the toolchain it brings answers the same requirements D-06 did (R-BUILD-1,
R-BUILD-2) at lower total build cost. This plan proposes superseding D-06.

This concerns the **ISA-level** toolchain (the assembler/linker/compiler for BLIP
programs). It does **not** touch the **microcode** toolchain — `tools/uasm/`,
R-BUILD-3 — which is unrelated and stays as is.

## 2. What FCK is (two repos)

The toolchain is split across two repositories; the assembler lives in the second.

- **Fuzix-Compiler-Kit** — the C compiler only. Pipeline:
  `cpp` → **cc0** (tokenize; identifiers become 16-bit tokens) → **cc1**
  (recursive-descent parser → expression trees) → **cc2** (a deliberately simple
  left-hand-walking code generator; the target rewrites subtrees). Per-CPU codegen
  is `backend-<cpu>.c` (+ `be-code-<cpu>.c` for the 680x family). In-tree docs:
  `Backend.md`, `TARGET.md`, `ABI.md`, `Operations.md`.
- **Fuzix-Bintools** — the **assembler, linker, librarian, and object format**.
  This is what we start with. Installs to `/opt/fcc/bin`; the compiler installs on
  top of it.

**Self-hosting is the design driver.** cc0/cc1/cc2 and the bintools are small C
programs intended to compile and run *on the target*; SDCC (a large host C++
program) cannot. This is the property motivating the pivot.

**BLIP is in FCK's sweet spot.** FCK is strongest on 680x/8080-class accumulator
machines; `be-code-6809.c` exists and the Bintools 6809 assembler is mature. BLIP's
addressing modes are already 6809-derived ([isa.md](../isa.md) §1.2, §4), so the
ISA work done so far fits FCK at least as well as it fit SDCC/STM8.

## 3. What we inherit from Bintools

The per-CPU surface is small; the expensive, reusable machinery is target-agnostic.

| Piece | Files | Per-CPU? |
|---|---|---|
| Shared multipass assembler core | `as0.c as2.c as3.c as4.c` | no |
| **Per-CPU encoder** — "assemble one line; knows all the dirt": operand/addressing-mode parsing, byte emission, reloc generation | **`as1-<cpu>.c`** (~875 lines for 6809) | **yes** |
| **Per-CPU symbol table** — every mnemonic, register name, pseudo-op (`sym[]`) | **`as6-<cpu>.c`** (~350 lines, mostly data) | **yes** |
| Linker, librarian, nm, size, reloc dumper | `ld.c reloc.c nm.c osize.c …` | no (per-target build only bakes in the arch id) |
| Object format | `obj.h` | one arch-id entry |

**A new CPU = two files** (`as1-blip.c`, `as6-blip.c`) + a one-line arch id in
`obj.h` + a Makefile rule (`-DTARGET_BLIP`). **The linker, relocatable object
format, and librarian come for free.** This is the hard, unglamorous majority of an
assembler/linker toolchain inherited at no per-CPU cost — the decisive technical
merit for R-BUILD-1/R-BUILD-2.

**Object format (`obj.h`) fits BLIP cleanly:** 16-bit magic `0x3D1A`; an endianness
flag set **little-endian** ([isa.md](../isa.md) §3); byte-addressed (no
word-addressing flag); 14 segments (CODE/DATA/BSS/ZP/COMMON/LITERAL/DISCARD — ZP
left unused, we dropped `DP`); relocations (escape `0xDA` + type/size) covering
16-bit absolute, 8-bit, PC-relative, and high/low-byte — the exact set BLIP
pointers, branches, and 16-bit-constant builds need. Only central change: **add a
BLIP arch id.**

**Clone base: `as1-6809.c` / `as6-6809.c`** — BLIP's addressing modes are
6809-derived, so the 6809 encoder is the closest start (the assembler-side analogue
of "clone STM8").

## 4. Repo setup

Treat the BLIP target as a real upstream-style CPU port.

```
tools/fcc/
  bintools/        ← submodule: our fork of Fuzix-Bintools, with as1-blip.c,
                     as6-blip.c, the obj.h arch id, and the Makefile rule added
  compiler-kit/    ← (later) submodule fork with backend-blip.c / be-code-blip.c
  build.sh         ← builds asblip/ldblip/nmblip into tools/fcc/bin (CCROOT)
  test/            ← round-trip smoke tests (assemble → link → compare bytes)
```

- **Fork + submodule** (not a vendored copy): the BLIP target is a genuine new
  port, so it belongs in a fork we can rebase on upstream and submit back; the BLIP
  repo pins a submodule commit. Sits beside `tools/uasm/` (microcode, unrelated).
  *(Vendored-copy is the alternative if submodule friction isn't worth it — open
  decision, §6.)*
- **Verify the upstream license** before vendoring (FUZIX components are typically
  GPL). Fine for a build tool under `tools/`; it does not touch BLIP hardware or
  microcode (not a derivative work). Keep it isolated and note the license.

## 5. How we start with the assembler

**Blocker to name:** `as6-blip.c` *is* the mnemonic→opcode table, and BLIP's opcode
bytes are still unassigned ([D-41](../decision-log.md)). The table can't be filled
until the encoding is pinned — so **the assembler is the forcing function for
finalizing the opcode map.** Hence two phases:

1. **Now — a tiny Python flat-binary assembler** (sibling to `tools/uasm/`; flat
   `$readmemh` output; no linker). Hours of work, tolerant of opcodes still in
   flux. Unblocks ISA bring-up, the R-SIM-4 functional suite, and front-panel
   bootstrap snippets (R-DBG-3). Explicitly throwaway — **not** the production tool.
2. **Once opcodes land — the FCK Bintools target:**
   1. Build an existing target (`as6809`) in `tools/fcc/` to confirm the toolchain
      compiles in our environment.
   2. Copy `as1-6809.c`/`as6-6809.c` → `as1-blip.c`/`as6-blip.c`; add the `obj.h`
      arch id and the `-DTARGET_BLIP` Makefile rule.
   3. Strip 6809-isms BLIP lacks (the `U` stack, `DP`/direct page), retarget the
      addressing-mode encoders to [isa.md](../isa.md) §4, rewrite `sym[]` to BLIP's
      opcode map. Reuse the relocation machinery unchanged.
   4. **Round-trip test wired into the sim:** assemble known BLIP asm → object →
      `ldblip` → compare emitted bytes against the values the functional suite
      already runs (R-SIM-4). Assembler and sim cross-check each other.
   5. *(Later)* `backend-blip.c` + `be-code-blip.c` in the Compiler-Kit, modeled on
      the 680x backend, emitting asm `asblip` consumes — guided by `Backend.md` /
      `TARGET.md`.

## 6. Open decisions to ratify

1. **Codegen quality vs. G2.** FCK's cc2 is a *simple* code generator: it trades
   peak optimization for portability and self-hosting. But **G2 ("code quality
   competitive with a 6809") ranks above G3 in the priority list**, and self-hosting
   serves G3. If FCK output is materially below the 6809 bar, the ordering says G2
   wins. Proposed resolution: adopt FCK (BLIP is in its sweet spot) but
   **re-validate the G2 success test empirically against FCK output**, and keep
   SDCC/GCC documented as the max-optimization alternative. **Decision needed:** is
   FCK's codegen acceptable against G2, or is G2 a hard gate that FCK must clear
   first?
2. **Self-hosting as a requirement.** R-BUILD-1 says "build the kernel and userland"
   — not "natively, on the target." If we want to bank native self-hosting, promote
   it to a requirement (proposed **R-BUILD-4 ⟸ G3**: *the C toolchain shall be able
   to run on BLIP under the OS and rebuild its own userland*) so specs can cite it.
   "Modern FUZIX dropped SDCC for FCK" is an **Influence**, not a justification.
3. **Vendoring mechanism.** Fork + submodule (recommended) vs. plain vendored copy
   under `tools/`.

## 7. Documentation ripple (promotion path once ratified)

| Action | Where | Note |
|---|---|---|
| New decision **D-44**: adopt FCK + Bintools; **supersedes D-06** | [decision-log.md](../decision-log.md) | Reason = R-BUILD-1/-2 + inherited-linker/object-format merit; FUZIX-dropped-SDCC goes in *Influences* |
| Add **R-BUILD-4** (self-hosting), if §6.2 accepted | [requirements.md](../requirements.md) | `⟸ G3`; update goal→requirement table |
| Rewrite §1.3 "a new SDCC backend (STM8-derived)" → FCK | [isa.md](../isa.md) | Re-anchor the §3 byte-order note and the register-shape rationale on requirement IDs (they get *stronger*, not weaker, under FCK) |
| Fill the ISA-level toolchain gap (currently only the microcode assembler) | [toolchain.md](../toolchain.md) | Bintools assembler + linker + object format; the two-phase start plan |
| Update non-goal/"done" wording that names SDCC | [goals.md](../goals.md) | "(plan: SDCC)" → FCK; optionally fold self-hosting into G3's "real computer" |

## 8. Status & next actions

- [ ] Ratify §6 decisions (codegen-vs-G2; self-hosting requirement; vendoring).
- [ ] **Ratify the instruction set / pin the opcode map (D-41)** — the immediate
      next activity, and the precondition for `as6-blip.c`.
- [ ] Write D-44 (supersede D-06) + R-BUILD-4; rewrite isa.md §1.3; fill
      toolchain.md; update goals.md.
- [ ] Scaffold `tools/fcc/` + the Python bring-up assembler.

## Influences / prior art (non-normative — justifies nothing)

- Modern **FUZIX** replaced its SDCC dependency with the **Fuzix Compiler Kit** to
  gain native self-hosting on 8-bit targets. *Availability/maturity fact, not a
  reason for any BLIP spec.*
- **Fuzix-Compiler-Kit:** <https://github.com/EtchedPixels/Fuzix-Compiler-Kit>
  (canonical: <https://codeberg.org/EtchedPixels/Fuzix-Compiler-Kit>).
- **Fuzix-Bintools:** <https://github.com/EtchedPixels/Fuzix-Bintools>
  (canonical: <https://codeberg.org/EtchedPixels/Fuzix-Bintools>).
- The FCK 6809/680x port is the clone base for the BLIP assembler target and, later,
  the compiler backend.
