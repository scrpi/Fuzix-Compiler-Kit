;
;	Compare A with @tmp
;
	.export __eqeqtmpc
	.export __eqeqtmpuc
	.export __l_eqeqtmpc
	.export __l_eqeqtmpuc
	.export __cceqc
	.export __ccequc
	.export __eqeqxa

__l_eqeqtmpc:
__l_eqeqtmpuc:
	jsr	__ytmpc
	jmp	__eqeqtmpc
__cceqc:
__ccequc:
	jsr	__poptmpc
__eqeqtmpc:
__eqeqtmpuc:
	ldx 	#0
	cmp	@tmp
	bne	false
true:	lda	#1
	rts
__eqeqxa:
	stx	@tmp
	ldx	#0
	cmp	@tmp
	beq	true
false:
	txa
	rts
