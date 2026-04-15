	.export __install_traps
	.code
;
;	Trap table for -O cases
;
	.word	__lstref0		; 23
	.word	__push0			; 22
	.word	__pargr1		; 21
	.word	__nstore_2		; 20
	.word	__cceqconst0		; 19
	.word	__garg10r2		; 18
	.word	__popw			; 17
	.word	__cceqconstb		; 16
	.word	__gargr4		; 15
	.word	__load2			; 14
	.word	__nref_1		; 13
	.word	__plusplus		; 12
	.word	__pushacl		; 11
	.word	__frame			; 10
	.word	__gargr1		; 9
	.word	__pushln		; 8
	.word	__pargr2		; 7
	.word	__nref_2		; 6
	.word	__gargr2		; 5
	.word	__pushac		; 4
trapdata:

__install_traps:
	; Install the traps. The top traps 0-3 are used for restart and
	; interrupt handling but we use the rest.
	mov	%0xFF,r2
	mov	%0xF7,r3
	mov	%>trapdata-1,r4
	mov	%<trapdata-1,r5
	mov	%40,r6
loop:
	lda	*r5
	sta	*r3
	decd	r5
	decd	r3
	djnz	r6,loop
	rets
