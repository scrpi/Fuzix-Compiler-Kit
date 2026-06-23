#!/bin/sh
# Build the BLIP toolchain into tools/fcc/bin: the assembler/linker (asblip,
# ldblip, ...) from the bintools submodule, and the C compiler (cc, cc0,
# cc1.blip, cc2.blip) from the compiler-kit submodule.
#
# Both submodules are pinned to pristine upstream commits; the BLIP target is
# carried as patches under patches/<submodule>/ and applied at build time, so we
# never maintain a fork -- we pin a commit and patch on top. The assembler's
# opcode table (blip-optab.h) is generated fresh from the single source of
# truth, isa/opcodes.toml. See README.md.
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
bintools="$here/bintools"
ckit="$here/compiler-kit"
bindir="$here/bin"
genopcodes="$here/../isa/gen_opcodes.py"

apply_patches() {	# apply_patches <submodule-dir> <patch-dir> <sentinel-file>
	if [ ! -e "$1/$3" ]; then
		for p in "$2"/*.patch; do
			echo "applying $(basename "$p")"
			git -C "$1" apply --whitespace=nowarn "$p"
		done
	fi
}

mkdir -p "$bindir"

# ---- assembler / linker (bintools) ----
if [ ! -e "$bintools/Makefile" ]; then
	echo "submodule not checked out; run: git submodule update --init $bintools" >&2
	exit 1
fi
apply_patches "$bintools" "$here/patches/bintools" as1-blip.c
echo "generating blip-optab.h from isa/opcodes.toml"
python3 "$genopcodes" emit-asmtab > "$bintools/blip-optab.h"
echo "building assembler/linker..."
make -C "$bintools" asblip ldblip nmblip osizeblip dumprelocsblip
for t in asblip ldblip nmblip osizeblip dumprelocsblip; do
	cp "$bintools/$t" "$bindir/$t"
done

# ---- C compiler (compiler-kit) ----
if [ -e "$ckit/Makefile" ]; then
	apply_patches "$ckit" "$here/patches/compiler-kit" backend-blip.c
	echo "building C compiler (cc, cc0, cc1.blip, cc2.blip)..."
	make -C "$ckit" cc cc0 cc1.blip cc2.blip
	for t in cc cc0 cc1.blip cc2.blip; do
		cp "$ckit/$t" "$bindir/$t"
	done
else
	echo "compiler-kit submodule not checked out; skipping compiler" >&2
fi

echo "built -> $bindir"
ls -l "$bindir"
