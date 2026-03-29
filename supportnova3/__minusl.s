;
;	32bit TOS minus hireg:1
;
	.export f__minusl
	.code
f__minusl:
	sta	3,__tmp,0		; save return
	popa	3			; get high
	popa	2			; get low
	lda	0,__hireg,0		; get high of arg
	; 3:2 - 0:1

	subz	2,1,szc
	sub	3,0,skp
	adc	3,0
	sta	0,__hireg,0
	mffp	3
	jmp	@__tmp
