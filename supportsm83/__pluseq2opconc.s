;
;	(DE) += HL
;	return result
;
;	FIXME: flip this one in the compiler ?
;	FIXME: should always inline this case!
;
	.export __pluseq2opconc

__pluseq2opconc:
	ld	a,(de)
	add	l
	ld	(de),a
	ret
