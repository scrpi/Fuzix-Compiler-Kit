;
;	div16x16 — unsigned 16-bit shift/subtract divide core.
;
;	On entry:  D = divisor, X = dividend.
;	On exit:   X = quotient, D = remainder.
;	Clobbers A,B (i.e. D), X.  Preserves Y.
;
;	Classic restoring division: for each of the 16 bits, shift the
;	(work:dividend) pair left by one, tentatively set the new quotient
;	bit, subtract the divisor from the work accumulator, and if that
;	borrowed (work went negative) add the divisor back and clear the
;	quotient bit.  After 16 iterations X = quotient, D = work = remainder.
;
;	Note: division by zero is NOT trapped.  With divisor = 0 the subtract
;	never borrows, so every quotient bit is set: this returns quotient =
;	0xFFFF and remainder = dividend.  (Documented, defined behaviour; see
;	supportblip/README.)
;
	.export div16x16
	.code

div16x16:
	PSHS $06		; push divisor at (SP).  D free now.
	LD D,$0010		; 16
	PSHS $04		; push B (=$10) as the loop counter at (SP).
				; Frame: (SP+0)=count
				;        (SP+1)=divisor_lo (SP+2)=divisor_hi
	LD D,$0000		; work = 0
loop:
	; --- shift (work:X) left by one, carry chains X(bit15) -> work(bit0) ---
	XCHG D,X
	ASL B
	ROL A
	XCHG D,X
	ROL B
	ROL A
	LEA X,X+1		; tentatively set new quotient bit (dividend lsb)
	SUB D,(SP+1)		; work -= divisor
	BCC skip		; no borrow -> bit stays set
	ADD D,(SP+1)		; borrow: restore work
	LEA X,X-1		; clear the quotient bit
skip:
	DEC (SP+0)		; --count
	BNE loop
	LEA SP,SP+3		; drop counter(1) + divisor(2)
	RTS
