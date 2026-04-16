#!/bin/sh
for i in tests/*.c
do
	b=$(basename $i .c)
	echo  $b":"
	fcc -m1802 -c tests/$b.c
	ld1802 -b -C0 testcrt0_byte1802.o tests/$b.o -o tests/$b -m tests/$b.map
	./byte1802 tests/$b tests/$b.map
done
