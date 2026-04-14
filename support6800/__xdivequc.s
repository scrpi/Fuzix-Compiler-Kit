;
;	D = ,X / D unsigned
;
	.export __xdivequc
	.export __xremequc

__xremequc:
	stx @tmp4		; save pointer
	clra
	staa @tmp
	stab @tmp+1
	ldab ,x
	clra
	staa @tmp2
	stab @tmp2+1
	ldaa @tmp
	ldab @tmp+1
	ldx @tmp2
	jsr div16x16		; do the unsigned divide
store:
	ldx @tmp4
	stab ,x
	rts
	
__xdivequc:
	stx @tmp4
	clra
	staa @tmp
	stab @tmp+1
	ldab ,x			; Data value
	clra
	staa @tmp2
	stab @tmp2+1
	ldaa @tmp
	ldab @tmp+1
	ldx @tmp2
	jsr div16x16		; do the maths
				; X = quotient, D = remainder
	stx @tmp
	ldaa @tmp
	ldab @tmp+1
	bra store
