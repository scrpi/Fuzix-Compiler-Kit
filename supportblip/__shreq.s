;
;	__shreq — 16-bit (int) arithmetic `>>=` op-assign helper (signed).
;
;	Convention as __shleq: lvalue pointer pushed at (SP+2), COUNT in D, result
;	in D.  Shifts *p right high-byte-first with ASR (sign replicated), feeding
;	C down through the low byte via ROR.
;
	.export __shreq
	.code
__shreq:
	LD X,(SP+2)
	AND B,$0F
	LBEQ shreq_out
shreq_loop:
	LD A,(X+1)		; high byte
	ASR A			; bit7 preserved (sign), C = bit0 out
	ST A,(X+1)
	LD A,(X)		; low byte
	ROR A			; C into bit7
	ST A,(X)
	DEC B
	LBNE shreq_loop
shreq_out:
	LD D,(X)
	LD X,(SP)
	LEA SP,SP+4
	JMP X
