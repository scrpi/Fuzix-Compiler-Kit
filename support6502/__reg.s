;
;	Register ops
;
	.export __rr1addysp
	.export __rr2addysp
	.export __rr3addysp
	.export __rr4addysp
	.export __rs1subysp
	.export __rs2subysp
	.export __rs3subysp
	.export __rs4subysp
	.export __rsave1
	.export __rsave2
	.export __rsave3
	.export __rsave4
	.export __pushr1
	.export __pushr2
	.export __pushr3
	.export __pushr4

	.code

__rr1addysp:
	sty	@tmp
	pha
	ldy	#0
	beq	dorr1
__rr2addysp:
	sty	@tmp
	pha
	ldy	#0
	beq	dorr2
__rr3addysp:
	sty	@tmp
	pha
	ldy	#0
	beq	dorr3
__rr4addysp:
	sty	@tmp
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
	ldy	@tmp
	beq	done
	jmp	__addysp

;
;	@tmp is used by subysp
;	
__rs1subysp:
	jsr	__subysp
__rsave1:
	ldy	#1
	bne	rsave
__rs2subysp:
	jsr	__subysp
__rsave2:
	ldy	#3
	bne	rsave
__rs3subysp:
	jsr	__subysp
__rsave3:
	ldy	#5
	bne	rsave
__rs4subysp:
	jsr	__subysp
;
;	Save the registers onto the stack pushing r4 first
;	Unroll ?
;
__rsave4:
	ldy	#7
rsave:
	ldx	#0
rsavel:
	lda	@reg1,x
	sta	(@sp),y
	inx
	dey
	bne	rsavel
	lda	@reg1,x
	sta	(@sp),y
done:
	rts

__pushr1:
	lda	@reg1
	ldx	@reg1+1
	jmp	__push
__pushr2:
	lda	@reg2
	ldx	@reg2+1
	jmp	__push
__pushr3:
	lda	@reg3
	ldx	@reg3+1
	jmp	__push
__pushr4:
	lda	@reg4
	ldx	@reg4+1
	jmp	__push
