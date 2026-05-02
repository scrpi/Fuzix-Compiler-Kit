;
;	Awkward case 8bit subtract of (TOS) - A
;
	.export __minusc

__minusc:
	sec
	eor	#$FF
	ldy	#0
	adc	(sp),y
	sta	@tmp
	jmp	__addysp1		; take 1 byte off

