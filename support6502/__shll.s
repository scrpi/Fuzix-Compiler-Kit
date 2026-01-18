;
;	Left shift TOS.L by A
;
	.export __shll
	.export __shleql
	

__shll:
	jsr	__pop32sh	; tmp1/tmp2 now holds our working value
				; Y is 0
	; We should optimize bytes maybe ?
do_shll:
	and	#31
	beq	done
	tax
next:
	asl	@tmp1
	rol	@tmp1+1
	rol	@tmp2
	rol	@tmp2+1
	dex
	bne	next
done:	lda	@tmp2+1
	sta	@hireg+1
	lda	@tmp2
	sta	@hireg
	ldx	@tmp1+1
	lda	@tmp1
	rts

__shleql:
	jsr	__shld32
	jsr	do_shll
	jmp	__shst32
