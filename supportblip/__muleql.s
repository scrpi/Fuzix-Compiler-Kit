;
;	__muleql — long (32-bit) `*=` op-assign helper (signed/unsigned share it;
;	the low 32 bits of a product are sign-independent).
;
;	Convention matches the other long op-assign helpers (cf. __pluseql,
;	__divequl): the lvalue POINTER is pushed by the caller (PUSH $06) just
;	above the 2-byte return address; the RHS arrives in D:Y (D = low word,
;	Y = high word).  Computes *p = *p * rhs, writes the product back through
;	the pointer, pops its own pointer + return, and returns via JMP X with the
;	product in D:Y.
;
;	Delegates to the value helper __mull.  The RHS is preserved in its own
;	stack slot and reloaded into D:Y just before the call, since building the
;	LHS from *p clobbers A.
;
	.export __muleql
	.code

__muleql:
	; On entry: (SP+0)=ret, (SP+2)=ptr; D:Y = RHS.
	PUSH $26		; save RHS at (SP+0..3).  (SP+4)=ret,(SP+6)=ptr.
	PUSH $26		; reserve LHS cell.  Now:
				;   (SP+0..3)=LHS (SP+4..7)=RHS (SP+8)=ret (SP+10)=ptr
	LD X,(SP+10)		; X = lvalue pointer
	LD A,(X)		; LHS = *p (little-endian, 4 bytes; clobbers A)
	ST A,(SP+0)
	LD A,(X+1)
	ST A,(SP+1)
	LD A,(X+2)
	ST A,(SP+2)
	LD A,(X+3)
	ST A,(SP+3)
	LD D,(SP+4)		; reload RHS into D:Y for __mull
	LD Y,(SP+6)
	JSR __mull		; pops LHS(4)+ret(2); product -> D:Y.  Back:
				;   (SP+0..3)=RHS (SP+4)=ret (SP+6)=ptr
	LD X,(SP+6)
	ST D,(X)		; *p = product (low word)
	ST Y,(X+2)		;          (high word)
	LD X,(SP+4)		; return address
	LEA SP,SP+8		; drop RHS(4) + ret(2) + ptr(2)
	JMP X
