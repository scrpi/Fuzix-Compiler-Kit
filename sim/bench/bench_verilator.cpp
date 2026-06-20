// bench_verilator.cpp — Verilator harness for the engine benchmark (FAST run).
//
// Drives the SAME add_accum netlist as tb_icarus.v, but compiled by Verilator to
// C++ and run zero-delay (specify delays ignored). Toggles the clock for N cycles
// in a tight eval() loop and reports cycles/second — the functional-regression
// rate the test suite cares about (toolchain.md §4.2, §5.3; target >= 1 MHz, and
// Verilator should clear it by a wide margin).

#include "Vadd_accum.h"
#include "verilated.h"
#include <chrono>
#include <cstdio>

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);

    Vadd_accum* dut = new Vadd_accum{ctx};

    const long N = 20000000;          // clock cycles (10x Icarus; Verilator is far faster)
    dut->din  = 0x01;
    dut->oe_n = 0;
    dut->clk  = 0;
    dut->eval();

    auto t0 = std::chrono::steady_clock::now();
    for (long i = 0; i < N; ++i) {
        dut->clk = 1; dut->eval();
        dut->clk = 0; dut->eval();
    }
    auto t1 = std::chrono::steady_clock::now();

    double secs = std::chrono::duration<double>(t1 - t0).count();
    std::printf("VERILATOR done: %ld cycles in %.3f s = %.3f Mcyc/s, final acc=%u\n",
                N, secs, (secs > 0.0 ? N / secs / 1e6 : 0.0), (unsigned)dut->acc);

    delete dut;
    delete ctx;
    return 0;
}
