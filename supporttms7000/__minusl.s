;
;	AC = TOS - AC and remove from stack
;
	.export __minusl
	.code

__minusl:
	; TOS holds the value but it's high byte first
	movd r15,r13
	add %4,r13
	adc %0,r12
	; point to the new tos and save it
	movd r13,r11
	decd r13
	lda *r13
	sub a,r5
	push st
	mov a,r5
	decd r13
	lda *r13
	pop st
	sbb a,r4
	push st
	mov a,r4
	decd r13
	lda *r13
	pop st
	sbb a,r3
	push st
	mov a,r3
	decd r13
	lda *r12
	pop st
	sbb a,r2
	mov a,r2
	movd r11,r14	; and adjust the stack
	rets

