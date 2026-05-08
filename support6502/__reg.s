;
;	Register ops
;
	.export __rr1addysp
	.export __rr2addysp
	.export __rr3addysp
	.export __rr4addysp
	.export __rres1
	.export __rres2
	.export __rres3
	.export __rres4
	.export __rs1subysp
	.export __rs2subysp
	.export __rs3subysp
	.export __rs4subysp
	.export __rsave1
	.export __rsave2
	.export __rsave3
	.export __rsave4

	.code

__rr1addysp:
	jsr	__addysp
__rres1:
	pha
	ldy	#0
	beq	dorr1
__rr2addysp:
	jsr	__addysp
__rres2:
	pha
	ldy	#0
	beq	dorr2
__rr3addysp:
	jsr	__addysp
__rres3:
	pha
	ldy	#0
	beq	dorr3
__rr4addysp:
	jsr	__addysp
__rres4:
	pha
	ldy	#0
	lda	(@sp),y
	sta	@reg4+1
	iny
	lda	(@sp),y
	sta	@reg4
	iny
dorr3:
	lda	(@sp),y
	sta	@reg3+1
	iny
	lda	(@sp),y
	sta	@reg3
	iny
dorr2:
	lda	(@sp),y
	sta	@reg2+1
	iny
	lda	(@sp),y
	sta	@reg2
	iny
dorr1:
	lda	(@sp),y
	sta	@reg1+1
	iny
	lda	(@sp),y
	sta	@reg1
	iny
	pla
	jmp	__addysp


;
;	Save the registers onto the stack pushing r4 first
;	Unroll ?
;
__rsave1:
	ldy	#2
	bne	rsave
__rsave2:
	ldy	#4
	bne	rsave
__rsave3:
	ldy	#6
	bne	rsave
__rsave4:
	ldy	#8
rsave:
	jsr	__subysp		; leaves X and Y unchanged
	dey
	ldx	#0
rsavel:
	lda	@reg1,x
	sta	(@sp),y
	inx
	dey
	bne	rsavel
	lda	@reg1,x
	sta	(@sp),y
nosub:
	rts

;
;	@tmp is used by subysp
;	
__rs1subysp:
	sty	@tmp+1
	jsr	__rsave1
	ldy	@tmp+1
	bne	nosub
	jmp	__subysp

__rs2subysp:
	sty	@tmp+1
	jsr	__rsave2
	ldy	@tmp+1
	bne	nosub
	jmp	__subysp

__rs3subysp:
	sty	@tmp+1
	jsr	__rsave3
	ldy	@tmp+1
	bne	nosub
	jmp	__subysp

__rs4subysp:
	sty	@tmp+1
	jsr	__rsave4
	ldy	@tmp+1
	bne	nosub
	jmp	__subysp
