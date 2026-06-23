#!/bin/sh
# run-testblip.sh — assemble/link/run a BLIP program under the emublip emulator.
#
# Usage:
#   run-testblip.sh build              # (re)generate blip-emutab.h, build emublip,
#                                      # assemble testcrt0_blip.o
#   run-testblip.sh PROG.s [SYMMAP]    # assemble PROG.s, link with crt0 first,
#                                      # run under emublip, report the exit code
#
# The decode table blip-emutab.h is GENERATED from isa/opcodes.toml (never hand
# written) so the emulator stays in lockstep with the ratified opcode map.
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
fcc="$here/.."
bin="$fcc/bin"
gen="$fcc/../isa/gen_opcodes.py"
emutab="$here/blip-emutab.h"
emu="$here/emublip"
crt0="$here/testcrt0_blip.o"

build() {
	echo "generating blip-emutab.h from isa/opcodes.toml"
	python3 "$gen" emit-emutab > "$emutab"
	echo "building emublip"
	cc -Wall -O2 -I"$here" -o "$emu" "$here/emublip.c"
	echo "assembling testcrt0_blip.s"
	"$bin/asblip" "$here/testcrt0_blip.s"
	echo "built: $emu, $crt0"
}

run() {
	prog="$1"
	symmap="${2:-}"
	obj="${prog%.s}.o"
	imgbin=$(mktemp).bin
	"$bin/asblip" "$prog"
	# crt0 first so entry (PC=0) is the boot path
	"$bin/ldblip" -b -C0 -o "$imgbin" "$crt0" "$obj"
	set +e
	if [ -n "$symmap" ]; then
		"$emu" "$imgbin" "$symmap"
	else
		"$emu" "$imgbin"
	fi
	rc=$?
	set -e
	rm -f "$imgbin"
	echo "exit=$rc"
	return $rc
}

if [ "$#" -lt 1 ]; then
	echo "usage: run-testblip.sh build | PROG.s [SYMMAP]" >&2
	exit 1
fi

# always ensure the emulator + crt0 exist
if [ ! -x "$emu" ] || [ ! -e "$crt0" ] || [ "$1" = "build" ]; then
	build
fi

if [ "$1" = "build" ]; then
	exit 0
fi

run "$@"
