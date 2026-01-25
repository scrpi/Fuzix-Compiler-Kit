;
;	Call the function in XA
;
	.export __callfunc

__callfunc:
;	Using RTI to do indirect transfer pulls the address from the stack
;	without the decrementing the addresses needed for RTS, provided that
;	a spare copy of the processor status byte is pushed. (In situations
;	where the address can be decremented at compile/link time, RTS
;	is still slightly more efficient).
;
;	The even simpler route is to a self-modifying JMP instruction, but it's not
;	re-entrant, cannot be placed in ROM, and probably doesn't work with 65C816.

;	Push return address onto stack, high byte first. 
;	For 6502, use Y as part of the shuffle.
;	For 65C02, this could be further optimized to PHX PHA 

	tay
	txa
	pha
	tya
	pha

	; RTI works without decrementing address, 
	; but must push a copy of the status register

	php
	rti
