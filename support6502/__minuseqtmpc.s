;
;	We do -= differently to the others as it is not commutive. Instead
;	we negate the value and add
;
;	Based on code from Ullrich von Bassewitz for CC65
;
	.export	__minuseqtmpc
	.export	__minuseqtmpuc
	.export __minuseqc

__minuseqc:
	jsr	__poptmp
	jmp	doop
__minuseqtmpc:
__minuseqtmpuc:
	stx	@tmp+1
	ldy	#0
doop:
	eor	#0xFF
	sec
	adc	(@tmp),y
	sta	(@tmp),y
	rts
