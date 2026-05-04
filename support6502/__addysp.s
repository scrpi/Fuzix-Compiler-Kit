;
;	Adjust stack frame by Y bytes
;
; From cc65
;
; Ullrich von Bassewitz, 25.10.2000
;
; CC65 runtime: Increment the stackpointer by value in y
;

	.export __add4sp
	.export __add3sp
	.export	__addysp1
	.export __addysp

	.code
__add4sp:
	ldy	#4
	bne	__addysp
__add3sp:
	ldy	#3
	bne	__addysp
__addysp1:
	iny
__addysp:
	pha		; Save A
	clc
	tya		; Get the value
	adc     @sp	; Add low byte
	sta     @sp	; Put it back
	bcc     l1	; If no carry, we're done
	inc     @sp+1	; Inc high byte
l1:	pla		; Restore A
	rts
