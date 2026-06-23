;
;	__divl / __reml — signed 32-bit divide and modulo.
;
;	Convention (matches backend gen for signed long '/' and '%'):
;	    LHS (dividend) pushed by caller (PSHS $26) at (SP+2..SP+5); RHS
;	    (divisor) in D:Y; result in D:Y; helper pops its own LHS + return.
;
;	C99 truncation toward zero:
;	    quotient  sign = sign(dividend) XOR sign(divisor)
;	    remainder sign = sign(dividend)
;	So we divide |dividend| / |divisor| with the unsigned core udiv32 and then
;	fix the sign.  The frame is exactly the one udiv32 expects (built like
;	__divul), and udiv32 never touches Y, so we keep the sign parity in Y
;	across the call.
;
	.export __divl
	.export __reml
	.code

;	neg32dy: D:Y = -(D:Y) (two's complement of the 32-bit working value).
neg32dy:
	COM A
	COM B
	XCHG D,Y
	COM A
	COM B
	XCHG D,Y
	ADD D,$0001
	XCHG D,Y
	ADC D,$0000
	XCHG D,Y
	RTS

__divl:
	PSHS $26		; push divisor.  R@SP+0..3, ret@SP+4, L@SP+6..9
	LD Y,$0000		; sign parity (# of negative operands)
	; --- |divisor|, count its sign ---
	LD A,(SP+3)
	BIT A,$80
	LBEQ dvl_rpos
	LEA Y,Y+1
	LD A,(SP+0)
	COM A
	ST A,(SP+0)
	LD A,(SP+1)
	COM A
	ST A,(SP+1)
	LD A,(SP+2)
	COM A
	ST A,(SP+2)
	LD A,(SP+3)
	COM A
	ST A,(SP+3)
	LD D,(SP+0)
	ADD D,$0001
	ST D,(SP+0)
	LD D,(SP+2)
	ADC D,$0000
	ST D,(SP+2)
dvl_rpos:
	; --- |dividend|, count its sign ---
	LD A,(SP+9)
	BIT A,$80
	LBEQ dvl_lpos
	LEA Y,Y+1
	LD A,(SP+6)
	COM A
	ST A,(SP+6)
	LD A,(SP+7)
	COM A
	ST A,(SP+7)
	LD A,(SP+8)
	COM A
	ST A,(SP+8)
	LD A,(SP+9)
	COM A
	ST A,(SP+9)
	LD D,(SP+6)
	ADD D,$0001
	ST D,(SP+6)
	LD D,(SP+8)
	ADC D,$0000
	ST D,(SP+8)
dvl_lpos:
	; --- finish the udiv frame and divide ---
	LD D,$0000
	PSHS $06
	PSHS $06		; rem = 0
	LD D,$0020
	PSHS $06		; count/ovf
	JSR udiv32		; Y (parity) preserved
	; quotient @SP+12..15
	CMP Y,$0001		; exactly one operand negative -> negate quotient
	LBNE dvl_pos
	LD D,(SP+12)
	LD Y,(SP+14)
	JSR neg32dy
	LBRA dvl_ret
dvl_pos:
	LD D,(SP+12)
	LD Y,(SP+14)
dvl_ret:
	LD X,(SP+10)
	LEA SP,SP+16
	JMP X

__reml:
	PSHS $26
	LD Y,$0000		; remainder sign = dividend sign
	; --- |divisor| (sign irrelevant for the remainder) ---
	LD A,(SP+3)
	BIT A,$80
	LBEQ rml_rpos
	LD A,(SP+0)
	COM A
	ST A,(SP+0)
	LD A,(SP+1)
	COM A
	ST A,(SP+1)
	LD A,(SP+2)
	COM A
	ST A,(SP+2)
	LD A,(SP+3)
	COM A
	ST A,(SP+3)
	LD D,(SP+0)
	ADD D,$0001
	ST D,(SP+0)
	LD D,(SP+2)
	ADC D,$0000
	ST D,(SP+2)
rml_rpos:
	; --- |dividend|, remember its sign ---
	LD A,(SP+9)
	BIT A,$80
	LBEQ rml_lpos
	LEA Y,Y+1
	LD A,(SP+6)
	COM A
	ST A,(SP+6)
	LD A,(SP+7)
	COM A
	ST A,(SP+7)
	LD A,(SP+8)
	COM A
	ST A,(SP+8)
	LD A,(SP+9)
	COM A
	ST A,(SP+9)
	LD D,(SP+6)
	ADD D,$0001
	ST D,(SP+6)
	LD D,(SP+8)
	ADC D,$0000
	ST D,(SP+8)
rml_lpos:
	LD D,$0000
	PSHS $06
	PSHS $06
	LD D,$0020
	PSHS $06
	JSR udiv32
	; remainder @SP+2..5
	CMP Y,$0001
	LBNE rml_pos
	LD D,(SP+2)
	LD Y,(SP+4)
	JSR neg32dy
	LBRA rml_ret
rml_pos:
	LD D,(SP+2)
	LD Y,(SP+4)
rml_ret:
	LD X,(SP+10)
	LEA SP,SP+16
	JMP X
