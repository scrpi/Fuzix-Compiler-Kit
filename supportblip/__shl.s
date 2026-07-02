;
;	__shl — 16-bit (int) left shift.
;
;	Calling convention (matches backend-blip.c gen for an int '<<', same shape
;	as __mul/__shll): the value is pushed by the caller (PUSH $06) -> at
;	(SP+2..SP+3) above the 2-byte return address, little-endian (low at SP+2).
;	The shift COUNT arrives in D (low byte = count).  The result is returned in
;	D.  The helper pops its own operand + return address and returns via JMP X.
;
;	BLIP has no memory-shift instructions, so the stacked value is shifted a
;	byte at a time through A: ASL the low byte, then ROL the carry up through
;	the high byte, COUNT times.  LD/ST do not touch C (isa.md S8.5), so the
;	carry survives between the bytes.
;
	.export __shl
	.code

__shl:
	AND B,$0F		; count &= 15 (a shift >= width is undefined in C)
	LBEQ shl_out
shl_loop:
	LD A,(SP+2)		; low byte
	ASL A			; 0 into bit0, C = bit7 out
	ST A,(SP+2)
	LD A,(SP+3)		; high byte
	ROL A			; C into bit0, C = bit7 out
	ST A,(SP+3)
	DEC B
	LBNE shl_loop
shl_out:
	LD D,(SP+2)		; result
	LD X,(SP)		; return address
	LEA SP,SP+4		; drop return(2) + operand(2)
	JMP X
