;
;	(TOS) = BCHL
;
;	Probably ought to be inlined and do LREF LSTORE etc for
;	32bit forms
;
	.export __assignl

__assignl:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),c
	inc	hl
	ld	(hl),b
	; Return correct value as well
	ld	l,e
	ld	h,d
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

