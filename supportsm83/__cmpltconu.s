;
;	16bit unsigned comparisons
;
	.export __ccgtu
	.export __cmpltu
	.export __cmpltconu

;	TOS > DE
__ccgtu:
	pop	bc		; ok to eat BC
	pop	hl		; args reverse so this is gt not lt
	push	bc		; restore return addr
	jr	__cmpltconu

;	DE < (HL)
__cmpltu:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	

;	DE < HL
__cmpltconu:
	ld 	a,d
	cp	h
	jr	c, true
	jr	nz, false
	ld	a,e
	cp	l
	jr	nc, false
true:
	ld	de,0
	inc	e
	ret
false:	xor	a
	ld	d,a
	ld	e,a
	ret
