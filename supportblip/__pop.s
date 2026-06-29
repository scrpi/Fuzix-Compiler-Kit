;
;	__pop — discard a stacked comma-expression left operand.
;
;	The default backend evaluates `foo, bar` by evaluating foo for its side
;	effects and stacking its 2-byte value (pushed just below the return
;	address), evaluating bar into the working register D:Y, then calling
;	__pop to throw the stacked foo away.  Drop it and return, leaving the
;	result (D:Y) untouched; X is caller-saved scratch (§7).
;
	.export __pop
	.code

__pop:
	LD X,(SP)		; return address
	LEA SP,SP+4		; drop return(2) + the stacked value(2)
	JMP X
