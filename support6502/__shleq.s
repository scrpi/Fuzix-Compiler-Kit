;
;	(TOS) << A
;
	.export __shleq
;

__shleq:
	jsr	__poptmp
	; Y is set to 0
	and	#15
	tax
	beq	out
	lda	(@tmp),y
	sta	@tmp1
	iny
	lda	(@tmp),y
	sta	@tmp1+1
loop:
	asl	@tmp1
	rol	@tmp1+1
	dex
	bne	loop
done:
	lda	@tmp1+1
	sta	(@tmp),y
	tax
	dey
	lda	@tmp1
	sta	(@tmp),y
	rts

out:
	iny
	lda	(@tmp),y
	tax
	dey
	lda	(@tmp),y
	rts

