; t_stack.s — exercise PSHS/PULS round-trip and JSR/RTS.
; exit 0 if everything round-trips, else a nonzero code identifying the failure.
	.code
	.export _main
_main:
	; --- PSHS D / PULS D round-trips a 16-bit value ---
	LD D,$BEEF
	PSHS $06		; push D (A+B)
	LD D,$0000		; clobber D
	PULS $06		; restore D
	CMP D,$BEEF
	BNE f1

	; --- PSHS of D+Y, then PULS, restores both ---
	LD D,$1234
	LD Y,$5678
	PSHS $26		; push D and Y
	LD D,$0000
	LD Y,$0000
	PULS $26
	CMP D,$1234
	BNE f2
	CMP Y,$5678
	BNE f3

	; --- JSR/RTS: add7 adds 7 to D and returns ---
	LD D,$0010
	JSR add7
	CMP D,$0017		; 0x10 + 7
	BNE f4

	LD B,$00
	ST B,($FF03)		; exit(0)

f1:	LD B,$01
	ST B,($FF03)
f2:	LD B,$02
	ST B,($FF03)
f3:	LD B,$03
	ST B,($FF03)
f4:	LD B,$04
	ST B,($FF03)

; add7: D += 7 ; return
add7:
	ADD D,$0007
	RTS
