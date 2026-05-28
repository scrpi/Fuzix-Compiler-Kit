;
;		TOS = lval of object HL = amount
;
	.export __postincc
	.setcpu 8080

	.code

__postincc:
	call	__popeq
	mov	a,m		; Get old value
	mov	d,a		; Old value into D
	add	e		; Plus E
	mov	m,a		; Save to pointer
	mov	l,d		; into return
	mvi	h,0		; clear upper byte of working value
	jmp	__reteq