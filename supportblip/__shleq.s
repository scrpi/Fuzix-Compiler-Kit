;
;	__shleq — 16-bit (int) `<<=` op-assign helper.
;
;	Convention matches the other op-assign helpers (cf. __pluseql): the lvalue
;	POINTER is pushed by the caller (PUSH $06) just above the 2-byte return
;	address, and the shift COUNT arrives in D (low byte = count).  Shifts *p in
;	place a byte at a time (BLIP has no memory-shift op), leaves the result in
;	D, pops its own pointer + return, and returns via JMP X.
;
	.export __shleq
	.code
__shleq:
	LD X,(SP+2)		; X = lvalue pointer
	AND B,$0F		; count &= 15 (shift >= width is undefined in C)
	LBEQ shleq_out
shleq_loop:
	LD A,(X)		; low byte
	ASL A			; 0 into bit0, C = bit7 out
	ST A,(X)
	LD A,(X+1)		; high byte
	ROL A			; C into bit0
	ST A,(X+1)
	DEC B
	LBNE shleq_loop
shleq_out:
	LD D,(X)		; result
	LD X,(SP)		; return address
	LEA SP,SP+4		; drop return(2) + ptr(2)
	JMP X
