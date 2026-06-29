;
;	crt0.s — BLIP C runtime startup (library copy).
;
;	Boot path for a flat image linked at 0 (entered at PC=0):
;	    * set SP just below the exception vector table (0xDF00-0xDFFF), which
;	      itself sits just below the I/O page (frame 7, 0xE000-0xFFFF, no RAM),
;	    * JSR _main,
;	    * main returns its 16-bit value in X (§7 ABI); exit with its low
;	      byte through the emulator exit port 0xFF03.
;
;	This mirrors tools/fcc/test/testcrt0_blip.s.  The acceptance harness
;	links testcrt0_blip.o explicitly, so libblip.a itself only needs the
;	helper routines; this crt0 is provided for standalone use.
;
	.code
	.export start

start:
	LD SP,$DEFF		; top of RAM, just below the 0xDF00 vector table
	JSR _main
	LD D,X			; D <- X (main's 16-bit return); B = low byte
	ST B,($FF03)		; exit(B)
	; not reached
	ST B,($FF03)
