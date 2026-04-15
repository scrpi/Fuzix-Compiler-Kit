;
;	HL != DE
;
;	TODO: in the backend generate the DE load when possible as negative
;	and use ADD instead
;
	.export __cmpnecon

__cmpnecon:
	ld	a,h
	xor	d
	jr	nz,true
	ld	a,l
	xor	e
	jr	nz,true
	ld	hl,0
	; Z is already set
	ret
true:	ld	hl,1	; already NZ
	ret
