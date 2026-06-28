;
;	__shr — 16-bit (int) arithmetic right shift (signed >>).
;
;	Same convention as __shl: value pushed at (SP+2..SP+3), shift COUNT in D,
;	result in D; helper pops its own operand + return, JMP X.  Shifts the high
;	byte first with ASR (the sign bit is replicated), then RORs the carry down
;	through the low byte, COUNT times.
;
	.export __shr
	.code

__shr:
	AND B,$0F		; count &= 15
	LBEQ shr_out
shr_loop:
	LD A,(SP+3)		; high byte
	ASR A			; bit7 preserved (sign), C = bit0 out
	ST A,(SP+3)
	LD A,(SP+2)		; low byte
	ROR A			; C into bit7, C = bit0 out
	ST A,(SP+2)
	DEC B
	LBNE shr_loop
shr_out:
	LD D,(SP+2)		; result
	LD X,(SP)		; return address
	LEA SP,SP+4		; drop return(2) + operand(2)
	JMP X
