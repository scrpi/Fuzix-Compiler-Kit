;
;	Compare XA with __tmp
;
	.export __l_eqeqtmp
	.export __l_eqeqtmpu
	.export __eqeqtmp
	.export __eqeqtmpu
	.export __cceq

__l_eqeqtmp:
__l_eqeqtmpu:
	jsr __ytmp
	jmp __eqeqtmp
__cceq:
	jsr __poptmp
__eqeqtmp:
__eqeqtmpu:
	cmp @tmp
	bne false
	txa
	ldx #0
	cmp @tmp+1
	bne false2
	lda #1
	rts
false:	ldx #0
false2: txa
	rts
