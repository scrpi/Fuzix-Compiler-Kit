	.export __muleq

	.code

__muleq:
	; tmp is the value, ea the pointer
	ld	t,ea
	ld	ea,0,p2
	jsr	__mpyfix
	st	ea,0,p2
	ret
	