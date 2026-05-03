;
;	Cast char or int to long or unsigned long
;
	.export __castc_l
	.export __cast_l
	.export __cast_ul

__castc_l:
__castc_ul:
	ldx #0
	ora #0
	bpl pve
	dex
	bmi nve
__cast_l:
__cast_ul:
	ldy #0
	cpx #0			; just force sign check
	bpl pve
nve:	dey			; set Y to FF
pve:	sty @hireg
	sty @hireg+1
	rts
