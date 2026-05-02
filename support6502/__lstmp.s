;
;	@tmp << XA (only low bits of A matter)
;
	.export __lstmp
	.export __lstmpu
	.export __l_ltlt
	.export __shl

	.code

__l_ltlt:
	sta	@tmp
	stx	@tmp+1
	dey
	lda	(@sp),y
__lstmp:
__lstmpu:
	and	#15
	beq	nowork
	tax
loop:	asl	@tmp
	rol	@tmp+1
	dex
	bne	loop
nowork:
	lda	@tmp
	ldx	@tmp+1
	rts

__shl:	; (TOS) << XA
	jsr	__poptmp
	; now @tmp << XA
	jmp	__lstmp
	