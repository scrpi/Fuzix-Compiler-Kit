;
;	(TOS) << A
;
	.export __shleqc
;

__shleqc:
	jsr	__poptmp
	and	#7
	tax
	beq	out
	lda	(@tmp),y
loop:
	asl	a
	dex
	bne	loop
	sta	(@tmp),y
	rts
out:
	lda	(@tmp),y
	rts
