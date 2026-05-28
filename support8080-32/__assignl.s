;
;	Assign the value in hireg:HL to lval at tos.
;
	.export __assignf
	.export __assignl
	.export	__assign0l
	.setcpu 8080

	.code

__assignf:			; for assign the same as l
__assignl:
	call	__popeq		; hireg:de is now our value, bank is set
	mov	m,e		; HL is our pointer
	inx	h
	mov	m,d		; Save low word
	inx	h
	push	d		; for return
	xchg
	lhld	__hireg
	xchg
	; de is now the high bytes
	mov	m,e
	inx	h
	mov	m,d
	pop	h		; saved low word
	jmp	__reteq

; Assign 0L to lval in HL (__hireg is bank)
__assign0l:
	call	__bankswitchhr
	xra	a
	mov	m,a
	inx	h
	mov	m,a
	inx	h
	mov	m,a
	inx	h
	mov	m,a
	mov	h,a
	mov	l,a
	shld	__hireg		; clear hireg
	ret
