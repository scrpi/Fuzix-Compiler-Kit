;
;	__divequl — long (32-bit) unsigned `/=` op-assign helper.
;
;	The generic backend lowers `*p /= v` on a 32-bit type to a call whose
;	convention matches the other long op-assign helpers (cf. __pluseql):
;	    the lvalue POINTER is pushed by the caller (PSHS $06) just above the
;	    2-byte return address; the RHS (divisor) arrives in D:Y (D = low word,
;	    Y = high word).  The helper computes *p = *p / divisor (unsigned),
;	    writes the quotient back through the pointer, pops its own pushed
;	    pointer + return address and returns via JMP X with the quotient
;	    (the value of the assignment expression) in D:Y.
;
;	Implementation: delegate the arithmetic to the value helper __divul,
;	whose convention is "LHS pushed above its return address, RHS in D:Y,
;	result in D:Y, pops its own LHS+ret".  Building the LHS from *p clobbers
;	A (and overwrites a stack copy of D:Y), so the divisor is preserved in its
;	OWN stack slot and reloaded into D:Y just before the call — never relying
;	on the live D:Y surviving the *p byte copies.
;
	.export __divequl
	.code

__divequl:
	; On entry: (SP+0)=ret, (SP+2)=ptr; D:Y = divisor.
	PSHS $26		; save divisor at (SP+0..3).  (SP+4)=ret,(SP+6)=ptr.
	PSHS $26		; reserve LHS cell at (SP+0..3).  Now:
				;   (SP+0..3)=LHS  (SP+4..7)=divisor  (SP+8)=ret
				;   (SP+10)=ptr
	LD X,(SP+10)		; X = lvalue pointer
	LD A,(X)		; LHS = *p (little-endian, 4 bytes; clobbers A)
	ST A,(SP+0)
	LD A,(X+1)
	ST A,(SP+1)
	LD A,(X+2)
	ST A,(SP+2)
	LD A,(X+3)
	ST A,(SP+3)
	LD D,(SP+4)		; reload divisor into D:Y for __divul
	LD Y,(SP+6)
	JSR __divul		; pops LHS(4)+ret(2); quotient -> D:Y.  Back:
				;   (SP+0..3)=divisor  (SP+4)=ret  (SP+6)=ptr
	LD X,(SP+6)		; reload lvalue pointer
	ST D,(X)		; *p = quotient (low word)
	ST Y,(X+2)		;           (high word)
	LD X,(SP+4)		; return address
	LEA SP,SP+8		; drop divisor(4) + ret(2) + ptr(2)
	JMP X
