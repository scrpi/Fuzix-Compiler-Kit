;
;	(TOS) = BCDE
;
;	Probably ought to be inlined and do LREF LSTORE etc for
;	32bit forms
;
	.export __assignf
	.export __assignl

__assignf:
__assignl:
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
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

