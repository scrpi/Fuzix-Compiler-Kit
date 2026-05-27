all: libsm83.a crt0.o

OBJ = workspace.o \
      __bool.o __castc_.o __pop.o __eqop.o \
      __switch.o __switchc.o \
      __cmpgteq0.o __cmplt0.o \
      __cmpeqcon.o __cmpnecon.o \
      __cmpgteqconu.o __cmpltconu.o __cmplteqconu.o __cmpgtconu.o \
      __cmpgteqcon.o __cmpltcon.o __cmplteqcon.o __cmpgtcon.o \
      __minus.o \
      __postinc.o __postdec.o __postincc.o __postdecc.o \
      __pluseq.o __minuseq.o \
      __minuseq2opcon.o __pluseq2opcon.o __pluseq2opconc.o \
      __mul2op.o \
      __div2opcon.o __diveq.o \
      __band2op.o __bor2op.o __bxor2op.o \
      __andeq2op.o __oreq2op.o __xoreq2op.o \
      __andeq2opcon.o __oreq2opcon.o __xoreq2opcon.o \
      __shl2op.o __shl2opcon.o __shr2op.o __shr2opcon.o __shr2opu.o \
      __shreq.o __shrequ.o __shr2opconu.o __shreqc.o __shrequc.o \
      __shleq.o \
      __cpl.o __cmp32.o __switchl.o \
      __assignl.o __cast_l.o __derefl.o __cpll.o \
      __minuseql.o __pluseql.o __postincl.o __postdecl.o \
      __bandl.o __orl.o __xorl.o __andeql.o __oreql.o __xoreql.o \
      __shll.o __shrl.o \
      __plusl.o __minusl.o __mull.o __divul.o __divl.o \
      __booll.o \
     __boolf.o __cast2f.o __castf.o __cceqf.o __ccgteqf.o __ccgtf.o __cclteqf.o \
      __ccltf.o __ccnef.o __divf.o __minusf.o __mulf.o __plusf.o __eqopf.o

.s.o:
	fcc -msm83 -c $<

.c.o:
	fcc -msm83 -O -c $<

libsm83.a: $(OBJ)
	rm -f libsm83.a
	ar qc libsm83.a `../lorder8080 $(OBJ) | tsort`

clean:
	rm -f *.o *.a *~
