;
;	32bit compare used to build all the flag checks for
;	all the long comparisons. Idea taken from cc65 but we implement
;	it quite differently as we eventually want to shortcircuit as much
;	as possible though directly storing/working off tmp/tmp1
;

	.export __cceql
	.export __ccnel
	.export __ccgtl
	.export __ccgteql
	.export __ccgtul
	.export __ccgtequl
	.export __ccltl
	.export __cclteql
	.export __ccltul
	.export __ccltequl


__lcmp:
	jsr	__pop32
	; We are now comparing hireg:XA with tmp1:tmp
	sta	@tmp2
	lda	@hireg+1
	sec
	sbc	@tmp1+1
	bne	signs
	lda	@hireg
	cmp	@tmp1
	bne	differ
	txa
	cmp	@tmp+1
	bne	differ
	lda	@tmp2
	cmp	@tmp
	beq	done
differ:
	bcs	clear_n
	lda	#0xFF
done:	rts

clear_n:
	lda	#0x01
	rts

;
;	The top of the comparison is different as we need to get the
;	signed comparison checks right too
;
signs:
	bvc	done
	eor	#0xFF		; clear N and Z
	ora	#0x01
	rts

;
;	Condition checks
;
is_eq:
	beq	ret1
ret0:
	lda	#0
	tax
	rts
is_ne:
	bne	ret1
	lda	#0
	tax
	rts
is_lt:
	beq	ret0
is_le:
	bmi	ret0
ret1:
	ldx	#0
	lda	#1		; so that Z is correct
	rts

is_ge:
	beq	ret1
is_gt:
	bmi	ret1
	lda	#0
	tax
	rts

is_ult:
	beq	ret0
is_ule:
	ldx	#0
	txa
	rol	a
	rts

is_uge:
	beq	ret1
is_ugt:
	bcc	ret1
	lda	#0
	tax
	rts

__ccgtl:
	jsr	__lcmp
	jmp	is_gt

__ccgtul:
	jsr	__lcmp
	jmp	is_ugt

__ccgteql:
	jsr	__lcmp
	jmp	is_ge

__ccgtequl:
	jsr	__lcmp
	jmp	is_uge

__ccltl:
	jsr	__lcmp
	jmp	is_lt

__ccltul:
	jsr	__lcmp
	jmp	is_ult

__cclteql:
	jsr	__lcmp
	jmp	is_le

__ccltequl:
	jsr	__lcmp
	jmp	is_ule

__cceql:
	jsr	__lcmp
	jmp	is_eq

__ccnel:
	jsr	__lcmp
	jmp	is_ne
