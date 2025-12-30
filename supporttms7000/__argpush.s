;
;	Argument stack shorteners
;

	; Push a local variable
	.export __pushln
	.export __pushlnl
	.export __pushlnw
	.export __pushlnwl

	; Short form pushes for constant helpers
	.export	__push0
	.export	__push1
	.export __pushl0
	.export __pushl1
	.export __pushl0r
	.export __pushl0a

;
;	On entry r13 is the offset on the stack
;
__pushln:
	clr	r12
__pushlnw:
	add	r15,r13
	adc	r14,r12
	; r12/r13 now points to the end of the variable
	; low byte
	lda	*r13
	; push
	decd	r15
	sta	*r15
	; high byte
	decd	r13
	lda	*r13
	; push
	decd	r15
	sta	*r15
	rets

__pushlnl:
	clr	r12
__pushlnwl:
	add	r15,r13
	adc	r14,r12
	; r12/r13 now points to the end of the variable
	; low byte
	lda	*r13
	; push
	decd	r15
	sta	*r15
	; second byte
	decd	r13
	lda	*r13
	; push
	decd	r15
	sta	*r15
	; third byte
	dec	r13
	lda	*r13
	; push
	decd	r15
	sta	*r15
	; final byte
	decd	r13
	lda	*r13
	; push
	decd	r15
	sta	*r15
	rets



; Push the accumulator word as a long
__pushl0a:
	mov	r5,r0
	decd	r15
	sta	*r15
	mov	r4,r0
	decd	r15
	sta	*r15
	jmp	__push0
; Push 1 as a long
__pushl1:
	mov	%1,r0
	jmp	__pushl0r
; Push 0 as a long
__pushl0:
	clr	r0
; Push r0 byte as a long
__pushl0r:
	decd	r15
	sta	*r15
	clr	r0
	decd	r15
	sta	*r15
	decd	r15
	sta	*r15
	decd	r15
	sta	*r15
	rets
; Push 1 as a word
__push1:
	mov	%1,r0
	decd	r15
	sta	*r15
	clr	r0
	decd	r15
	sta	*r15
	rets
; Push 0 as a word
__push0:
	clr	r0
	decd	r15
	sta	*r15
	decd	r15
	sta	*r15
	rets
