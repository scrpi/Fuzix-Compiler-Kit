	.setcpu	4
	.export	__switchc

	.code

__switchc:
	lda	(x+)	; count
	bz	found	; No entries then next word is the vector
	xfr	al,ah	; use al for working, use ah for counter
swent:
	ldab	(x+)	; value
	subb	bl,al	; compare, preserving B
	bz	found	; success
	inx		; skip over address
	inx
	dcr	ah	; count down through loop
	bnz	swent
found:
	ldx	(x)	; grab jump address
	jmp	(x)	; go
	; ?? TODO can we jmp ((x))
