;
;	Add (TOS) to hireg:D and remove from stack
;
	.export __plusl
	.setcpu 6803

__plusl:
	tsx
	addd	4,x		; low halves
	std	@tmp
	ldd	@hireg
	adcb	3,x
	adca	2,x
	std	@hireg
	ldd	@tmp
	pulx
	ins
	ins
	ins
	ins
	jmp	,x
