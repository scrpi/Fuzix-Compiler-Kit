;
;	xa < @tmp unsigned
;
	.export	__lttmpu
	.export	__l_lttmpu
	.export __ccgtu
	.export __lttmpu

	.code

__ccgtu:
	jsr	__poptmp
	jmp	__lttmpu
__l_lttmpu:
	jsr	__ytmp
__lttmpu:
	cmp	@tmp
	txa
	ldx	#0
	sbc	@tmp+1
	bcc	true
	txa
	rts
true:
	lda	#1
	rts
__ltxayu:
	sty @tmp
	ldy #0
	sty @tmp+1
	beq __lttmpu
