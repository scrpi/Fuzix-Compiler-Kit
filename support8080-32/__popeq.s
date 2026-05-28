;
;	Helper for 32bit eq ops as they are all a bit of a pain
;	otherwise. Also means we've got one spot to fudge for
;	different targets
;
	.export __popeq
	.export __reteq
;
;
;	7-4:	large model address
;	3-2:	return to eqop's caller
;	1-0:	return to our caller
;
__popeq:
	xchg
	lxi	h,6
	dad	sp
	;	HL now points at the stacked address bank byte
	mov	a,m
	call	__bankswitch
	dcx	h
	mov	a,m
	dcx	h
	mov	l,m
	mov	h,a
	;	DE = user data, HL = pointer, bank is set
	ret
;	This is jumped to. TOS is the return address, 4 bytes above it to
;	clean up. Result is in HL
__reteq:
	pop	d
	pop	psw
	pop	psw
	push	d
	ret
