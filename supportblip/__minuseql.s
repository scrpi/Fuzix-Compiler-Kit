;
;	__minuseql — long (32-bit) `-=` op-assign helper.
;
;	Same convention as __pluseql: the lvalue POINTER is pushed by the caller
;	(PUSH $06) above the 2-byte return address; the RHS amount is in D:Y (D =
;	low word, Y = high word).  Subtract the amount from *p (4 bytes, little-
;	endian, borrow propagated via SBC), pop the pushed pointer + return, and
;	return via JMP X with the result in D:Y.
;
	.export __minuseql
	.code

__minuseql:
	PUSH $26		; stack the amount a0..a3 at (SP+0..3)
				;  (SP+4)=ret  (SP+6)=ptr
	LD X,(SP+6)		; X = lvalue pointer
	LD A,(X)		; *p -= amount, byte by byte with borrow
	SUB A,(SP+0)
	ST A,(X)
	LD A,(X+1)
	SBC A,(SP+1)
	ST A,(X+1)
	LD A,(X+2)
	SBC A,(SP+2)
	ST A,(X+2)
	LD A,(X+3)
	SBC A,(SP+3)
	ST A,(X+3)
	LD D,(X)		; result low word
	LD Y,(X+2)		; result high word
	LD X,(SP+4)		; return address
	LEA SP,SP+8		; drop amount(4) + ret(2) + ptr(2)
	JMP X
