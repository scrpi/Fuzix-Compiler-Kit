;
;	(TOS) -= BCDE
;
;	return original TOS
;
	.export __postdecl

__postdecl:
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
	ld	d,e
	pop	af
	ld	e,a
	; Now clean up
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

	
	