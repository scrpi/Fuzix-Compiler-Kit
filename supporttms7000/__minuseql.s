;
;	*TOS - AC
;
	.export __minuseql
	.code


__minuseql:
	call @__pop12

	lda *r13
	sub r5,a
	push st
	mov a,r5
	sta *r13
	decd r13

	lda *r13
	pop st
	sbb r4,a
	push st
	mov a,r4
	sta *r13
	decd r13

	lda *r13
	pop st
	sbb r3,a
	push st
	mov a,r3
	sta *r13
	decd r13

	lda *r13
	pop st
	sbb r2,a
	mov a,r2
	sta *r13
	decd r13

	rets
