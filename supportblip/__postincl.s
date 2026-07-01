;
;	__postincl — long (32-bit) post-increment ( x++ / (*p)++ ), result used.
;
;	The + sibling of __postdecl (see there for the ABI).  Add the amount to *p
;	in place (4 bytes, little-endian, carry via ADC) but return the ORIGINAL
;	value of *p in D:Y; the original is stashed on the stack so the in-place add
;	(which clobbers A) can't lose it.
;
	.export __postincl
	.code

__postincl:
	PSHS $26		; stack the amount a0..a3 at (SP+0..3)
				;  (SP+4)=ret  (SP+6)=ptr
	LD X,(SP+6)		; X = lvalue pointer
	LD D,(X)		; D:Y = original *p ...
	LD Y,(X+2)
	PSHS $26		; ... stashed at (SP+0..3); amount -> (SP+4..7),
				;  (SP+8)=ret  (SP+10)=ptr
	LD A,(X)		; *p += amount, byte by byte with carry
	ADD A,(SP+4)
	ST A,(X)
	LD A,(X+1)
	ADC A,(SP+5)
	ST A,(X+1)
	LD A,(X+2)
	ADC A,(SP+6)
	ST A,(X+2)
	LD A,(X+3)
	ADC A,(SP+7)
	ST A,(X+3)
	LD D,(SP+0)		; return the stashed original in D:Y
	LD Y,(SP+2)
	LD X,(SP+8)		; return address
	LEA SP,SP+12		; drop original(4) + amount(4) + ret(2) + ptr(2)
	JMP X
