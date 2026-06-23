#!/bin/sh
# Smoke test: build the BLIP toolchain, assemble a small program, and check the
# emitted bytes against the ratified encoding (isa/opcodes.toml, isa.md §3/§8).
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
fcc="$here/.."

sh "$fcc/build.sh" >/dev/null

asm="$(mktemp).s"; obj="${asm%.s}.o"
trap 'rm -f "$asm" "$obj"' EXIT

emitted() {	# emitted <objfile> -> hex bytes of the code segment
	"$fcc/bin/dumprelocsblip" "$1" | sed -n '/Segment 1:/,/Segment 2:/p' \
		| grep -oE '^[0-9a-f]{4}\b.*' | grep -oE '\b[0-9A-F]{2}\b' \
		| tr '\n' ' ' | sed 's/ *$//'
}

check() {	# check <name> <expect>; source is already assembled to $obj
	got=$(emitted "$obj")
	if [ "$got" = "$2" ]; then
		echo "PASS: $1 = [$got]"
	else
		echo "FAIL: $1 got [$got] expected [$2]" >&2
		exit 1
	fi
}

# --- mixed modes: imm8, abs16 (little-endian), rel8 backward branch ---
printf '\t.code\nstart:\n\tLD A,$42\n\tST A,($0400)\nloop:\n\tDEC A\n\tBNE loop\n' > "$asm"
"$fcc/bin/asblip" "$asm"
# 00 42       LD A,$42      (imm8)
# 1A 00 04    ST A,($0400)  (abs16, little-endian)
# 99          DEC A
# B8 FD       BNE loop      (rel8 = -3, relative to next instruction)
check "modes/rel8" "00 42 1A 00 04 99 B8 FD"

# --- branch offsets: rel8 and rel16, both relative to the next instruction ---
printf '\t.code\nspin:\n\tNOP\n\tBRA spin\n\tLBRA spin\n' > "$asm"
"$fcc/bin/asblip" "$asm"
# D0          NOP                (spin @ 0)
# B2 FD       BRA spin           (rel8  = 0 - 3 = -3   = FD)
# 80 1F F9 FF LBRA spin          (rel16 = 0 - 7 = -7   = FFF9, little-endian)
check "branches" "D0 B2 FD 80 1F F9 FF"

