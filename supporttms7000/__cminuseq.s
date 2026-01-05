	.export __cminuseq
	.export __cminuseqc
	.code

__cminuseq:
	add %1,r5
	adc %0,r4
	lda *r5
	sub r11,a
	push st
	sta *r5
	mov a,b

	decd r5

	lda *r5
	pop st
	sbb r10,a
	sta *r5
	mov a,r4
	mov b,r5
	rets

__cminuseqc:
	lda *r5
	sub r10,a
	sta *r5
	mov a,r5
	rets
