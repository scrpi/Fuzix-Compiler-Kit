;
;	(p2) >> EA
;
	.export __shreq
	.export __shrequ

__shrequ:
	ld t,0,p2
	and a,=15	; wrap by bit count
	st a,:__tmp
	bz noshift
loop:
	ld ea,t
	sr ea
	ld t,ea
	dld a,:__tmp
	bnz loop
noshift:
	ld ea,t
	st ea,0,p2
	ret

via_u:
	xch a,e
	ld t,ea
	bra loop

__shreq:
	ld t,0,p2
	and a,=15	; wrap by bit count
	st a,:__tmp
	bz noshift
	ld ea,t
	xch a,e
	bp loop
loop1:
	ld ea,t
	sr ea
	xch a,e
	or a,=0x80
	xch a,e
	ld t,ea
	dld a,:__tmp
	bnz loop1
	ld ea,t
	st ea,0,p2
	ret
