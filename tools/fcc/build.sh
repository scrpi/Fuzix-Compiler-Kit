#!/bin/sh
# Build the BLIP Fuzix-Bintools target (asblip/ldblip/nmblip/...) into tools/fcc/bin.
#
# The bintools/ submodule is pinned to a pristine upstream commit. The BLIP
# target (as1-blip.c, as6-blip.c, the obj.h arch id, the as.h config block and
# the Makefile rules) is carried as patches under patches/ and applied into the
# submodule at build time, so we never have to maintain a bintools fork with our
# changes -- we just pin a commit and patch on top. See README.md.
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
bintools="$here/bintools"
bindir="$here/bin"

if [ ! -e "$bintools/Makefile" ]; then
	echo "submodule not checked out; run:" >&2
	echo "    git submodule update --init $bintools" >&2
	exit 1
fi

# Stage the BLIP target into the submodule if it isn't applied yet.
if [ ! -e "$bintools/as1-blip.c" ]; then
	for p in "$here"/patches/*.patch; do
		echo "applying $(basename "$p")"
		git -C "$bintools" apply --whitespace=nowarn "$p"
	done
fi

echo "building BLIP target..."
make -C "$bintools" asblip ldblip nmblip osizeblip dumprelocsblip

mkdir -p "$bindir"
for t in asblip ldblip nmblip osizeblip dumprelocsblip; do
	cp "$bintools/$t" "$bindir/$t"
done
echo "built -> $bindir"
ls -l "$bindir"
