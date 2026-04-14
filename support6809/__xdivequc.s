;
;	D = ,X / D unsigned
;
	.export __xdivequc
	.export __xremequc

__xremequc:
	stx ,--s		; save pointer
	clra
	ldx ,x
	exg d,x
	exg a,b			; ldx ,x ended and exg ended up in A not B
	clra
	exg d,x
	lbsr div16x16		; do the unsigned divide
	stb [,s++]
	rts
	
__xdivequc:
	stx, --s
	ldx ,x			; Data value
	clra
	exg d,x
	exg a,b			; ldx ,x ended and exg ended up in A not B
	clra
	exg d,x
	lbsr div16x16		; do the maths
				; X = quotient, D = remainder
	exg d,x
	stb [,s++]
	rts
