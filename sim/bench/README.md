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
accumulator built structurally from the cell library — two `sn74f283` adders +
one `sn74ahct574` register, with the register→adder→register feedback as the timed
path. Cells live in [hdl/cells/](../../hdl/cells/).

> **Mixed timing.** The `sn74f283` adder carries datasheet-sourced `specify`
> delays (SN74F283); the `sn74ahct574` register delay is still a placeholder, not
> yet datasheet-sourced (toolchain.md §10.3). Either way the benchmark measures
> simulator *throughput*, not timing correctness.

## Running (WSL, repo cloned at ~/dev/blip)

```bash
bash sim/bench/run.sh
```

`run.sh` builds both engines (into `/tmp`, off the repo tree) and prints each
rate: Icarus = `N` (parameter in `tb_icarus.v`) ÷ wall-clock; Verilator prints
its own Mcyc/s.

## Results (first run, 2026-06-20)

3-cell slice (two `sn74f283` + one `sn74ahct574`), WSL Ubuntu-24.04, Verilator 5.020 / Icarus 12:

| Engine | Rate | Sanity |
|--------|------|--------|
| Verilator (zero-delay) | **~15.9 Mcyc/s** | `acc=0` ✓ (2e7 mod 256) |
| Icarus (timed, `-gspecify`) | **~1.2 Mcyc/s** | `acc=128` ✓ (2e6 mod 256) |

Confirms the two-engine strategy: Verilator clears the ≥1 MHz functional target by
~16× and is ~13× faster than Icarus even on this tiny slice (the gap widens with
design size). These are **3-cell** numbers — whole-CPU rates differ (Verilator stays
fast; timed Icarus drops sharply, reinforcing that timing runs stay bounded,
toolchain.md §5.1).

Caveats: the flop clk→Q is modeled with an intra-assignment `#` delay (Icarus honors
it; Verilator ignores it via `--no-timing`) rather than `specify` — sequential-cell
timing methodology is open (toolchain.md §10.3/§10.4). Cell delay values are
provisional (§10.3).
