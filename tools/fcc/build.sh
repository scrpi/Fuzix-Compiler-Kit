#!/bin/sh
# Build the BLIP toolchain into tools/fcc/bin: the assembler/linker (asblip,
# ldblip, ...) from the bintools submodule, and the C compiler (cc, cc0,
# cc1.blip, cc2.blip) from the compiler-kit submodule.
#
# Both submodules track the BLIP port on the 'blip' branch of our forks (pinned
# by the superproject); there is nothing to patch at build time. The assembler's
# opcode table (blip-optab.h) is the one generated artifact: it is produced fresh
# from the single source of truth, isa/opcodes.toml, so it can never drift from
# the ratified opcode map. See README.md.
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
bintools="$here/bintools"
ckit="$here/compiler-kit"
bindir="$here/bin"
genopcodes="$here/../isa/gen_opcodes.py"

mkdir -p "$bindir"

# ---- assembler / linker (bintools) ----
if [ ! -e "$bintools/Makefile" ]; then
	echo "submodule not checked out; run: git submodule update --init $bintools" >&2
	exit 1
fi
echo "generating blip-optab.h from isa/opcodes.toml"
python3 "$genopcodes" emit-asmtab > "$bintools/blip-optab.h"
echo "building assembler/linker..."
make -C "$bintools" asblip ldblip nmblip osizeblip dumprelocsblip
for t in asblip ldblip nmblip osizeblip dumprelocsblip; do
	cp "$bintools/$t" "$bindir/$t"
done

# ---- C compiler (compiler-kit) ----
if [ -e "$ckit/Makefile" ]; then
	echo "building C compiler (cc, cc0, cc1.blip, cc2.blip)..."
	make -C "$ckit" cc cc0 cc1.blip cc2.blip
	for t in cc cc0 cc1.blip cc2.blip; do
		cp "$ckit/$t" "$bindir/$t"
	done
	cp "$ckit/cpp" "$bindir/cpp"	# preprocessor (shell wrapper)

	# Support/runtime library (mul/div/rem/switch helpers + crt0). Needs asblip
	# (built above) and the system archiver; produces libblip.a + crt0.o.
	if [ -e "$ckit/supportblip/build.sh" ]; then
		echo "building support library (libblip.a)..."
		( cd "$ckit/supportblip" && sh build.sh >/dev/null )
		cp "$ckit/supportblip/libblip.a" "$bindir/libblip.a"
		cp "$ckit/supportblip/crt0.o" "$bindir/crt0.o"
	fi
else
	echo "compiler-kit submodule not checked out; skipping compiler" >&2
fi

echo "built -> $bindir"
ls -l "$bindir"
