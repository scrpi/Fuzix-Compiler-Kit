;
;	(TOS) -= BCHL
;
;	return original TOS
;
	.export __postdecl

__postdecl:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,(hl)
	push	af		; no room otherwise
	sub	e
	ldi	(hl),a
	ld	a,(hl)
	ld	e,a
	sbc	d
	ldi	(hl),a
	ld	a,(hl)
	ld	d,a
	sbc	c
	ldi	(hl),a
	ld	a,(hl)
	ld	c,a
	sbc	b
	ld	(hl),a
	; Sort out saved bits
	ld	b,c
	ld	c,d
	ld	h,e
	pop	af
	ld	l,a
	; Now clean up
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

	
	