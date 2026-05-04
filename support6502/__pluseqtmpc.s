	.export __pluseqc
	.export __pluseqtmpc
	.export __pluseqtmpuc

__pluseqc:
	jsr	__poptmp
	jmp	doop
__pluseqtmpc:
__pluseqtmpuc:
	stx	@tmp+1
	ldy	#0
doop:
	clc
	adc	(@tmp),y
	sta	(@tmp),y
	rts
