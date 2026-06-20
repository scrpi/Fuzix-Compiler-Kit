#!/usr/bin/env bash
# Engine benchmark runner: builds and runs the add_accum slice under both
# engines and reports throughput (toolchain.md §5.3). Run from anywhere:
#   bash sim/bench/run.sh
#
# Builds into /tmp (off the repo tree) so no artifacts land in git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CELLS=("$ROOT/rtl/cells/ttl_283.v" "$ROOT/rtl/cells/ttl_574.v")
SLICE="$ROOT/sim/bench/add_accum.v"
ICARUS_N=2000000          # must match parameter N in tb_icarus.v

echo "=== Icarus (timed gate-level, -gspecify) ==="
iverilog -g2012 -gspecify -o /tmp/tb_icarus \
    "$ROOT/sim/bench/tb_icarus.v" "$SLICE" "${CELLS[@]}"
t0=$(date +%s.%N)
vvp /tmp/tb_icarus
t1=$(date +%s.%N)
awk -v n="$ICARUS_N" -v a="$t0" -v b="$t1" \
    'BEGIN { d = b - a; printf "Icarus: %d cycles in %.3f s = %.4f Mcyc/s\n", n, d, n/d/1e6 }'

echo
echo "=== Verilator (zero-delay, compiled) ==="
verilator --cc --exe --build -j 0 -Wno-fatal --Mdir /tmp/vbench \
    --top-module add_accum \
    "${CELLS[@]}" "$SLICE" "$ROOT/sim/bench/bench_verilator.cpp" -o bench_verilator
/tmp/vbench/bench_verilator
