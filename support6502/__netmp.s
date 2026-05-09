;
;	Compare XA with __tmp
;
	.export __netmp
	.export __netmpu
	.export __l_netmp
	.export __l_netmpu
	.export __ccne
	.export __ccneu
	.export __nexay

__l_netmp:
__l_netmpu:
	jsr __ytmp
	jmp __netmp
__ccne:
__ccneu:
	jsr __poptmp
__netmp:
__netmpu:
	cmp @tmp
	bne true
	txa
	ldx #0
	cmp @tmp+1
	bne true2
	txa
	rts
true:	ldx #0
true2:	lda #1
	rts
__nexay:
	sty @tmp
	ldy #0
	sty @tmp+1
	beq __netmp
