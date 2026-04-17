;
;	32bit comparisons. We do these via a helper for compactness
;
	.export __ccnel
	.export __cceql
	.export __ccltul
	.export __ccgtequl
	.export __ccgtul
	.export __ccltequl
	.export __ccltl
	.export __ccgteql
	.export __ccgtl
	.export __cclteql

;	Compare BCDE with (HL)
;	On entry pointer HL is to high (top byte)

__cmp32top:
	ld	hl,sp+7
__cmp32:
	ld	a,b
	xor	(hl)
	bit	7,a
	; If the signs match then do an unsigned compare
	jr	nz, __cmp32u
	bit	7,b
	scf
	ret	nz
	xor	a		; clears C
	inc	a		; force NZ
	ret
__cmp32utop:
	ld	hl,sp+7
__cmp32u:
	ld 	a,b
	cp	(hl)
	ret	nz
	dec	hl
	ld	a,c
	cp	(hl)
	ret	nz
	dec	hl
	ld	a,d
	cp	(hl)
	ret	nz
	dec	hl
	cp	(hl)
	ret


__ccnel:
	call	__cmp32utop
	ld	hl,0
	ret	z		; equality is false
	inc	l
	ret			; was not equal

__cceql:
	call	__cmp32utop
	jr	z,true
false:
	pop	de
	add	sp,4
	push	de
	xor	a
	ld	h,a
	ld	l,a
	ret
true:	pop	de
	add	sp,4
	push	de
	ld	hl,0
	inc	hl
	ret

__ccltul:
	call	__cmp32utop
	jr	c,true
	jp	false

__ccgtequl:
	call	__cmp32utop
	jr	nc,true
	jp	false

__ccltequl:
	call	__cmp32utop
	jr	c,true
	jr	z,true
	jp	false

__ccgtul:
	call	__cmp32utop
	jr	c,false
	jr	z,false
	jp	true

__ccltl:
	call	__cmp32top
	jr	c,true
	jp	false

__ccgteql:
	call	__cmp32top
	jr	nc,true
	jp	false

__cclteql:
	call	__cmp32top
	jr	c,true
	jr	z,true
	jp	false

__ccgtl:
	call	__cmp32top
	jr	c,false
	jr	z,false
	jp	true
