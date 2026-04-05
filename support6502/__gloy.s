;
;	Get 16bit local at offset Y
;
	.export __gloy
	.export __gloy0
	.export __pushly
	.export __pushly0
	.export __gloytmp
	.export __gloytmp0
	.export __gloytmpd1
	.export __gloytmpd2
	.export __pushyd1
	.export __pushyd2

	.code
__gloy0:
	ldy #1
__gloy:
	lda (@sp),y
	tax
	dey
	lda (@sp),y
	rts

__pushly0:
	ldy #1
__pushly:
	jsr __gloy
	jmp __push

__gloytmp0:
	ldy #1
__gloytmp:
	jsr __gloy
	sta @tmp
	stx @tmp+1
	rts

__gloytmpd1:
	jsr __gloytmp
	ldx #0
	lda (@tmp,x)
	rts

__gloytmpd2:
	jsr __gloytmp
	ldy #1
	lda (@tmp),y
	tax
	dey
	lda (@tmp),y
	rts

__pushyd1:
	jsr __gloytmpd1
	jmp __push

__pushyd2:
	jsr __gloytmpd2
	jmp __push
