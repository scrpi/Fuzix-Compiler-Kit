;
;	D = ,X / D unsigned
;
	.export __xdivequc
	.export __xremequc

	.setcpu 6803

__xremequc:
	pshx			; save pointer
	clra
	std @tmp
	ldab ,x
	clra
	std @tmp2
	ldd @tmp
	ldx @tmp2
	jsr div16x16		; do the unsigned divide
store:
	pulx
	stab ,x
	rts
	
__xdivequc:
	pshx
	clra
	std @tmp
	ldab ,x			; Data value
	clra
	std @tmp2
	ldd @tmp
	ldx @tmp2
	jsr div16x16		; do the maths
				; X = quotient, D = remainder
	stx @tmp
	ldd @tmp
	bra store
