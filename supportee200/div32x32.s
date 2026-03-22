;
;	32bit unsigned divide. Used as the core for the actual C library
;	division routines. It expects to be called with the parameters
;	offsets from S
;
;	tmp2/tmp3 end up holding the remainder
;
;	On entry the stack frame referenced by S looks like this
;
;	6-9	32bit dividend (C compiler TOS)
;	4,5	A return address
;	0-3	32bit divisor
;
;	In the main loop it becomes
;
;
;	18-19	Dividend (low)
;	16-17	Dividend (high)
;	14-15	Saved return link
;	12-13	Divisior (low)
;	10-11	Divisor (high)
;	8-9	Return
;	6-7	Saved X
;	4-5	Saved Z
;	2-3	Saved Y
;	0-1	saved B
;
;	The one trick here is that to save space and time we start
;	with DIVID,x hoilding the 32bit input value (N in the usual
;	algorithm description). Each cycle we take the top bit of N,
;	we shift it left discarding this bit from DIVID,x and we shift the
;	resulting Q(n) bit into the bottom. After 32 cycles we throw N(0)
;	out and have shifted all of Q into the result.
;

		.setcpu 4

		.export div32x32
		.code

;
;	YZ are our working register
;	DIVID is our in memory dividend
;	XAB are scratch
;
div32x32:
		stx	(-s)
		xfr	y,a
		sta	(-s)
		xfr	z,a
		sta	(-s)

		ldb 	32		; 32 iterations for 32 bits

		; Clear the working register YZ
		; R = 0;
		clr	y
		clr	z

loop:		stb	(-s)

		; Shift the dividend left and set bit 0 assuming that
		; R >= D
		sl
		ldb	18(s)		; low dividend
		rlr	b
		stb	18(s)
		ldb	16(s)		; high dividend
		rlr	b
		stb	16(s)

		; N(i) is now in carry
		; R <<= 1; R(0) = N(i)
		; Capture into the working register

		rlr	z
		rlr	y

		; capturing high bit into the working register bottom

		; Do a 32bit subtract but skip writing the high 16bits
		; back until we know the comparison
		;
		; R - D
		;

		ldb	12(s)		; low half divisor
		xfr	z,a		; copy working low into A
		xax			; and into X
		sab			; B = A - B
		xfr	b,z		; save new low
		xfr	y,a		; high half
		ldb	10(s)		; divisor
		bl	noripple	; do carry if needed
		inr	b		; carry
noripple:
		sab			; B = A - B, high half
		; Want to subtract (R - D >= 0)
		bl	dosub		; Big enough
		bz	dosub
		xfr	x,z		; Low half back
		; High half in Y is still the old value
		; We guessed the wrong way for Q(i). Clear Q(i) which is
		; in the lowest bit and we know is set so using dec is safe
		ldab	19(s)		; Low byte low dividend
		dcab
		stab	19(s)
		bra	done
dosub:		; Low half is in Z, high half is in B
		xfr	b,y		; Move high half into place
done:
		ldb	(s+)		; recover counter
		dcr	b
		bnz	loop

		; Result is in YZ - move it
		xfr	z,b
		xfr	y,a

		ldx	(s+)
		xfr	x,y
		ldx	(s+)
		xfr	x,z
		ldx	(s+)
		; Registers restored result now in A / B
		rsr
