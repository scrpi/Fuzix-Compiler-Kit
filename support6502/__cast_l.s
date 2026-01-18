;
;	Cast int to long or unsigned long
;
	.export __cast_l
	.export __cast_ul

__cast_l:
__cast_ul:
	ldy #0
	cpx #0			; just force sign check
	bpl pve
	dey			; set Y to FF
pve:	sty @hireg
	sty @hireg+1
	rts
