#!/usr/bin/env bash
# Compile real C programs with the BLIP C toolchain (tools/fcc), run each on the gate-level Verilog
# CPU, and check the result against the emublip software emulator (the reference oracle): the SAME
# linked image runs on both, and we diff program stdout + exit status. With no args, runs every
# sim/ctests/*.c. Artifacts -> /tmp/blip_ctests.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$ROOT/sim/ctests"
FCC="$ROOT/tools/fcc"; BIN="$FCC/bin"; TEST="$FCC/test"
SUPPORT="$FCC/compiler-kit/supportblip"
CRT0="$TEST/testcrt0_blip.o"; LIB="$SUPPORT/libblip.a"
OUT=/tmp/blip_ctests; mkdir -p "$OUT"

# --- 1. build the C toolchain + emulator/crt0 + support library (once) ------------------------
[ -x "$BIN/cc2.blip" ] || sh "$FCC/build.sh" >/dev/null
{ [ -x "$TEST/emublip" ] && [ -f "$CRT0" ]; } || sh "$TEST/run-testblip.sh" build >/dev/null
[ -f "$LIB" ] || ( cd "$SUPPORT" && sh build.sh >/dev/null )

# --- 2. assemble the microcode image the CPU boots into its control store ----------------------
python3 "$ROOT/tools/uasm/uasm.py" >/dev/null
IMG="$ROOT/microcode/build/blip_microcode.hex"

# --- 3. build the gate-level sim harness once --------------------------------------------------
iverilog -g2012 -gspecify -D IMG="\"$IMG\"" -o "$OUT/tb_csim" \
    "$ROOT"/hdl/cells/*.v "$ROOT/hdl/boot/uc_loader.v" \
    "$ROOT/hdl/microsequencer.v" "$ROOT/hdl/trap_encoder.v" "$ROOT/hdl/bus_arbiter.v" \
    "$ROOT/hdl/microcode_store.v" "$ROOT/hdl/opcode_lut.v" "$ROOT/hdl/control_word_decoder.v" \
    "$ROOT/hdl/register16.v" "$ROOT/hdl/left_lane.v" "$ROOT/hdl/z_lane.v" \
    "$ROOT/hdl/sp_bank.v" "$ROOT/hdl/mmu_entry.v" "$ROOT/hdl/mmu.v" "$ROOT/hdl/uloop.v" \
    "$ROOT/hdl/memory_interface.v" \
    "$ROOT/hdl/alu_arithmetic.v" "$ROOT/hdl/alu_logic.v" "$ROOT/hdl/alu_shift.v" "$ROOT/hdl/alu.v" \
    "$ROOT/hdl/right_bus.v" "$ROOT/hdl/cc_conditions.v" "$ROOT/hdl/cc_register.v" "$ROOT/hdl/cc.v" \
    "$ROOT/hdl/cpu.v" "$CT/tb_csim.v"

# --- 4. per program: compile -> oracle (emublip) -> gate sim -> compare ------------------------
progs=("$@"); [ ${#progs[@]} -gt 0 ] || progs=("$CT"/*.c)
fail=0
for c in "${progs[@]}"; do
    name=$(basename "$c" .c); b="$OUT/$name"

    # compile + link (staged; output fds opened 1<> per the kit's lseek/read convention)
    "$BIN/cpp" "$c" "$b.i"                                    2>/dev/null
    "$BIN/cc0" "$b.sym" 1<>"$b.at"   <"$b.i"                  2>/dev/null
    "$BIN/cc1.blip" 9000 0 1<>"$b.hash" <"$b.at"             2>/dev/null
    "$BIN/cc2.blip" "$b.sym" 9000 0 0 1<>"$b.s" <"$b.hash"   2>/dev/null
    if ! err=$("$BIN/asblip" "$b.s" 2>&1); then echo "FAIL $name: assemble: $err"; fail=1; continue; fi
    if ! "$BIN/ldblip" -b -C0 "$CRT0" "$b.o" -o "$b.bin" "$LIB" 2>/dev/null; then
        echo "FAIL $name: link"; fail=1; continue; fi

    # oracle: the same image on the software emulator
    emu_out=$("$TEST/emublip" "$b.bin" 2>/dev/null); emu_rc=$?

    # device under test: the gate-level CPU
    python3 "$CT/bin2hex.py" "$b.bin" "$b.hex"
    log=$(timeout 600 vvp "$OUT/tb_csim" +PROG="$b.hex" +OUT="$b.simout" 2>&1)
    gate_out=$(cat "$b.simout" 2>/dev/null)
    gate_rc=$(printf '%s\n' "$log" | sed -n 's/^\[EXIT\] //p' | head -1)

    if printf '%s\n' "$log" | grep -q '^\[TIMEOUT\]'; then
        echo "FAIL $name: gate sim TIMEOUT (no exit) — $(printf '%s' "$log" | grep '^\[TIMEOUT\]')"; fail=1; continue
    fi
    if [ "$gate_out" = "$emu_out" ] && [ "${gate_rc:-X}" = "$emu_rc" ]; then
        echo "PASS $name: gate sim matches emublip (exit=$emu_rc${emu_out:+, output ok})"
    else
        echo "FAIL $name: gate vs emublip mismatch"
        echo "    emublip : exit=$emu_rc out=[$(printf '%s' "$emu_out" | tr '\n' ' ')]"
        echo "    gatesim : exit=${gate_rc:-?} out=[$(printf '%s' "$gate_out" | tr '\n' ' ')]"
        fail=1
    fi
done

[ "$fail" = 0 ] && echo "=== ctests: ALL PASS ===" || { echo "=== ctests: FAIL ==="; exit 1; }
