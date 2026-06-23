;
;	__shrl — 32-bit (long) arithmetic right shift (signed >>).
;
;	Same convention as __shll: the long is at (SP+2..SP+5) (low word SP+2,
;	high word SP+4), the COUNT in D, the result returned in D:Y, and the
;	helper pops its own operand + return.  Shift from the most-significant
;	byte down: ASR preserves the sign bit and feeds C downward via ROR.
;
	.export __shrl
	.code

__shrl:
	AND B,$1F		; count &= 31
	LBEQ shrl_out
shrl_loop:
	LD A,(SP+5)
	ASR A			; MSB: sign preserved, C = bit0 out
	ST A,(SP+5)
	LD A,(SP+4)
	ROR A			; C into bit7, C = bit0 out
	ST A,(SP+4)
	LD A,(SP+3)
	ROR A
	ST A,(SP+3)
	LD A,(SP+2)
	ROR A
	ST A,(SP+2)
	DEC B
	LBNE shrl_loop
shrl_out:
	LD D,(SP+2)
	LD Y,(SP+4)
	LD X,(SP)
	LEA SP,SP+6
	JMP X
