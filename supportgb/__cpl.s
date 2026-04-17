		.export	__negate
		.export __cpl

__negate:
		dec	h
__cpl:
		ld	a,h
		cpl
		ld	h,a
		ld	a,l
		cpl
		ld	l,a
		ret
