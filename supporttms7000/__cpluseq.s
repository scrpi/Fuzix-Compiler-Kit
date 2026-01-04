	.export __cpluseq
	.export __cpluseqc
	.code

__cpluseq:
	; r4/r5 is the pointer
	; r10/11 the value
	add %1,r5
	adc %0,r4
	lda *r5
	add r11,a
	push st
	sta *r5
	mov a,b
	decd r5
	lda *r5
	pop st
	adc r10,a
	sta *r5
	mov a,r4
	mov b,r5
	rets

__cpluseqc:
	lda *r5
	add r10,a
	sta *r5
	mov a,r5
	rets
