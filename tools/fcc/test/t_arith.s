; t_arith.s — sum 1..10 = 55 via a loop using ADD D and CMP/Bcc.
; exit 0 if the sum is 55, else exit 1.
;
; A and B are the two halves of D, so neither can hold a loop counter that must
; survive a 16-bit LD D / ADD D. The counter i therefore lives in Y, and the
; per-iteration addend is materialised in memory at $0402 from Y's low byte.
; The running sum lives at $0400.
	.code
	.export _main
_main:
	LD D,$0000
	ST D,($0400)		; sum = 0
	LD Y,$0001		; i = 1
loop:
	ST Y,($0402)		; scratch = i (16-bit, little-endian)
	LD D,($0400)		; D = sum
	ADD D,($0402)		; D = sum + i
	ST D,($0400)		; sum = D
	LEA Y,Y+1		; i++
	CMP Y,$000B		; compare i with 11
	BNE loop		; loop while i = 1..10
	; check sum == 55 (0x37)
	LD D,($0400)
	CMP D,$0037
	BNE fail
	LD B,$00
	ST B,($FF03)		; exit(0)
fail:
	LD B,$01
	ST B,($FF03)		; exit(1)
	RTS
