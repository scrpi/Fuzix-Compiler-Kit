	.export __plusl

	.code

	; Add hireg,ea to TOS, drop TOS
__plusl:
	add ea,2,p1
	st ea,2,p1
	ld t,ea
	ld a,s
	bp skip		; carry ?
	ld ea,4,p1
	add ea,=1
addexit:
	add ea,:__hireg
	st ea,:__hireg
	ld ea,t
	ret		; and return
skip:
	ld ea,4,p1
	bra addexit
