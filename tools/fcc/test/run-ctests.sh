#!/bin/sh
# Compile each ctests/*.c with the BLIP C compiler, link with crt0 (no support
# library - these are pure-native programs), run on emublip, and check it exits
# 0. Each test program returns 0 on success / a nonzero code at the failing
# check. Also asserts the generated assembly has no helper calls (these
# programs must compile entirely to native BLIP).
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
fcc="$here/.."
bin="$fcc/bin"

# Build the toolchain + emulator + crt0 if needed.
[ -x "$bin/cc2.blip" ] || sh "$fcc/build.sh" >/dev/null
sh "$here/run-testblip.sh" build >/dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

for c in "$here"/ctests/*.c; do
	name=$(basename "$c" .c)
	b="$work/$name"
	# preprocess (strips comments / handles directives), then the stages
	# (which lseek/read fd 1, so open read-write 1<> on fresh files)
	"$bin/cpp" "$c" "$b.i" 2>/dev/null
	"$bin/cc0" "$work/sym" 1<>"$b.at" <"$b.i" 2>/dev/null
	"$bin/cc1.blip" 9000 0 1<>"$b.hash" <"$b.at" 2>/dev/null
	"$bin/cc2.blip" "$work/sym" 9000 0 0 1<>"$b.s" <"$b.hash" 2>/dev/null
	if ! err=$("$bin/asblip" "$b.s" 2>&1); then
		echo "FAIL $name: assemble: $err"; fail=1; continue
	fi
	"$bin/ldblip" -b -C0 "$here/testcrt0_blip.o" "$b.o" -o "$b.bin" 2>/dev/null
	rc=0; "$here/emublip" "$b.bin" >/dev/null 2>&1 || rc=$?
	helpers=$(grep -c 'JSR __' "$b.s" || true)
	if [ "$rc" = 0 ] && [ "$helpers" = 0 ]; then
		echo "PASS $name"
	else
		echo "FAIL $name: exit=$rc helpers=$helpers"; fail=1
	fi
done

[ "$fail" = 0 ] && echo "all ctests passed" || { echo "ctests FAILED"; exit 1; }
