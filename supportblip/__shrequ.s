;
;	__shrequ — 16-bit (unsigned int) logical `>>=` op-assign helper.
;
;	Like __shreq but the high byte is shifted with LSR (zero fill) instead of
;	ASR, so no sign is replicated.
;
	.export __shrequ
	.code
__shrequ:
	LD X,(SP+2)
	AND B,$0F
	LBEQ shrequ_out
shrequ_loop:
	LD A,(X+1)		; high byte
	LSR A			; 0 into bit7, C = bit0 out
	ST A,(X+1)
	LD A,(X)		; low byte
	ROR A
	ST A,(X)
	DEC B
	LBNE shrequ_loop
shrequ_out:
	LD D,(X)
	LD X,(SP)
	LEA SP,SP+4
	JMP X
