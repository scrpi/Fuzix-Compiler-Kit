;
;	__shrequl — 32-bit (unsigned long) logical `>>=` op-assign helper.
;
;	Like __shreql but the most-significant byte is shifted with LSR (zero
;	fill), so no sign is replicated.
;
	.export __shrequl
	.code
__shrequl:
	LD X,(SP+2)
	AND B,$1F
	LBEQ shrequl_out
shrequl_loop:
	LD A,(X+3)		; byte 3 (MSB)
	LSR A			; zero fill
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
	LBNE shrequl_loop
shrequl_out:
	LD D,(X)
	LD Y,(X+2)
	LD X,(SP)
	LEA SP,SP+4
	JMP X
