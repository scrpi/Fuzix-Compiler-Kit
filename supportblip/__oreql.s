;
;	__oreql — 32-bit (long) `|=` op-assign helper.
;
;	Convention matches the other long op-assign helpers (cf. __pluseql): the
;	lvalue POINTER is pushed by the caller (PUSH $06) just above the 2-byte
;	return address; the RHS arrives in D:Y (D = low word, Y = high word).
;	Combines *p |= RHS byte by byte and writes it back, leaves the result in
;	D:Y, pops its own pointer + return, and returns via JMP X.
;
;	OR has no A,(SP+n) form, so each RHS byte is loaded into A and combined
;	against *p through the A,(X+n) form (or is commutative).
;
	.export __oreql
	.code
__oreql:
	PUSH $26		; stack RHS a0..a3 at (SP+0..3); (SP+4)=ret,(SP+6)=ptr
	LD X,(SP+6)		; X = lvalue pointer
	LD A,(SP+0)		; RHS byte0
	OR A,(X)		; |= *p byte0
	ST A,(X)
	LD A,(SP+1)
	OR A,(X+1)
	ST A,(X+1)
	LD A,(SP+2)
	OR A,(X+2)
	ST A,(X+2)
	LD A,(SP+3)
	OR A,(X+3)
	ST A,(X+3)
	LD D,(X)		; result low word
	LD Y,(X+2)		; result high word
	LD X,(SP+4)		; return address
	LEA SP,SP+8		; drop RHS(4) + ret(2) + ptr(2)
	JMP X
