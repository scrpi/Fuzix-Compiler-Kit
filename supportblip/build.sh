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
# The long (32-bit) op-assign helpers __muleql / __diveql / __divequl /
# __remeql / __remequl delegate to the matching value helpers (__mull / __divl
# / __divul / __reml / __remul).  The one-pass librarian pulls a member only to
# resolve an already-undefined symbol, so each referencer must precede its
# definer: the op-assign helpers go before __mull (in __mull.s) and before
# __divl / __divul (which define __divl/__reml and __divul/__remul).
# The bitwise (__andeql/__oreql/__xoreql) and shift (__shleq/__shreq/__shrequ +
# long __sh*eql) op-assign helpers are self-contained — they operate on *p in
# place and delegate to nothing — so their archive position is unconstrained.
SRCS="__pluseql.s __minuseql.s __pop.s __muleql.s __mul.s __mull.s __diveql.s __divequl.s __remeql.s __remequl.s __divl.s __divul.s __divu.s __div.s __andeql.s __oreql.s __xoreql.s __shl.s __shr.s __shru.s __shll.s __shrl.s __shrul.s __shleq.s __shreq.s __shrequ.s __shleql.s __shreql.s __shrequl.s __switch.s __switchc.s divide.s"

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
