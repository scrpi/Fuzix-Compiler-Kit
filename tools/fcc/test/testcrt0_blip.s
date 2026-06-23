; testcrt0_blip.s — minimal BLIP crt0 for the emulator test harness.
;
; Boot path (image linked flat at 0, entered at PC=0):
;   * set SP just below the I/O page,
;   * JSR _main,
;   * take main's return (16-bit in X per the §7 ABI, or 8-bit in B) and store
;     its low byte to the exit port 0xFF03, which makes emublip exit(low).
;
; Magic I/O ABI used here (matches emublip.c blip_write):
;   0xFF00  latch the low byte of a 16-bit int to be printed
;   0xFF01  print signed 16-bit ((hi<<8)|lo) as "%d\n"   (write hi here)
;   0xFF02  putchar (write the byte)
;   0xFF03  exit(low byte written)
;
; Helpers follow the §7 caller-cleanup ABI: the caller pushes args (PSHS) before
; the call and pops them (LEA SP / PULS) after; helpers read args at (SP+2..)
; above the saved return address.

	.code
	.export start
	.export _printint
	.export _printchar

start:
	LD SP,$FEFF
	JSR _main
	; main's 16-bit result is in X (§7); exit with its low byte.
	LD D,X			; D <- X  (movsel: src X=1, dst D=0 -> 0x10)
	ST B,($FF03)		; exit(B) ; B is the low byte of D
	; not reached
	ST B,($FF03)

; _printint(int) — prints the 16-bit argument as a signed decimal + newline.
; Arg layout at entry: (SP)=return addr (2 bytes), (SP+2)=arg low, (SP+3)=hi.
_printint:
	LD A,(SP+2)		; arg low byte
	ST A,($FF00)		; latch low
	LD A,(SP+3)		; arg high byte
	ST A,($FF01)		; print signed 16-bit
	RTS

; _printchar(char) — writes the low byte of its argument via putchar.
; Arg layout: (SP)=return addr, (SP+2)=char (low byte of the pushed word).
_printchar:
	LD A,(SP+2)
	ST A,($FF02)
	RTS
