; t_print.s — print a known integer via _printint and a char via _printchar,
; then exit 0. Expected stdout:
;   12345
;   A
	.code
	.export _main
_main:
	; printint(12345)  -> "12345\n"   (12345 = 0x3039)
	LD D,$3039
	PSHS $06		; push the 16-bit argument (caller pushes)
	JSR _printint
	LEA SP,SP+2		; caller cleanup of the 2-byte arg

	; printchar('A')   -> "A"
	LD D,$0041		; 'A' in the low byte
	PSHS $06
	JSR _printchar
	LEA SP,SP+2

	LD B,$00
	ST B,($FF03)		; exit(0)
