;
;	__shru — 16-bit (int) logical right shift (unsigned >>).
;
;	Same convention as __shl: value pushed at (SP+2..SP+3), shift COUNT in D,
;	result in D; helper pops its own operand + return, JMP X.  Like __shr but
;	the high byte is shifted with LSR (zero fill) instead of ASR.
;
	.export __shru
	.code

__shru:
	AND B,$0F		; count &= 15
	LBEQ shru_out
shru_loop:
	LD A,(SP+3)		; high byte
	LSR A			; 0 into bit7, C = bit0 out
	ST A,(SP+3)
	LD A,(SP+2)		; low byte
	ROR A			; C into bit7, C = bit0 out
	ST A,(SP+2)
	DEC B
	LBNE shru_loop
shru_out:
	LD D,(SP+2)		; result
	LD X,(SP)		; return address
	LEA SP,SP+4		; drop return(2) + operand(2)
	JMP X
