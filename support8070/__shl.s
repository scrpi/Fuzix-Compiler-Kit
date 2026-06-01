	.export __shl
	.export __shlc		; TODO - is this worth having native ?

;	TOS << EA

__shlc:
__shl:
	ld t,2,p1

	and a,=15
	bz nowork

	st a,:__tmp
loop:
	ld ea,t
	sl ea
	ld t,ea
	dld a,:__tmp
	bnz loop
nowork:
	ld ea,t
	ret
