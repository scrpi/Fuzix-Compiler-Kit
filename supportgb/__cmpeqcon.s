;
;	HL = DE
;
;	TODO: in the backend generate the DE load when possible as negative
;	and use ADD instead
;
	.export __cmpeqcon

__cmpeqcon:
	ld	a,h
	xor	d
	jr	nz,false
	ld	a,l
	xor	e
	jr	nz,false
	ld	hl,0
	inc	l
	ret
false:	xor	a
	ld	l,a
	ret
