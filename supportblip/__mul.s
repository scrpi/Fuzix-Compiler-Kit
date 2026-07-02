;
;	__mul — 16x16 -> 16 signed/unsigned multiply.
;
;	Calling convention (matches backend-blip.c gen for '*'):
;	    LHS pushed by caller (PUSH $06) -> at (SP+2) above the 2-byte
;	    return address; RHS in D on entry; result returned in D.
;	    The helper pops its own LHS + return address (caller does NOT
;	    clean up) and returns via JMP X.
;
;	D = L * R, low 16 bits.  With L = Lhi:Llo, R = Rhi:Rlo:
;	    result = Llo*Rlo + ((Lhi*Rlo + Llo*Rhi) & 0xFF) << 8
;	The two cross terms only contribute their low byte to the result's
;	high byte (anything above bit 15 is discarded for a 16-bit product),
;	so 8x8 hardware MUL (D = A*B, unsigned) composes the whole thing.
;
;	N,Z are set from the 16-bit result by the closing ADD D,$0000.
;
	.export __mul
	.code

__mul:
	PUSH $06		; save R.  Frame now:
				;  (SP+0)=Rlo (SP+1)=Rhi
				;  (SP+2)=ret_lo (SP+3)=ret_hi
				;  (SP+4)=Llo (SP+5)=Lhi
	; --- cross = (Lhi*Rlo + Llo*Rhi) low byte ---
	LD A,(SP+5)		; A = Lhi
	LD B,(SP+0)		; B = Rlo
	MUL
	PUSH $04		; push B (cross partial). Frame shifts +1:
				;  (SP+0)=cross
				;  (SP+1)=Rlo (SP+2)=Rhi
				;  (SP+3)=ret_lo (SP+4)=ret_hi
				;  (SP+5)=Llo (SP+6)=Lhi
	LD A,(SP+5)		; A = Llo
	LD B,(SP+2)		; B = Rhi
	MUL
	ADD B,(SP+0)		; B = (Llo*Rhi + Lhi*Rlo) low byte = cross
	ST B,(SP+0)		; cross stored back
	; --- main = Llo*Rlo (full 16 bits) ---
	LD A,(SP+5)		; A = Llo
	LD B,(SP+1)		; B = Rlo
	MUL
	ADD A,(SP+0)		; add cross into high byte of result
	; D now holds the 16-bit product (A:B)
	; --- pop scratch (cross) + saved R, then LHS + return ---
	LEA SP,SP+3		; drop cross(1) + R(2)
	; Frame now: (SP+0)=ret_lo (SP+1)=ret_hi (SP+2)=L word
	LD X,(SP)		; X = return address
	LEA SP,SP+4		; drop return(2) + LHS(2)
	ADD D,$0000		; set N,Z from the result word
	JMP X
