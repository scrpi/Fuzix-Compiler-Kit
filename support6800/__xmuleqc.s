;
;	,X *= D
;
	.export __xmuleqc
	.export __xmulequc

__xmuleqc:
__xmulequc:
	stx @tmp4
	stab @tmp+1
	clra
	ldab ,x
	pshb		; onto the stack
	psha
	; A is still clear
	ldab @tmp+1
	jsr __mul	; Do the multiply, D gets result, _mul removes the arg
	ldx @tmp4
	stab ,x		; Save result
	rts
