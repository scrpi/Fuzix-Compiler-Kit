;
;	__shreql — 32-bit (long) arithmetic `>>=` op-assign helper (signed).
;
;	Convention as __shleql: pointer at (SP+2), COUNT in D, result in D:Y.
;	Shifts *p right from the most-significant byte down; ASR replicates the
;	sign bit and feeds C downward via ROR.
;
	.export __shreql
	.code
__shreql:
	LD X,(SP+2)
	AND B,$1F
	LBEQ shreql_out
shreql_loop:
	LD A,(X+3)		; byte 3 (MSB)
	ASR A			; sign preserved
	ST A,(X+3)
	LD A,(X+2)
	ROR A
	ST A,(X+2)
	LD A,(X+1)
	ROR A
	ST A,(X+1)
	LD A,(X)		; byte 0 (LSB)
	ROR A
	ST A,(X)
	DEC B
	LBNE shreql_loop
shreql_out:
	LD D,(X)
	LD Y,(X+2)
	LD X,(SP)
	LEA SP,SP+4
	JMP X
