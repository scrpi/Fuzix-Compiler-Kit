;
;	Compare A with @tmp
;
	.export __eqeqtmpc
	.export __eqeqtmpuc
	.export __l_eqeqtmpc
	.export __l_eqeqtmpuc

__l_eqeqtmpc:
__l_eqeqtmpuc:
	jsr	__ytmp
__eqeqtmpc:
__eqeqtmpuc:
	ldx #0
	cmp @tmp
	bne false
true:	lda #1
	rts
false:
	txa
	rts


