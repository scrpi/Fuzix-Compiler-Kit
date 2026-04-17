all: libgb.a crt0.o

OBJ = workspace.o \
      __bool.o __castc_.o __pop.o __eqop.o \
      __switch.o __switchc.o \
      __ccgtu.o __ccgtequ.o __ccltu.o __ccltequ.o \
      __cclt.o __ccgteq.o __ccgt.o __cclteq.o __cceq.o __ccne.o \
      __cmpgteq0.o __cmplt0.o \
      __cmpeqcon.o __cmpnecon.o __cmpltcon.o __cmpgteqcon.o \
      __cmpgteqconu.o __cmpltconu.o \
      __minus.o \
      __postinc.o __postdec.o __postincc.o __postdecc.o \
      __pluseq.o \
      __minuseq2opcon.o __pluseq2opcon.o \
      __mul2op.o \
      __div2opcon.o __diveq.o \
      __band2op.o __bor2op.o __bxor2op.o \
      __andeq2op.o __oreq2op.o __xoreq2op.o \
      __andeq2opcon.o __oreq2opcon.o __xoreq2opcon.o \
      __shl2op.o __shl2opcon.o __shr2op.o __shr2opcon.o __shr2opu.o \
      __shreq.o __shrequ.o __shr2opconu.o __shreqc.o __shrequc.o \
      __shleq.o \
      __cpl.o __cmp32.o \
      __assignl.o __cast_l.o __derefl.o __cpll.o \
      __minuseql.o __pluseql.o __postincl.o __postdecl.o \
      __bandl.o __orl.o __xorl.o

.s.o:
	fcc -mgb -c $<
.c.o:
	fcc -mgb -O -c $<

libgb.a: $(OBJ)
	rm -f libgb.a
	ar qc libgb.a `../lorder8080 $(OBJ) | tsort`

clean:
	rm -f *.o *.a *~
