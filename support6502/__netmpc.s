;
;	Compare A with @tmp
;
	.export __netmpc
	.export __netmpuc
	.export __l_netmpc
	.export __l_netmpuc
	.export __ccnec

__l_netmpc:
__l_netmpuc:
	jsr __ytmp
	jmp __netmpc
__ccnec:
	jsr __poptmpc
__netmpc:
__netmpuc:
	ldx #0
	cmp @tmp
	beq false	; already 0
true:	lda #1
false:
	rts


