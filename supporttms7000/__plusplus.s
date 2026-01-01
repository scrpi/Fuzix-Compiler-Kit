	.export __plusplus
	.export __plusplusc
	.code
;
;	(r4) + r12/13
;	return original data
;
__plusplus:
	lda *r5
	mov a,r2
	add %1,r5
	adc %0,r4
	lda *r5
	mov a,r3
	; R2/R3 is the original
	add r3,r11
	adc r2,r10
	mov r11,a
	sta *r5
	decd r5
	mov r10,a
	sta *r5
	movd r3,r5
	rets

__plusplusc:
	lda *r5
	mov a,b
	add r10,a
	sta *r5
	mov b,r5
	clr r4
	rets
