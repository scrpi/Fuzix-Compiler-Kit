
;	TOS.L >> EA
;
	.export __shrul
	.export __shrequl
	.export __shrl
	.export __shreql

use_shrul:
	ld ea,t
__shrul:
	and a,=31
	bz nowork
	ld t,ea
	and a,=16
	bnz slide16
test8:
	ld ea,t
	and a,=8
	bnz bytes
final:
	ld ea,t
	and a,=7
	bz nowork
	st a,:__tmp
; Right shifting 32bit

loop:
	add a,=0		; clear carry
	ld a,5,p1
	rrl a
	st a,5,p1
	ld a,4,p1
	rrl a
	st a,4,p1
	ld a,3,p1
	rrl a
	st a,3,p1
	ld a,2,p1
	rrl a
	st a,2,p1
	dld a,:__tmp
	bnz loop
nowork:
	ld ea,4,p1
	st ea,:__hireg
	ld ea,2,p1
	ret

slide16:
	ld ea,4,p1
	st ea,2,p1
	ld ea,=0
	st ea,4,p1
	ld ea,t
	and a,=15
	ld t,ea
	bra test8
bytes:
	ld a,3,p1
	st a,2,p1
	ld ea,4,p1
	st ea,3,p1
	ld a,=0
	st a,5,p1
	bra final

__shrl:
	ld t,ea
	ld a,5,p1
	bp use_shrul
	ld ea,t
;
;	Negative forms
;
	and a,=31
	bz nowork
	ld t,ea
	and a,=16
	bnz slide16_m
test8_m:
	ld ea,t
	and a,=8
	bnz bytes_m
final_m:
	ld ea,t
	and a,=7
	bz nowork
	st a,:__tmp
; Right shifting 32bit

loop_m:
	ld a,5,p1
	rrl a
	or a,=0x80
	st a,5,p1
	ld a,4,p1
	rrl a
	st a,4,p1
	ld a,3,p1
	rrl a
	st a,3,p1
	ld a,2,p1
	rrl a
	st a,2,p1
	dld a,:__tmp
	bnz loop_m
	bra nowork
slide16_m:
	ld ea,4,p1
	st ea,2,p1
	ld ea,=0xFFFF
	st ea,4,p1
	ld ea,t
	and a,=15
	ld t,ea
	bra test8_m
bytes_m:
	ld a,3,p1
	st a,2,p1
	ld ea,4,p1
	st ea,3,p1
	ld a,=0xFF
	st a,5,p1
	bra final_m

; (p2) >>= hireg:EA

__shrequl:
	push p2
	ld t,ea
	ld ea,2,p2
	push ea
	ld ea,0,p2
	push ea
	ld ea,t
	jsr __shrul
	pop p2
	pop p2
	pop p2
	st ea,0,p2
	ld t,ea
	ld ea,:__hireg
	st ea,2,p2
	ld ea,t
	ret

__shreql:
	push p2
	ld t,ea
	ld ea,2,p2
	push ea
	ld ea,0,p2
	push ea
	ld ea,t
	jsr __shrl
	; discard working
	pop p2
	pop p2
	; get pointer back
	pop p2
	st ea,0,p2
	ld t,ea
	ld ea,:__hireg
	st ea,2,p2
	ld ea,t
	ret
