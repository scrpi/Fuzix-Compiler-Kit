	.setcpu	4
	.export	__switch

	.code

;	Table is in X value is in B
__switch:
	xfr	y,a	; Save old Y
	sta	(-s)
	lda	(x+)	; count
	bz	found	; No entries then next word is the vector
	xay		; count into Y
swent:
	lda	(x+)	; value
	sub	b,a	; compare, preserving B
	bz	found	; success
	inx		; skip over address
	inx
	dcr	y	; count down through loop
	bnz	swent
found:
	lda	(s+)	; restore Y
	xay
	ldx	(x)	; grab jump address
	jmp	(x)	; go
	; ?? TODO can we jmp ((x))
