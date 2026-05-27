;
;	16bit unsigned comparisons
;
	.export __ccltu
	.export __cmpgtu
	.export __cmpgtconu

;	TOS < DE
__ccltu:
	pop	bc
	pop	hl		; args reverse so this is gt not lt
	push	bc
	jr	__cmpltconu

;	DE > (HL)
__cmpgtu:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	

;	DE > HL
__cmpgtconu:
	ld 	a,h
	cp	d
	jr	c, true
	jr	nz, false
	ld	a,l
	cp	e
	jr	nc, false
true:
	ld	de,0
	inc	e
	ret
false:	xor	a
	ld	d,a
	ld	e,a
	ret
