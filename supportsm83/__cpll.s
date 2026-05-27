		.export	__negatel
		.export __cpll

__negatel:
		ld	a,d
		or	e		; will it wrap ?
		dec	de		; doesn't touch Z
		jr	nz,__cpll
		dec	bc		; ripple carry
__cpll:
		ld	a,b
		cpl
		ld	b,a
		ld	a,c
		cpl
		ld	c,a
		ld	a,d
		cpl
		ld	d,a
		ld	a,e
		cpl
		ld	e,a
		ret
