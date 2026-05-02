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
__minuseqtmpc:
__minuseqtmpuc:
	ldy	#0
	eor	#0xFF
	sec
	adc	(@tmp),y
	sta	(@tmp),y
	rts
