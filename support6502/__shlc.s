;
;	Only used for non constant cases
;
	.export __shlc
	.export __lstmpc

;	TOS >> XA
__shlc:
	jsr	__poptmpc
;	tmp >> XA
__lstmpc:
	ldy	#0
	;	(TOS) << XA
	and	#7
	beq	nowork
	tax
	lda	(@tmp),y
loop:
	asl	a
	dex
	bne	loop
	rts
nowork:
	lda	(@tmp),y
	rts
