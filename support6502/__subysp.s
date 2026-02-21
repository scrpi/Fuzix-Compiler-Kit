;
;	Adjust stack frame by Y bytes the other direction
;	Must preserve Y
;
	.export __subysp

	.code

__subysp:
	pha
	sty @tmp
	lda @sp
	sec
	sbc @tmp
	sta @sp
	bcs done
	dec @sp+1
done:	pla
	rts	