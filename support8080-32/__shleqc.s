;
;	Shift TOS left by HL
;
	.export __shleqc
	.setcpu 8080

	.code

__shleqc:
	call	__popeq
	mov	a,e
	ani	7
	mov	e,a
	mov	a,m
	jz	noop
loop:
	add	a
	dcr	e
	jnz	loop
	mov	m,a
noop:
	mov	l,a
	jmp	__reteq


