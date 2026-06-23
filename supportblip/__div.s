;
;	__div / __rem — signed 16-bit divide and remainder.
;
;	Convention (matches backend-blip.c for '/' and '%' on signed int):
;	    LHS (dividend) pushed by caller at (SP+2); RHS (divisor) in D.
;	    Result in D.  Helper pops its own LHS + return; returns JMP X.
;
;	Signed rules (C99, truncation toward zero):
;	    quotient  sign = sign(dividend) XOR sign(divisor)
;	    remainder sign = sign(dividend)
;	So we divide |dividend| / |divisor| unsigned, then fix the sign.
;
;	Y is callee-saved (§7); we save it on entry and reuse it as scratch
;	(sign parity for __div / dividend-sign flag for __rem).
;	N,Z are set from the result word by the closing ADD D,$0000.
;
	.export __div
	.export __rem
	.code

;
;	__div: quotient = L / R, sign = sign(L) XOR sign(R)
;	Y holds the running parity of negations (odd => negate quotient).
;
__div:
	PSHS $20		; save Y
				; Frame: (SP+0..1)=savedY (SP+2..3)=ret
				;        (SP+4)=Llo (SP+5)=Lhi
	LD Y,$0000		; sign parity = 0
	; --- divisor (currently in D); A = divisor high byte ---
	BIT A,$80
	BEQ dv_rpos
	LEA Y,Y+1		; divisor negative -> one sign flip
	JSR negd		; D = |divisor|
dv_rpos:
	LD X,D			; X = |divisor|
	; --- dividend ---
	LD A,(SP+5)		; A = Lhi (dividend high byte)
	BIT A,$80
	BEQ dv_lpos
	LEA Y,Y+1		; dividend negative -> another sign flip
dv_lpos:
	LD D,(SP+4)		; D = dividend (L word)
	JSR absd		; D = |dividend|
	XCHG D,X
	JSR div16x16		; X = quotient, D = remainder
	LD D,X			; D = |quotient|
	; negate quotient if exactly one operand was negative (Y == 1).
	; (Y is 0, 1 or 2; CMP Y leaves D untouched.)
	CMP Y,$0001
	BNE dv_done
	JSR negd
dv_done:
	JMP divpop

;
;	__rem: remainder = L % R, sign = sign(L)
;	Y low byte holds the dividend sign flag (nonzero => negate remainder).
;
__rem:
	PSHS $20		; save Y
				; Frame: (SP+0..1)=savedY (SP+2..3)=ret
				;        (SP+4)=Llo (SP+5)=Lhi
	; --- divisor (in D): take |divisor| into X (sign irrelevant) ---
	JSR absd		; D = |divisor|
	LD X,D			; X = |divisor|
	; --- dividend: remember its sign in Y, then take |dividend| ---
	LD A,(SP+5)		; A = Lhi
	LD Y,$0000
	BIT A,$80
	BEQ rm_lpos
	LEA Y,Y+1		; dividend negative
rm_lpos:
	LD D,(SP+4)		; D = dividend
	JSR absd		; D = |dividend|
	XCHG D,X
	JSR div16x16		; X = quotient, D = remainder = |L| % |R|
	; remainder sign follows dividend (negate if dividend was negative, Y==1).
	CMP Y,$0001
	BNE rm_done
	JSR negd
rm_done:
	; fall through to divpop

;
;	Common tail: restore Y, pop LHS+return, set N,Z, return.
;	Frame here: (SP+0..1)=savedY (SP+2..3)=ret (SP+4)=L word
;
divpop:
	PULS $20		; restore Y ; Frame: (SP+0..1)=ret (SP+2)=L word
	LD X,(SP)		; X = return address
	LEA SP,SP+4		; drop return(2) + LHS(2)
	ADD D,$0000		; set N,Z from result
	JMP X

;
;	negd: D = -D (two's complement).
;
negd:
	COM A
	COM B
	ADD D,$0001
	RTS

;
;	absd: D = |D| (signed 16-bit).
;
absd:
	BIT A,$80		; sign bit of high byte
	BEQ absdone
	COM A
	COM B
	ADD D,$0001
absdone:
	RTS
