;
;	__divu / __remu — unsigned 16-bit divide and remainder.
;
;	Convention (matches backend-blip.c for '/' and '%' on unsigned):
;	    LHS (dividend) pushed by caller at (SP+2); RHS (divisor) in D.
;	    Result in D.  Helper pops its own LHS + return; returns JMP X.
;
;	div16x16 wants D = divisor, X = dividend -> X = quotient, D = remainder.
;	N,Z set from the result word by the closing ADD D,$0000.
;
	.export __divu
	.export __remu
	.code

__divu:
	LD X,(SP+2)		; X = dividend (LHS)
	JSR div16x16		; X = quotient, D = remainder
	LD D,X			; result = quotient
	JMP pop2u

__remu:
	LD X,(SP+2)		; X = dividend (LHS)
	JSR div16x16		; X = quotient, D = remainder (already in D)
pop2u:
	; pop LHS + return; result in D
	LD X,(SP)		; X = return address
	LEA SP,SP+4		; drop return(2) + LHS(2)
	ADD D,$0000		; set N,Z from result
	JMP X
