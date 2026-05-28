;
;		(TOS) /= L
;

	.export __remeqc
	.setcpu 8080
	.code

__remeqc:
	call	__popeq
	; Now we are doing (HL) * DE
	push	d
	mov	e,m
	xthl	; swap address with stacked value
	xchg	; swap them back as we divide by DE
	; We are now doing HL / DE and the address we want is TOS
	call	__sex
	xchg
	call	__sex
	xchg
	call	__remde
	; Return is in HL
	pop	d
	mov	a,l
	stax	d
	jmp	__reteq
