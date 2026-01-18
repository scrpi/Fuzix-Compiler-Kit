;
;	Right shift TOS.L by A
;
;	TODO:
;	should spot 8/16/24 and do register moves except for the final bits
;
	.export __shrl
	.export __shrul
	.export __shreql
	.export __shrequl

__shrl:
	jsr	__pop32sh	; tmp1/tmp2 now holds our working value
				; Y is 0
do_shrl:
	; We should optimize bytes maybe ?
	and	#31
	beq	done
	ldx	@tmp2+1		; grab high byte
	bpl	viau		; as unsigned
	; Need to set upper bits
	tax
next:
	sec
	ror	@tmp2+1
	ror	@tmp2
	ror	@tmp1+1
	ror	@tmp1
	dex
	bne	next
done:	lda	@tmp2+1
	sta	@hireg+1
	lda	@tmp2
	sta	@hireg
	ldx	@tmp1+1
	lda	@tmp1
	rts

__shrul:
	jsr	__pop32sh
do_shrul:
	and	#31
	beq	done
viau:
	tax
nextu:
	lsr	@tmp2+1
	ror	@tmp2
	ror	@tmp1+1
	ror	@tmp1
	dex
	bne	nextu
	beq	done

__shreql:
	jsr	__shld32
	jsr	do_shrl
	jmp	__shst32

__shrequl:
	jsr	__shld32
	jsr	do_shrul
	jmp	__shst32
