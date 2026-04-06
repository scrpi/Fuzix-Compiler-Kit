;
;	Store XA into (@tmp)
;
	.code
	.export __poptmpstxa

__poptmpstxa:
	jsr	__poptmp
	; Y is now 0 XA is preserved @tmp is pointer
	sta	(@tmp),y
	iny
	pha
	txa
	sta	(@tmp),y
	pla
	; Y always 1 on exit - compiler knows this
	rts
