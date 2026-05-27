#!/bin/sh
for i in tests/*.c
do
	b=$(basename $i .c)
	echo  $b":"
	fcc -O -msm83 -c tests/$b.c
	ldsm83 -b -C0 testcrt0_sm83.o tests/$b.o -o tests/$b /opt/fcc/lib/sm83/libsm83.a -m tests/$b.map
	./emusm83 tests/$b tests/$b.map
	rm -f tests/$b tests/$b.o tests/$b.map
done
