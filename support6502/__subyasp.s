;
;	Adjust stack frame by YA bytes the other direction
;	Only used when generating a frame so can destroy XA
;
	.export __subyasp

	.code

__subyasp:
	sta @tmp
	sty @tmp+1
	lda @sp
	sec
	sbc @tmp
	sta @sp
	lda @sp+1
	sbc @tmp+1
	sta @sp+1
	rts
