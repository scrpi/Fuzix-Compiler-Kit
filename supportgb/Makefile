all: libgb.a crt0.o

OBJ = workspace.o \
      __bool.o __pop.o \
      __ccgtu.o __ccgtequ.o __ccltu.o __ccltequ.o \
      __cmpeqcon.o __cmpgteqconu.o __cmpltconu.o

.s.o:
	fcc -mgb -c $<
.c.o:
	fcc -mgb -O -c $<

libgb.a: $(OBJ)
	rm -f libgb.a
	ar qc libgb.a `../lorder8080 $(OBJ) | tsort`

clean:
	rm -f *.o *.a *~
