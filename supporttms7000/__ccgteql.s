;
;	Comparison between top of stack and ac
;

	.export __ccgteql
	.export __ccgtequl
	.code

__ccgtequl:
	movd r15,r13
	lda *r13
	jmp cmprest
__ccgteql:
	movd r15,r13
	lda *r13
	xor r2,a
	jpz samesign
	xor r2,a
	jn false
	jmp true

samesign:
	xor r2,a
cmprest:
	cmp r2,a
	jnc false		; carry set on equality
	jnz true
	add %1,r13
	adc %0,r12
	lda *r13
	cmp r3,a
	jnc false
	jnz true
	add %1,r13
	adc %0,r12
	lda *r13
	cmp r4,a
	jnc false
	jnz true
	add %1,r13
	adc %0,r12
	lda *r13
	cmp r5,a
	jnc false
true:
	mov %1,r5
	jmp out
false:
	clr r5
out:
	add %4,r15
	adc %0,r14
	clr r4
	or r5,r5	; flags
	rets
