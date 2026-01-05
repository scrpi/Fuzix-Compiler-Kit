;
;	(TOS) * r2-r5
;
	.export __muleql
	.export __muleqlu

	.code

__muleql:
__muleqlu:
	call	@__pop10	; pointer into r10 x r11
	add	%3,r11
	adc	%0,r10		; point to end of block
	push	r10
	push	r11

	lda	*r11
	mov	a,r13
	decd	r11
	lda	*r11
	mov	a,r12
	decd	r11
	lda	*r11
	mov	a,b
	decd	r11
	lda	*r11
	movd	b,r11		; into r10/11/12/13
	
	call	@__mull_op	; do the maths (eats r10-r10, returns r2-r5)

	pop	r11
	pop	r10		; pointing to low byte
	mov	r5,a
	sta	*r11
	decd	r11
	mov	r4,a
	sta	*r11
	decd	r11
	mov	r3,a
	sta	*r11
	decd	r11
	mov	r2,a
	sta	*r11
	rets

