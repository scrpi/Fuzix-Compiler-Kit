	.export __xoreql

;	UNUSED

;	(p2) & hireg:ea

__xoreql:
	xor a,0,p2
	xch a,e
	xor a,1,p2
	xch a,e
	st ea,0,p2
	ld t,ea
	ld ea,:__hireg
	xor a,2,p2
	xch a,e
	xor a,3,p2
	xch a,e
	st ea,2,p2
	st ea,:__hireg
	ld ea,t
	ret
