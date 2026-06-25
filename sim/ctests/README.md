# sim/ctests — real C programs on the gate-level CPU

Compile a C program with the BLIP C toolchain ([tools/fcc](../../tools/fcc)), run it on the
**gate-level Verilog CPU**, and check its output and exit status against the **emublip** software
emulator (the reference oracle). The *same* linked image runs on both, so any divergence is a real
gate-level/microcode bug.

This is the ISA-level program path (programs that run *on* BLIP). It is unrelated to the microcode
benches in `sim/tb/` (which test the CPU's own datapath) and to the microcode assembler in
`tools/uasm/`.

## How it works

```
fib.c ──cpp/cc0/cc1.blip/cc2.blip──▶ fib.s ──asblip──▶ fib.o ──ldblip -b -C0──▶ fib.bin
                                                                                   │
                          (raw flat binary, linked at 0, entered at PC=0)          │
                                                                                   ▼
   emublip fib.bin ───────────────▶ stdout + exit   (ORACLE)              bin2hex.py
        │                                                                          │
        └──────────────── compare ◀── stdout + [EXIT] ◀── vvp tb_csim +PROG=fib.hex
```

- **Boot** — the CPU boots the real microcode image (`make image`) into its control store via the
  `FILE` parameter, exactly as the `prog` bench does.
- **Load** — the program image is `$readmemh`'d into the testbench's 64 KB memory at address 0; the
  CPU resets to PC=0 (crt0), which sets `SP=$FEFF` and `JSR _main`.
- **I/O / exit** — [tb_csim.v](tb_csim.v) decodes the same magic I/O page the C runtime
  (`crt0`/`libblip`) and emublip use, so the image is unchanged between the two:
  `0xFF00`/`0xFF01` print a signed int, `0xFF02` is putchar, `0xFF03` is exit. Program stdout is
  written to the `+OUT` file; the exit code is logged as `[EXIT] n`.
- **Check** — [run.sh](run.sh) diffs the gate sim's stdout + exit against emublip's, byte for byte.

## Run

```
make ctests                      # every sim/ctests/*.c
bash sim/ctests/run.sh ret.c     # one program
```

A program writes output with the runtime helper `printint(int)` (signed decimal + newline) and
ends by returning from `main` (the low byte of the return is the exit status).

## Status

The bridge is complete and works: `ret.c` compiles, runs on emublip, loads into the gate sim,
boots, and the gate CPU executes compiled C from memory (`LD SP`, `JSR _main`, and into `main`).

**Known gate-microcode gap:** execution currently hangs on **`RTS` (opcode `0xC3`)** — the
subroutine return. `JSR` reaches the callee, but the return path does not complete, so no non-trivial
C program finishes yet. This matches the earlier finding that `JSR`/`RTS`, stack ops, and 16-bit
addressing are microcoded but were never exercised end-to-end from memory. Fixing the `RTS`
microroutine (and then re-running `ret.c` → `fib.c`) is the next step; until then `ctests` is kept
out of `make test`.
