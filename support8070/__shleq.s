;
;	(p2) << EA
;
	.export __shleq

__shleq:
	and a,=15
	bz nowork

	st a,:__tmp

	ld t,0,p2
next:
	ld ea,t
	sl ea
	ld t,ea
	dld a,:__tmp
	bnz next

	ld ea,t
	st ea,0,p2
	ret
nowork:
	ld ea,0,p2
	ret
