#!/bin/sh
# Smoke test: build asblip, assemble a tiny program, and check the emitted bytes.
# This is a wiring/round-trip check only. The byte values below match the 6809
# clone the target currently carries; they will be updated to BLIP's real opcode
# map as the encoder is retargeted (see ../README.md).
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
fcc="$here/.."

sh "$fcc/build.sh" >/dev/null

asm="$(mktemp).s"; obj="${asm%.s}.o"
trap 'rm -f "$asm" "$obj"' EXIT
printf '\t.code\nstart:\n\tlda #$42\n\tsta $0400\n\tjmp start\n' > "$asm"

"$fcc/bin/asblip" "$asm"
bytes=$("$fcc/bin/dumprelocsblip" "$obj" | tr -s ' ' | grep -oE '86 42 B7 04 00 7E' || true)

if [ "$bytes" = "86 42 B7 04 00 7E" ]; then
	echo "PASS: asblip round-trip produced expected bytes"
else
	echo "FAIL: unexpected encoding" >&2
	"$fcc/bin/dumprelocsblip" "$obj" >&2
	exit 1
fi
