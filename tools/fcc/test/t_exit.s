; t_exit.s — load a constant and exit with its low byte. Expect emublip exit 42.
	.code
	.export _main
_main:
	LD B,$2A		; 42
	ST B,($FF03)		; exit(42)
	RTS
