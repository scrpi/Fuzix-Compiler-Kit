;
;	D = ,X / D unsigned
;
	.export __xdivequc
	.export __xremequc

__xremequc:
	pshx			; save pointer
	clra
	ldx ,x
	xgdx
	tab			; was in the high half
	clra
	xgdx
	jsr div16x16		; do the unsigned divide
store:
	pulx
	stab ,x
	rts
	
__xdivequc:
	pshx
	ldx ,x			; Data value
	clra
	xgdx
	tab
	clra
	xgdx
	jsr div16x16		; do the maths
				; X = quotient, D = remainder
	xgdx
	bra store
