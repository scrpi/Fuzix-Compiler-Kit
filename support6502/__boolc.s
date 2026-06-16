;
;	Turn A into 0 or 1 and flags
;
	.export __boolc

__boolc:
	ldx #0
	cmp #0
	beq ex0
	lda #1
ex0:
	rts
