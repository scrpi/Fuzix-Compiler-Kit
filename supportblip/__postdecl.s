;
;	__postdecl — long (32-bit) post-decrement ( x-- / (*p)-- ), result used.
;
;	Emitted for a long-sized -- that inc_dec_node can't fold inline (size 4).
;	ABI mirrors __minuseql: the lvalue POINTER is pushed by the caller (PSHS
;	$06) above the 2-byte return address; the decrement amount is in D:Y (D =
;	low word, Y = high word — the scaled delta, 1 for a plain long).  Post
;	semantics: subtract the amount from *p in place (4 bytes, little-endian,
;	borrow via SBC) but return the ORIGINAL value of *p in D:Y.  The original is
;	stashed on the stack so the in-place subtract (which clobbers A) can't lose
;	it — no static scratch, so the helper stays re-entrant.
;
	.export __postdecl
	.code

__postdecl:
	PSHS $26		; stack the amount a0..a3 at (SP+0..3)
				;  (SP+4)=ret  (SP+6)=ptr
	LD X,(SP+6)		; X = lvalue pointer
	LD D,(X)		; D:Y = original *p ...
	LD Y,(X+2)
	PSHS $26		; ... stashed at (SP+0..3); amount -> (SP+4..7),
				;  (SP+8)=ret  (SP+10)=ptr
	LD A,(X)		; *p -= amount, byte by byte with borrow
	SUB A,(SP+4)
	ST A,(X)
	LD A,(X+1)
	SBC A,(SP+5)
	ST A,(X+1)
	LD A,(X+2)
	SBC A,(SP+6)
	ST A,(X+2)
	LD A,(X+3)
	SBC A,(SP+7)
	ST A,(X+3)
	LD D,(SP+0)		; return the stashed original in D:Y
	LD Y,(SP+2)
	LD X,(SP+8)		; return address
	LEA SP,SP+12		; drop original(4) + amount(4) + ret(2) + ptr(2)
	JMP X
