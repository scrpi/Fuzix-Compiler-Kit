;
;	*r4/5 += r10-r13
;
	.export __plusplusl

__plusplusl:
	add %3,r5
	adc %0,r4	; point at low end
	lda *r5
	mov a,b
	add r13,a
	push st
	sta *r5		; low byte old into b, result into *r5
	decd r5
	lda *r5		; second byte
	mov a,r13	; load into r13 (free now)
	pop st
	adc r12,a	; into a
	push st
	sta *r5		; into *r5
	decd r5
	lda *r5		; same again but can put the value into the right spot
	mov a,r3
	pop st
	adc r11,a
	push st
	sta *r5
	decd r5
	lda *r5		; last byte into r2
	mov a,r2
	pop st
	adc r10,a
	sta *r5
	mov b,r5	; shuffle the other 2 bytes
	mov r13,r4
	rets


