#!/bin/sh
# Smoke test: build the BLIP toolchain, assemble a small program, and check the
# emitted bytes against the ratified encoding (isa/opcodes.toml, isa.md §3/§8).
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
fcc="$here/.."

sh "$fcc/build.sh" >/dev/null

asm="$(mktemp).s"; obj="${asm%.s}.o"
trap 'rm -f "$asm" "$obj"' EXIT

# LD A,$42 / ST A,($0400) / loop: DEC A / BNE loop
printf '\t.code\nstart:\n\tLD A,$42\n\tST A,($0400)\nloop:\n\tDEC A\n\tBNE loop\n' > "$asm"
"$fcc/bin/asblip" "$asm"

bytes=$("$fcc/bin/dumprelocsblip" "$obj" | sed -n '/Segment 1:/,/Segment 2:/p' \
	| grep -oE '^[0-9a-f]{4}\b.*' | grep -oE '\b[0-9A-F]{2}\b' | tr '\n' ' ' | sed 's/ *$//')

# 00 42        LD A,$42      (imm8)
# 1A 00 04     ST A,($0400)  (abs16, little-endian)
# 99           DEC A
# B8 FD        BNE loop      (rel8 = -3, relative to next instruction)
expect="00 42 1A 00 04 99 B8 FD"
if [ "$bytes" = "$expect" ]; then
	echo "PASS: asblip round-trip = [$bytes]"
else
	echo "FAIL: got [$bytes] expected [$expect]" >&2
	exit 1
fi
