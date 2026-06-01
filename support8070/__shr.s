	.export __shr
	.export __shru

;	TOS << EA

__shru:
	ld t,2,p1
	and a,=15
	bz nowork

	st a,:__tmp

loop:
	ld ea,t
	sr ea
	ld t,ea
	dld a,:__tmp
	bnz loop
nowork:
	ld ea,t
	ret

__shr:
	ld t,2,p1
	and a,=15
	bz nowork

	st a,:__tmp

	ld ea,t
	xch a,e
	bp loop

loop1:
	ld ea,t
	sr ea
	add ea,=0x8000
	ld t,ea
	dld a,:__tmp
	bnz loop1

	ld ea,t
	ret
