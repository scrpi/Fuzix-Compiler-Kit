;
;	__shll — 32-bit (long) left shift.
;
;	Calling convention (matches backend-blip.c gen for a long '<<'):
;	    The long is pushed by the caller (PUSH $26) -> at (SP+2..SP+5)
;	    above the 2-byte return address, little-endian (low word at SP+2,
;	    high word at SP+4).  The shift COUNT arrives in D.  The result is
;	    returned in D:Y (D = low word, Y = high word).  The helper pops its
;	    own operand + return address and returns via JMP X.
;
;	BLIP has no memory-shift instructions, so the stacked long is shifted a
;	byte at a time through A: ASL the least-significant byte, then ROL the
;	carry up through the most-significant byte, COUNT times.  LD/ST do not
;	touch C (isa.md S8.5), so the carry survives between the bytes.
;
	.export __shll
	.code

__shll:
	AND B,$1F		; count &= 31 (a shift >= width is undefined in C)
	LBEQ shll_out
shll_loop:
	LD A,(SP+2)
	ASL A			; LSB: 0 into bit0, C = bit7 out
	ST A,(SP+2)
	LD A,(SP+3)
	ROL A			; C into bit0, C = bit7 out
	ST A,(SP+3)
	LD A,(SP+4)
	ROL A
	ST A,(SP+4)
	LD A,(SP+5)
	ROL A
	ST A,(SP+5)
	DEC B
	LBNE shll_loop
shll_out:
	LD D,(SP+2)		; result low word
	LD Y,(SP+4)		; result high word
	LD X,(SP)		; return address
	LEA SP,SP+6		; drop return(2) + operand(4)
	JMP X
