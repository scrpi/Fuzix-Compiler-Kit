;
;	HL >= DE
;
	.export __cmpgteqconu
	.export __cmpgtequ
	.export	__ccltequ

;	TOS <= DE
__ccltequ:
	pop	bc
	pop	hl
	push	bc
	jr	__cmpgteqconu
;	DE >= (HL)
__cmpgtequ:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	
;	DE >= HL
__cmpgteqconu:
	ld 	a,d
	cp	h
	jr	c, false
	jr	nz, true
	ld	a,e
	cp	l
	jr	nc, true
false:	xor	a
	ld	d,a
	ld	e,a
	ret
true:
	ld	de,0
	inc	e
	ret
