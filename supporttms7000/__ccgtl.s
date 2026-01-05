;
;	Comparison between top of stack and ac
;

	.export __ccgtl
	.export __ccgtul
	.code

__ccgtul:
	movd r15,r13
	lda *r13
	jmp cmprest
__ccgtl:
	movd r15,r13
	lda *r13
	xor r2,a
	jpz samesign
	xor r2,a
	jpz true
	jmp false
samesign:
	xor r2,a
cmprest:
	cmp a,r2
	jnc true		; carry set on equality
	jnz false
	add %1,r13
	adc %0,r12
	lda *r13
	cmp a,r3
	jnc true
	jnz false
	add %1,r13
	adc %0,r12
	lda *r13
	cmp a,r4
	jnc true
	jnz false
	add %1,r13
	adc %0,r12
	lda *r13
	cmp a,r5
	jnc true
false:
	clr r5
out:
	add %4,r15
	adc %0,r14
	clr r4
	or r5,r5	; flags
	rets
true:
	mov %1,r5
	jmp out
