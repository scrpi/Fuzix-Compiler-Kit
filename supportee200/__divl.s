;
;	Do a 32bit divide signed
;
	.setcpu	4
	.export __divl
	.export __reml
	.code

__divl:
	stx	(-s)	; save return info
	xfr	y,x
	stx	(-s)	; save Y to free it up for private use
	stb	(-s)	; stack the value
	ldb	(__hireg)
	stb	(-s)
	lda	1
	jsr	signfix	; Y is sign info and saved by the jsr
	jsr	div32x32
	; Result is in the TOS value
	lda	10(s)
	ldb	12(s)
dosign:
	ori	y,y
	bz	noneg
	ivr	a
	ivr	b	; negate result
	inr	b
	bnz	norip
	inr	a
norip:
noneg:
	sta	(__hireg)
	lda	4	; clean up value we pushed
	add	a,s
	ldx	(s+)	; get back Y
	xfr	x,y
	ldx	(s+)	; get back return info
	add	a,s	; clean up caller argument (a is still 4)
	rsr

__reml:
	stx	(-s)	; save return info
	xfr	y,x
	stx	(-s)	; save Y to use for working sign info
	stb	(-s)
	ldb	(__hireg)
	stb	(-s)
	cla
	jsr	signfix2
	jsr	div32x32
	bra	dosign

; Fix signs for divide, turn both positive and count signs
signfix:
	clr	y
	lda	2(s)	; value just pushed
	bp	nosh1
	dcr	y
; Comm part of the fixup. For rem we don't care about the sign of the
; second value for sign fixup
sfcommon:
	ldb	4(s)
	ivr	b
	iva
	inr	b
	bnz	norip2
	ina
norip2:	sta	2(s)
	stb	4(s)
nosh1:
	lda	12(s)
	bp	nosh2
	ldb	14(s)
	ivr	b
	iva
	inr	b
	bnz	norip3
	ina
norip3:	sta	12(s)
	stb	14(s)
	inr	y
nosh2:
	rsr
; Version for remainder
signfix2:
	clr	y
	lda	2(s)
	bp	nosh1
	bra	sfcommon
