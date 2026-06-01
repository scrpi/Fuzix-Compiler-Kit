	.export __orl

__orl:
	or a,2,p1
	xch a,e
	or a,3,p1
	xch a,e
	ld t,ea
	ld ea,:__hireg
	or a,4,p1
	xch a,e
	or a,5,p1
	xch a,e
	st ea,:__hireg
	ld ea,t
	ret
