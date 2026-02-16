;
;	32bit multiply
;
	.export __mull
	.export __mulul
	.export __muleql
	.export __mulequl



__muleql:
__mulequl:
	;	(TOS) *= hireg;XA
	sta	@tmp2
	stx	@tmp2+1
	ldy	#1
	lda	(@sp),y
	sta	@tmp5+1
	dey
	lda	(@sp),y
	sta	@tmp5
	; Y is now 0 and @tmp3 is the pointer we need to load @tmp1:@tmp
	lda	(@tmp5),y
	sta	@tmp
	iny
	lda	(@tmp5),y
	sta	@tmp+1
	iny
	lda	(@tmp5),y
	sta	@tmp1
	iny
	lda	(@tmp5),y
	sta	@tmp1+1
	jsr	mult32
	; hireg:xa is the result (also in tmp2 and we use that fact)
	; tmp5 is still the pointer
	ldy	#3
	lda	@hireg+1
	sta	(@tmp5),y
	dey
	lda	@hireg
	sta	(@tmp5),y
	dey
	lda	@tmp2+1
	sta	(@tmp5),y
	tax
	dey
	lda	@tmp2
	sta	(@tmp5),y
	; hireg:xa is also the result needed
	jmp	__incsp2

__mull:
__mulul:
	jsr	__pop32		; (TOS) into @tmp/@tmp1
;
;	Internal 32bit multiply work
;
;	Computes hireg:xa * @tmp1:@tmp
;	Returns hireg:xa
;
	sta	@tmp2
	stx	@tmp2+1
;
;	Utilisation
;	@tmp1:@tmp		argument1
;	@tmp2:			holds the entry XA during calculation
;	@tmp3:@tmp4		32bit working value
;
mult32:
	lda	#0
	sta	@tmp3+2
	sta	@tmp3+1
	sta	@tmp3
	ldy	#32		; bits to do
next:	lsr	@tmp3+2
	ror	@tmp3+1
	ror	@tmp3
	ror	a		; rotate 32bits right one
	;	Now slide into result
	ror	@hireg+1
	ror	@hireg
	ror	@tmp2+1
	ror	@tmp2
	bcc	no_add
	;	32 bit add of arg2 to the working value
	clc
	adc	@tmp
	tax
	lda	@tmp+1
	adc	@tmp3
	sta	@tmp3
	lda	@tmp+2
	adc	@tmp3+1
	sta	@tmp3+1
	lda	@tmp+3
	adc	@tmp3+2
	sta	@tmp3+2
	txa
no_add:	dey
	bpl	next
	;	At this point the result is in hireg:tmp2
	lda	@tmp2
	ldx	@tmp2+1
	rts

