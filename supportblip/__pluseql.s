;
;	__pluseql — long (32-bit) `+=` op-assign helper.
;
;	Calling convention (backend-blip gen for `*p += v` on a 32-bit type):
;	    the lvalue POINTER is pushed by the caller (PUSH $06) just above the
;	    2-byte return address; the RHS amount arrives in D:Y (D = low word,
;	    Y = high word).  The helper adds the amount into *p (4 bytes, little-
;	    endian) and — like the other long helpers — pops its own pushed
;	    pointer + return address and returns via JMP X, result in D:Y.
;
	.export __pluseql
	.code

__pluseql:
	PUSH $26		; stack the amount a0..a3 at (SP+0..3)
				;  (SP+4)=ret  (SP+6)=ptr
	LD X,(SP+6)		; X = lvalue pointer
	LD A,(X)		; *p += amount, byte by byte with carry
	ADD A,(SP+0)
	ST A,(X)
	LD A,(X+1)
	ADC A,(SP+1)
	ST A,(X+1)
	LD A,(X+2)
	ADC A,(SP+2)
	ST A,(X+2)
	LD A,(X+3)
	ADC A,(SP+3)
	ST A,(X+3)
	LD D,(X)		; result low word
	LD Y,(X+2)		; result high word
	LD X,(SP+4)		; return address
	LEA SP,SP+8		; drop amount(4) + ret(2) + ptr(2)
	JMP X
