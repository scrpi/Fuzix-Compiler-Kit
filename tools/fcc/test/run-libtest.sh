#!/bin/sh
# Build libblip.a, then compile each lib_*.c (or the files named as args), link
# with crt0 + libblip.a, run on emublip, and assert exit 0. These programs
# exercise the support-library helpers (multiply, divide/remainder, switch).
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
fcc="$here/.."
bin="$fcc/bin"
support="$fcc/compiler-kit/supportblip"
lib="$support/libblip.a"
crt0="$here/testcrt0_blip.o"

# Build the toolchain, emulator + crt0, and the support library.
[ -x "$bin/cc2.blip" ] || sh "$fcc/build.sh" >/dev/null
sh "$here/run-testblip.sh" build >/dev/null
( cd "$support" && sh build.sh >/dev/null )

if [ "$#" -gt 0 ]; then set -- "$@"; else set -- "$here"/lib_*.c; fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail=0
for c in "$@"; do
	name=$(basename "$c" .c); b="$work/$name"
	"$bin/cpp" "$c" "$b.i" 2>/dev/null
	"$bin/cc0" "$b.sym" 1<>"$b.at" <"$b.i" 2>/dev/null
	"$bin/cc1.blip" 9000 0 1<>"$b.hash" <"$b.at" 2>/dev/null
	"$bin/cc2.blip" "$b.sym" 9000 0 0 1<>"$b.s" <"$b.hash" 2>/dev/null
	if ! err=$("$bin/asblip" "$b.s" 2>&1); then echo "FAIL $name: assemble: $err"; fail=1; continue; fi
	if ! "$bin/ldblip" -b -C0 "$crt0" "$b.o" -o "$b.bin" "$lib" 2>/dev/null; then
		echo "FAIL $name: link"; fail=1; continue
	fi
	rc=0; "$here/emublip" "$b.bin" >/dev/null 2>&1 || rc=$?
	[ "$rc" = 0 ] && echo "PASS $name" || { echo "FAIL $name: exit=$rc"; fail=1; }
done

[ "$fail" = 0 ] && echo "all libtests passed" || { echo "libtests FAILED"; exit 1; }
