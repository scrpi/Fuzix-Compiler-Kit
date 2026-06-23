;
;	__mull / __mulul — 32x32 -> 32 multiply (low 32 bits).
;
;	Calling convention (matches backend gen for a long '*'):
;	    LHS pushed by caller (PSHS $26) -> at (SP+2..SP+5) above the 2-byte
;	    return address (low word SP+2, high word SP+4); RHS in D:Y on entry
;	    (D = low word, Y = high word).  Result in D:Y.  The helper pops its
;	    own LHS + return and returns via JMP X.
;
;	Schoolbook of the 8x8 hardware MUL (D = A*B, unsigned).  With operand
;	bytes a0..a3 (LHS, a0 = LSB) and b0..b3 (RHS), the result byte k gets
;	every product ai*bj with i+j == k; products with i+j > 3 overflow past
;	bit 31 and are dropped.  Signed and unsigned share this code: the low 32
;	bits of a product are independent of operand sign.
;
	.export __mull
	.export __mulul
	.code

__mull:
__mulul:
	PSHS $26		; save RHS (b0..b3).  Frame:
				;  (SP+0)=b0 (SP+1)=b1 (SP+2)=b2 (SP+3)=b3
				;  (SP+4)=ret  (SP+6)=a0..a3
	LD D,$0000
	PSHS $06		; result high half = 0
	PSHS $06		; result low half  = 0.  Frame now:
				;  (SP+0..3)=r0..r3
				;  (SP+4..7)=b0..b3
				;  (SP+8..9)=ret
				;  (SP+10..13)=a0..a3
	; k=0 : a0*b0 -> r0,r1  (result is zero, just store)
	LD A,(SP+10)
	LD B,(SP+4)
	MUL
	ST D,(SP+0)
	; k=1 : a0*b1 -> r1,r2 (+carry r3)
	LD A,(SP+10)
	LD B,(SP+5)
	MUL
	ADD D,(SP+1)
	ST D,(SP+1)
	LD A,(SP+3)
	ADC A,$00
	ST A,(SP+3)
	; k=1 : a1*b0
	LD A,(SP+11)
	LD B,(SP+4)
	MUL
	ADD D,(SP+1)
	ST D,(SP+1)
	LD A,(SP+3)
	ADC A,$00
	ST A,(SP+3)
	; k=2 : a0*b2 -> r2,r3
	LD A,(SP+10)
	LD B,(SP+6)
	MUL
	ADD D,(SP+2)
	ST D,(SP+2)
	; k=2 : a1*b1
	LD A,(SP+11)
	LD B,(SP+5)
	MUL
	ADD D,(SP+2)
	ST D,(SP+2)
	; k=2 : a2*b0
	LD A,(SP+12)
	LD B,(SP+4)
	MUL
	ADD D,(SP+2)
	ST D,(SP+2)
	; k=3 : low byte only (high overflows past bit 31)
	LD A,(SP+10)		; a0*b3
	LD B,(SP+7)
	MUL
	ADD B,(SP+3)
	ST B,(SP+3)
	LD A,(SP+11)		; a1*b2
	LD B,(SP+6)
	MUL
	ADD B,(SP+3)
	ST B,(SP+3)
	LD A,(SP+12)		; a2*b1
	LD B,(SP+5)
	MUL
	ADD B,(SP+3)
	ST B,(SP+3)
	LD A,(SP+13)		; a3*b0
	LD B,(SP+4)
	MUL
	ADD B,(SP+3)
	ST B,(SP+3)
	; --- load result, unwind everything, return ---
	LD D,(SP+0)		; low word
	LD Y,(SP+2)		; high word
	LD X,(SP+8)		; return address
	LEA SP,SP+14		; drop result(4)+RHS(4)+ret(2)+LHS(4)
	JMP X
