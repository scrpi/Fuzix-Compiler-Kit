#!/bin/sh
for i in tests/*.c
do
	b=$(basename $i .c)
	echo  $b":"
	fcc -O -mgb -c tests/$b.c
	ldgb -b -C0 testcrt0_sm83.o tests/$b.o -o tests/$b /opt/fcc/lib/gb/libgb.a -m tests/$b.map
	./emusm83 tests/$b tests/$b.map
	rm -f tests/$b tests/$b.o tests/$b.map
done
