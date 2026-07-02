;
;	__divul / __remul — unsigned 32-bit divide and modulo, and the shared
;	restoring-division core udiv32.
;
;	Calling convention (matches backend gen for long '/' and '%'):
;	    LHS (dividend) pushed by caller (PUSH $26) at (SP+2..SP+5); RHS
;	    (divisor) in D:Y on entry; result in D:Y; helper pops its own LHS +
;	    return and returns via JMP X.
;
;	Classic shift/subtract restoring division of the 64-bit (rem:dividend)
;	pair: each of 32 iterations shifts the pair left one bit (the dividend's
;	top bit enters rem, and the dividend's freed low bit becomes the next
;	quotient bit), subtracts the divisor from rem, and restores it on borrow.
;	The shift can push rem to 33 bits; that 33rd bit (ovf) means rem >=
;	divisor regardless of the low-32 borrow, so it overrides the keep/restore
;	decision.  Division by zero never borrows -> quotient 0xFFFFFFFF (defined,
;	non-trapping; see README).
;
	.export __divul
	.export __remul
	.export udiv32
	.code

;	udiv32: divide a frame the caller built.  Relative to udiv32's SP (after
;	JSR): SP+2=count, SP+3=ovf, SP+4..7=rem, SP+8..11=divisor, SP+14..17=
;	dividend/quotient.  Leaves quotient and remainder in the frame; RTS.
udiv32:
udiv_loop:
	LD A,(SP+14)		; (rem:dividend) <<= 1, dividend first
	ASL A
	ST A,(SP+14)
	LD A,(SP+15)
	ROL A
	ST A,(SP+15)
	LD A,(SP+16)
	ROL A
	ST A,(SP+16)
	LD A,(SP+17)
	ROL A
	ST A,(SP+17)		; C = dividend bit 31
	LD A,(SP+4)
	ROL A
	ST A,(SP+4)		; rem byte 0 takes that bit
	LD A,(SP+5)
	ROL A
	ST A,(SP+5)
	LD A,(SP+6)
	ROL A
	ST A,(SP+6)
	LD A,(SP+7)
	ROL A
	ST A,(SP+7)		; C = rem overflow (33rd bit)
	LD A,$00
	ROL A
	ST A,(SP+3)		; ovf = that bit
	LD D,(SP+4)		; rem -= divisor (32-bit)
	SUB D,(SP+8)
	ST D,(SP+4)
	LD D,(SP+6)
	SBC D,(SP+10)
	ST D,(SP+6)		; C = final borrow
	LBCC udiv_keep		; no borrow -> rem >= divisor -> keep
	LD A,(SP+3)
	CMP A,$00
	LBNE udiv_keep		; overflow -> keep despite low-32 borrow
	LD D,(SP+4)		; restore rem += divisor
	ADD D,(SP+8)
	ST D,(SP+4)
	LD D,(SP+6)
	ADC D,(SP+10)
	ST D,(SP+6)
	LBRA udiv_next		; quotient bit stays 0
udiv_keep:
	LD A,(SP+14)
	OR A,$01		; set the new quotient bit
	ST A,(SP+14)
udiv_next:
	DEC (SP+2)
	LBNE udiv_loop
	RTS

;	Build the working frame, divide, extract the quotient.
__divul:
	PUSH $26		; divisor
	LD D,$0000
	PUSH $06		; rem high = 0
	PUSH $06		; rem low  = 0
	LD D,$0020		; B = 32 (count), A = 0 (ovf)
	PUSH $06
	JSR udiv32
	; frame: SP+0=count SP+1=ovf SP+2..5=rem SP+6..9=divisor
	;        SP+10=ret SP+12..15=quotient
	LD D,(SP+12)		; quotient low word
	LD Y,(SP+14)		; quotient high word
	LD X,(SP+10)
	LEA SP,SP+16		; drop frame(10)+ret(2)+LHS(4)
	JMP X

__remul:
	PUSH $26
	LD D,$0000
	PUSH $06
	PUSH $06
	LD D,$0020
	PUSH $06
	JSR udiv32
	LD D,(SP+2)		; remainder low word
	LD Y,(SP+4)		; remainder high word
	LD X,(SP+10)
	LEA SP,SP+16
	JMP X
