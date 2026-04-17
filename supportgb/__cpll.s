		.export	__negatel
		.export __cpll

__negatel:
		ld	a,h
		or	l		; will it wrap ?
		dec	hl		; doesn't touch Z
		jr	z,__cpll
		dec	bc		; ripple carry
__cpll:
		ld	a,b
		cpl
		ld	b,a
		ld	a,c
		cpl
		ld	c,a
		ld	a,h
		cpl
		ld	h,a
		ld	a,l
		cpl
		ld	l,a
		ret
