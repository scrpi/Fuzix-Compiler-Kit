;
;	32bit signed division and modulus. Basically a wrapper around
;	unsigned division that figures out the signs
;
	.export __divl
	.export __reml
	.export __diveql
	.export __remeql
;
;	At this point we have the entry frame as per div32x32
;
divs32x32:
	ld	a,=0
	st	a,:__tmp2		; sign track
	ld	ea,p1
	add	ea,=2
	jsr	negcheck
	ld	ea,p1
	add	ea,=8
	jsr	negcheck
	;	Values on stack are now positive and __tmp2 holds
	;	the sign info
	jmp	div32x32
mods32x32:
	ld	ea,p1
	add	ea,=2
	jsr	negcheck
	ld	a,=0
	st	a,:__tmp2		; sign track
	ld	ea,p1
	add	ea,=8
	jsr	negcheck
	;	Values on stack are now positive and __tmp2 holds
	;	the sign info
	jmp	div32x32


negcheck:
	ld	p2,ea
	ld	a,3,p2			; sign byte
	bp	pve			; no work
	xor	a,=0xFF
	st	a,3,p2
	ld	a,2,p2
	xor	a,=0xFF
	st	a,2,p2
	ld	ea,0,p2
	xor	a,=0xFF
	st	a,0,p2
	xch	a,e
	xor	a,=0xFF
	st	a,1,p2
	xch	a,e
	;	Complement done, now do the + 1
	add	ea,=1
	st	ea,0,p2
	ld	a,s
	bp	nocarry
	ld	ea,2,p2
	add	ea,=1
	st	ea,2,p2
nocarry:
	ild	a,:__tmp2
pve:
	ret

__divl:
	ld t,ea
	ld ea,:__hireg
	push ea
	ld ea,t
	push ea				; stack working value
	jsr divs32x32
	pop p2				; clear working balue
	pop p2
	; Stack now holds return and result above
	ld ea,4,p1
	st ea,:__hireg

	ld a,:__tmp2
	and a,=1
	bz noneg
	ld ea,2,p1
	jsr __negatel
	ret
noneg:
	ld ea,2,p1
	ret

__reml:
	ld t,ea
	ld ea,:__hireg
	push ea
	ld ea,t
	push ea
	jsr mods32x32
	ld t,ea
	ld a,:__tmp2
	bz nonegr
	ld ea,t
	jsr __negatel
	bra remout
nonegr:
	ld ea,t
remout:
	pop p2
	pop p2
	ret

__diveql:
	;	2,p1 is the tos, build a working frame for the
	; 	divide call
	st ea,:__tmp
	ld ea,2,p2
	push ea
	ld ea,0,p2
	push ea
	push p2		; Pointer
	ld ea,:__hireg
	push ea
	ld ea,:__tmp
	push ea
	jsr divs32x32
	pop p2		; discard stacked
	pop p2
	pop p2		; pointer back
	ld a,:__tmp2
	and a,=1	; signs differed (1 negation)
	bnz negdiv

	ld ea,4,p1
	st ea,:__hireg
	st ea,2,p2	; save high
	ld ea,2,p1
	st ea,0,p2	; and save it
	ret

negdiv:
	pop p2
	pop p2
	pop p2		; pointer back
	ld ea,4,p1
	st ea,:__hireg
	ld ea,2,p1
	jsr __negatel
	st ea,0,p2
	ld t,ea
	ld ea,:__hireg
	st ea,2,p2
	ld ea,t
	ret

__remeql:
	;	Build a working frame for the
	; 	divide call
	st ea,:__tmp
	ld ea,2,p2
	push ea
	ld ea,0,p2
	push ea
	push p2		; pointer
	ld ea,:__hireg
	push ea
	ld ea,:__tmp
	push ea
	jsr mods32x32
	pop p2
	pop p2
	pop p2		; pointer back

	; return is in hireg:ea
	ld t,ea
	ld a,:__tmp2
	bz nochange
	ld ea,t
	jsr __negatel
	ld t,ea
nochange:
	ld ea,t
out:
	st ea,0,p2
	ld ea,:__hireg
	st ea,2,p2
	ld ea,t
	ret

