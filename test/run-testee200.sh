#!/bin/sh
for i in tests/*.c
do
	b=$(basename $i .c)
	echo  $b":"
	fcc  -mee200 -c tests/$b.c
	ldee200 -b -C256 testcrt0_ee200.o tests/$b.o -o tests/$b /opt/fcc/lib/ee200/libee200.a -m tests/$b.map
	./ee200 tests/$b tests/$b.map
done
