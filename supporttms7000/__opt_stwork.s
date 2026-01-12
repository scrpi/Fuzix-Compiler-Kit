;
;	Rule rewrite of storing work into r4/r5
;
	.export __stwork
	.code

__stwork:
	add %1,r5
	adc %0,r4
	mov r11,r0
	sta *r5
	decd r5
	mov r10,r0
	sta *r5
	rets