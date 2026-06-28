;
;	crt0.s — BLIP C runtime startup (library copy).
;
;	Boot path for a flat image linked at 0 (entered at PC=0):
;	    * set SP at the top of RAM,
;	    * JSR _main,
;	    * main returns its 16-bit value in X (§7 ABI); exit with its low
;	      byte through the I/O exit port (OUT B,$03; D-54 separate I/O space).
;
;	This mirrors tools/fcc/test/testcrt0_blip.s.  The acceptance harness
;	links testcrt0_blip.o explicitly, so libblip.a itself only needs the
;	helper routines; this crt0 is provided for standalone use.
;
	.code
	.export start

start:
	LD SP,$FEFF
	JSR _main
	LD D,X			; D <- X (main's 16-bit return); B = low byte
	OUT B,$03		; exit(B)
	; not reached
	OUT B,$03
