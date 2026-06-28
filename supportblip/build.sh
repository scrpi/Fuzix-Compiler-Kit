#!/bin/sh
# build.sh — assemble the BLIP support-library helpers and archive libblip.a.
#
# Each .s is assembled with the kit's own asblip; the objects are archived with
# the system 'ar' (Unix ar format, which ldblip reads — see bintools/ar.h).
# Order matters for the one-pass librarian/linker: a member that DEFINES a
# symbol is placed before members that REFERENCE it, so divide.o (div16x16)
# precedes __div.o/__divu.o, etc.
set -eu

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
bin="$here/../../bin"
as="$bin/asblip"
ar=${AR:-ar}

# Archive order for the one-pass linker: a member is only pulled when it
# resolves an already-undefined symbol, so a member that DEFINES a symbol must
# come AFTER the members that reference it.  div16x16 (divide.o) is referenced
# by __div.o/__divu.o, so divide.o is placed last.
SRCS="__mul.s __mull.s __divl.s __divul.s __divu.s __div.s __shl.s __shr.s __shru.s __shll.s __shrl.s __shrul.s __switch.s __switchc.s divide.s"

OBJS=""
for s in $SRCS; do
	echo "asblip $s"
	"$as" "$here/$s"
	OBJS="$OBJS $here/${s%.s}.o"
done

# crt0 is built but NOT put in the archive (it is an object the link line names
# explicitly, like testcrt0_blip.o).
echo "asblip crt0.s"
"$as" "$here/crt0.s"

rm -f "$here/libblip.a"
# shellcheck disable=SC2086
"$ar" qc "$here/libblip.a" $OBJS
echo "built: $here/libblip.a"
echo "       $here/crt0.o"
