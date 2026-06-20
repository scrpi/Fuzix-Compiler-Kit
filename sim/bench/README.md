# Engine benchmark

The first executable step of the simulation-first build (D-10), and the
"benchmark a representative slice" action from [toolchain.md](../../docs/toolchain.md)
§10. It measures the throughput of the **two engines** on the same gate-level
netlist, to replace the §5.3 speed *estimates* with real numbers:

- **Verilator** (zero-delay, compiled) → the functional-regression rate. Target
  ≥ 1 MHz simulated; expected to clear it by a wide margin.
- **Icarus** (`-gspecify`, timed) → the gate-level timed rate. Expected to be
  far slower per cycle (kHz, not MHz) — which is fine, because timing runs are
  bounded/one-shot, not long (toolchain.md §5.1–§5.3).

## What it simulates

`add_accum` (a *representative* slice, not real BLIP): an 8-bit registered
accumulator built structurally from the cell library — two `ttl_283` adders +
one `ttl_574` register, with the register→adder→register feedback as the timed
path. Cells live in [rtl/cells/](../../rtl/cells/).

> **Provisional timing.** The cell `specify` delays are representative
> 74AHCT/ACT placeholders, **not** yet datasheet-sourced (toolchain.md §10.3).
> The benchmark measures simulator *throughput*, not timing correctness.

## Running (WSL, repo cloned at ~/dev/blip)

```bash
bash sim/bench/run.sh
```

`run.sh` builds both engines (into `/tmp`, off the repo tree) and prints each
rate: Icarus = `N` (parameter in `tb_icarus.v`) ÷ wall-clock; Verilator prints
its own Mcyc/s.

## Status

First-draft scaffold — not yet run (the WSL toolchain install is the prerequisite).
Expect to fix bring-up issues on the first run (e.g. Verilator tri-state / specify
warnings); that iteration is the point of the benchmark.
