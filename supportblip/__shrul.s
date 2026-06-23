;
;	__shrul — 32-bit (long) logical right shift (unsigned >>).
;
;	Same convention as __shrl, but the most-significant byte is shifted with
;	LSR (zero into bit7) rather than ASR, so no sign is propagated.
;
	.export __shrul
	.code

__shrul:
	AND B,$1F		; count &= 31
	LBEQ shrul_out
shrul_loop:
	LD A,(SP+5)
	LSR A			; MSB: 0 into bit7, C = bit0 out
	ST A,(SP+5)
	LD A,(SP+4)
	ROR A
	ST A,(SP+4)
	LD A,(SP+3)
	ROR A
	ST A,(SP+3)
	LD A,(SP+2)
	ROR A
	ST A,(SP+2)
	DEC B
	LBNE shrul_loop
shrul_out:
	LD D,(SP+2)
	LD Y,(SP+4)
	LD X,(SP)
	LEA SP,SP+6
	JMP X
