		.export	__negate
		.export __cpl

__negate:
		dec	de
__cpl:
		ld	a,d
		cpl
		ld	d,a
		ld	a,e
		cpl
		ld	e,a
		ret
