	.export __castc_

; Almost never used as our chars are unsigned by default

__castc_:
	ldx	#0
	ora	#0
	bpl	pve
	dex
pve:	rts
