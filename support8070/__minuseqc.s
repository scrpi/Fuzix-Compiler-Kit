	.export __minuseqc

;	UNUSED

;	(TOS.B) += A

__minuseqc:
	st	a,:__tmp
	ld	a,0,p2
	sub	a,:__tmp
	st	a,0,p2
	ret
