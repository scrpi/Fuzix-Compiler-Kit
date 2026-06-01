;	
;	Division 32 bit unsigned
;
;	FIXME: needs adjusting for new stack layout
;
	.export __divul
	.export __remul
	.export __divequl
	.export __remequl

__divul:
	ld t,ea
	ld ea,:__hireg
	push ea
	ld ea,t
	push ea
	jsr div32x32
	ld ea,8,p1
	st ea,:__hireg
	ld ea,6,p1
	pop p2
	pop p2
	ret

__remul:
	ld t,ea
	ld ea,:__hireg
	push ea
	ld ea,t
	push ea
	jsr div32x32
	pop p2
	pop p2
	; Result is in hireg/ea
	ret

__divequl:
	;	2,p1 is the tos, build a working frame for the
	; 	divide call
	st ea,:__tmp
	ld ea,2,p2
	push ea
	ld ea,0,p2
	push ea
	push p2		; Pointer to write back
	ld ea,:__hireg
	push ea
	ld ea,:__tmp
	push ea
	jsr div32x32
	pop ea
	pop ea		; discard divisor
	pop p2		; pointer to write into
	pop ea		; result low
	ld t,ea		; save
	pop ea		; actual result high
	st ea,:__hireg
	st ea,2,p2
	ld ea,t
	st ea,0,p2
	ret

__remequl:
	;	2,p1 is the tos, build a working frame for the
	; 	divide call
	st ea,:__tmp
	ld ea,2,p2
	push ea
	ld ea,0,p2
	push ea
	push p2		; Pointer to write back
	ld ea,:__hireg
	push ea
	ld ea,:__tmp
	push ea
	jsr div32x32
	ld t,ea
	pop ea
	pop ea
	pop p2
	pop ea
	pop ea
	ld ea,:__hireg
	st ea,2,p2
	ld ea,t
	st ea,0,p2
	ret
