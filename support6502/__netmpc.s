;
;	Compare A with @tmp
;
	.export __netmpc
	.export __netmpuc
	.export __l_netmpc
	.export __l_netmpuc

__l_netmpc:
__l_netmpuc:
	jsr ytmp
__netmpc:
__netmpuc:
	ldx #0
	cmp @tmp
	beq false	; already 0
true:	lda #1
false:
	rts


