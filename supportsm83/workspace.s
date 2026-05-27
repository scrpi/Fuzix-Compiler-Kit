		.data

		.export __tmp
		.export __tmp2
		.export __tmp3
		.export	__callde

; __tmp must be the word before hireg
__tmp:
		.word	0
__tmp2:
		.word	0
		.word	0
__tmp3:
		.word	0
		.word	0

		.code

__callde:	push	de
		ret
