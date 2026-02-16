;
;	Unlike the 680x series it's very difficult to make this re-entrant
;	so we don't bother. We just try and keep all our support code using
;	the one block of temporaries

	.export __divul
	.export __remul
	.export __divl
	.export __reml
	.export __divequl
	.export __remequl
	.export __diveql
	.export __remeql
;
;
;	tmp1:tmp / @hireg:XA using tmp4 for XA and tmp2/3 as working
;	Could do with optimizations for 6502
;

div32x32:
	sta	@tmp4
	stx	@tmp4+1
	lda	#0
	sta	@tmp2
	sta	@tmp2+1
	sta	@tmp3
	sta	@tmp3+1
	ldy	#32		; Number of iterations
loop:	; Shift dividend left and set bit 0 assuming that
	; R >= D
	clc
	rol	@tmp
	rol	@tmp+1
	rol	@tmp1
	rol	@tmp1+1
	; N(i) is now in carry
	; R <<= 0; R(0) = N(i)_
	; Capture into working register
	rol	@tmp2
	rol	@tmp2+1
	rol	@tmp3
	rol	@tmp3+1
	; Do a 32bit subtract but skip writing back the value
	; We can't do this nicely like the 6800 as we only have
	; one 8bit accumulator
	lda	@tmp2
	cmp	@tmp4
	lda	@tmp2+1
	sbc	@tmp4+1
	lda	@tmp3
	sbc	@hireg
	lda	@tmp3+1
	sbc	@hireg+1
	;
	;	We did R - D
	;
	bmi	next
	;
	;	It fitted, redo for real
	;
	sec
	lda	@tmp2
	sbc	@tmp4
	sta	@tmp2
	lda	@tmp2+1
	sbc	@tmp4+1
	sta	@tmp2+1
	lda	@tmp3
	sbc	@hireg
	sta	@tmp3
	lda	@tmp3+1
	sbc	@hireg+1
	sta	@tmp3+1
	;
	;	Set R(0) - currently will be 0 so can just inc
	;
	inc	@tmp
next:
	; Round we go
	dey
	bne	loop
	;
	;	At this point we have both the division and remainder
	;	computed for the caller to extract
	rts

fetch:
	ldy	#1
	lda	(@sp),y
	sta	@tmp4+1
	dey
	lda	(@sp),y
	sta	@tmp4
	; @tmp4 is the pointer, now load that into tmp2/tmp3
	lda	(@tmp4),y
	sta	@tmp
	iny
	lda	(@tmp4),y
	sta	@tmp+1
	iny
	lda	(@tmp4),y
	sta	@tmp1
	iny
	lda	(@tmp4),y
	sta	@tmp1+1
	ldy	#0
	rts

	;
__divequl:
	jsr	fetch
	jsr	dodivul
store:	; Result is in hireg/XA top of stack is pointer
	jsr	__poptmp
	; @tmp is pointer Y is 0
	sta	(@tmp),y
	iny
	pha
	txa
	sta	(@tmp),y
	iny
	lda	@hireg
	sta	(@tmp),y
	iny
	lda	@hireg+1
	sta	(@tmp),y
	pla
	rts

__remequl:
	jsr	fetch
	jsr	domodul
	jmp	store

__divul:
	;	(TOS) / hireg:XA
	jsr	__pop32
dodivul:
	;	tmp1/tmp is now set up
	jsr	div32x32
	;	pull the result into the right place
divout:
	lda	@tmp1+1
	sta	@hireg+1
	lda	@tmp1
	sta	@hireg
	ldx	@tmp+1
	lda	@tmp
	rts

__remul:
	;	(TOS) % hireg:XA
	jsr	__pop32
domodul:
	;	tmp1/tmp is now set up
	jsr	div32x32
	;	pull the result into the right place
modout:
	lda	@tmp3+1
	sta	@hireg+1
	lda	@tmp3
	sta	@hireg
	ldx	@tmp2+1
	lda	@tmp2
	rts


negtmp1:
	;	Need to negate tmp1:tmp
	tay
	lda	@tmp
	clc
	eor	#0xFF
	adc	#1
	sta	@tmp
	lda	@tmp+1
	eor	#0xFF
	adc	#0
	sta	@tmp+1
	lda	@tmp1
	eor	#0xFF
	adc	#0
	sta	@tmp1
	lda	@tmp1+1
	eor	#0xFF
	adc	#0
	sta	@tmp1+1
	tya
	rts

__divl:
	jsr	__pop32
dodivl:
	;	Returns with Y = 0
	sty	@tmp5
	;	This is like unsigned divide except we have to muck about
	;	with sign handling
	ldy	@hireg+1
	bpl	signok1
	;	Negate hireg:xa and remember we did so
	jsr	__negatel
	inc	@tmp5
signok1:
	ldy	@tmp1+1
	bpl	signok2
	jsr	negtmp1
	; Remember the second negation
	inc	@tmp5
signok2:
	jsr	div32x32
	ror	@tmp5
	;	No change needed
	bcc	divout
	;	Get into hireg:xa
	jsr	divout
	jmp	__negatel

__reml:
	jsr	__pop32
domodl:
	sty	@tmp5
	ldy	@hireg+1
	bpl	signok3
	;	negate hireg:xa
	jsr	__negatel
	;	remember division by negative
	inc	@tmp5
signok3:
	ldy	@tmp1+1
	bpl	signok4
	;	negate but not relevant to final sign
	jsr	negtmp1
signok4:
	jsr	div32x32
	ldy	@tmp5
	beq	modout
	;	Get the modulus and negate it
	jsr	modout
	jmp	__negatel

__diveql:
	jsr	fetch
	jsr	dodivl
	jmp	store

__remeql:
	jsr	fetch
	jsr	domodl
	jmp	store

