;
;	Adjust stack frame by Y bytes the other direction
;	Must preserve Y
;
	.export __sub4sp
	.export __sub3sp
	.export __sub2sp
	.export __sub1sp
	.export __subysp

	.code

__sub4sp:
	ldy #4
	bne __subysp
__sub3sp:
	ldy #3
	bne __subysp
__sub2sp:
	ldy #2
	bne __subysp
__sub1sp:
	ldy #1
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