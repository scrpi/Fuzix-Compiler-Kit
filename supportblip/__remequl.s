;
;	__remequl — long (32-bit) unsigned `%=` op-assign helper.
;
;	Convention (the long op-assign family; cf. __pluseql / __divequl): the
;	lvalue POINTER is pushed by the caller (PSHS $06) above the 2-byte return
;	address; the RHS (divisor) arrives in D:Y.  Computes *p = *p % divisor
;	(unsigned), writes the remainder back, pops its own pointer + return, and
;	returns via JMP X with the remainder in D:Y.
;
;	Delegates to the unsigned value helper __remul.  The divisor is preserved
;	in its own stack slot and reloaded into D:Y just before the call, since
;	building the LHS from *p clobbers A.
;
	.export __remequl
	.code

__remequl:
	; On entry: (SP+0)=ret, (SP+2)=ptr; D:Y = divisor.
	PSHS $26		; save divisor at (SP+0..3).  (SP+4)=ret,(SP+6)=ptr.
	PSHS $26		; reserve LHS cell.  Now:
				;   (SP+0..3)=LHS (SP+4..7)=divisor (SP+8)=ret (SP+10)=ptr
	LD X,(SP+10)		; X = lvalue pointer
	LD A,(X)		; LHS = *p (little-endian, 4 bytes; clobbers A)
	ST A,(SP+0)
	LD A,(X+1)
	ST A,(SP+1)
	LD A,(X+2)
	ST A,(SP+2)
	LD A,(X+3)
	ST A,(SP+3)
	LD D,(SP+4)		; reload divisor into D:Y for __remul
	LD Y,(SP+6)
	JSR __remul		; pops LHS(4)+ret(2); remainder -> D:Y.  Back:
				;   (SP+0..3)=divisor (SP+4)=ret (SP+6)=ptr
	LD X,(SP+6)
	ST D,(X)
	ST Y,(X+2)
	LD X,(SP+4)
	LEA SP,SP+8		; drop divisor(4) + ret(2) + ptr(2)
	JMP X
