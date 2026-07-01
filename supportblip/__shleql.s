;
;	__shleql — 32-bit (long) `<<=` op-assign helper.
;
;	Convention as __shleq but for a 4-byte lvalue: pointer pushed at (SP+2),
;	COUNT in D (low byte), result returned in D:Y (low word / high word).
;	Shifts *p in place from the least-significant byte up, COUNT times.
;
	.export __shleql
	.code
__shleql:
	LD X,(SP+2)		; X = lvalue pointer
	AND B,$1F		; count &= 31
	LBEQ shleql_out
shleql_loop:
	LD A,(X)		; byte 0 (LSB)
	ASL A
	ST A,(X)
	LD A,(X+1)
	ROL A
	ST A,(X+1)
	LD A,(X+2)
	ROL A
	ST A,(X+2)
	LD A,(X+3)		; byte 3 (MSB)
	ROL A
	ST A,(X+3)
	DEC B
	LBNE shleql_loop
shleql_out:
	LD D,(X)		; result low word
	LD Y,(X+2)		; result high word
	LD X,(SP)		; return address
	LEA SP,SP+4		; drop return(2) + ptr(2)
	JMP X
