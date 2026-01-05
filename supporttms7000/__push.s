	.export __pushac
	.export __pushacl

;	Push word or long uninlined

__pushac:
	decd	r15
	mov	r5,a
	sta	*r15
	decd	r15
	mov	r4,a
	sta	*r15
	rets

__pushacl:
	decd	r15
	mov	r5,a
	sta	*r15
	decd	r15
	mov	r4,a
	sta	*r15
	decd	r15
	mov	r3,a
	sta	*r15
	decd	r15
	mov	r2,a
	sta	*r15
	rets
