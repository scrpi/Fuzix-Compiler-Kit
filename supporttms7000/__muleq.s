;
;	Same helper but with load/store from pointer
;
	.export __muleq
	.export __mulequ   	

	.code

__muleq:
__mulequ:
	; stack holds ptr instead in this case
	call @__pop10

	; Get values
	lda *r11
	mov a,r2
	add %1,r11
	adc %0,r11
	lda *r11
	mov a,r3

	; save ptr
	push r11
	push r10

	; r2/r3 x r4/r5

	mpy r3,r5
	movd b,r12		; r12/r13 working low
	mpy r3,r4		; high1 v low 2
	add b,r2
	mpy r2,r5
	add b,r12

	movd r12,r5
	; result in r4,r5, r10/r11/12/13 trashed
	pop r10
	pop r11
	mov r5,a
	sta *r11
	decd r11
	mov r4,a
	sta *r11
	rets


