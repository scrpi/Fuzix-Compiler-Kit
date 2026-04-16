#!/bin/sh
for i in tests/*.c
do
	b=$(basename $i .c)
	echo  $b":"
	fcc -m65c02 -c tests/$b.c
	ld6502 -b -C512 testcrt0_6502.o tests/$b.o -o tests/$b /opt/fcc/lib/6502/lib6502.a -m tests/$b.map
	./emu65c816 tests/$b tests/$b.map
done
