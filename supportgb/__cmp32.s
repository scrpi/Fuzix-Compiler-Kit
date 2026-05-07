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
	jr	z, __cmp32u
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
	ld	a,e
	cp	(hl)
	ret


__ccnel:
	call	__cmp32utop
	jr	z,false
	jr	true

__cceql:
	call	__cmp32utop
	jr	z,true
false:
	pop	hl
	add	sp,4
	xor	a
	ld	d,a
	ld	e,a
	jp	(hl)
true:	pop	hl
	add	sp,4
	ld	de,0
	inc	e
	jp	(hl)

__ccltul:
	call	__cmp32utop
	jr	z,false
	jr	c,false
	jr	true

__ccgtequl:
	call	__cmp32utop
	jr	c,true
	jr	z,true
	jr	false

__ccltequl:
	call	__cmp32utop
	jr	c,false
	jr	true

__ccgtul:
	call	__cmp32utop
	jr	c,true
	jr	false

__ccltl:
	call	__cmp32top
	jr	z,false
	jr	c,false
	jr	true

__ccgteql:
	call	__cmp32top
	jr	c,true
	jr	z,true
	jr	false

__cclteql:
	call	__cmp32top
	jr	c,true
	jr	false

__ccgtl:
	call	__cmp32top
	jr	c,true
	jr	false
