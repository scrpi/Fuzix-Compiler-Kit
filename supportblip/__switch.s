;
;	__switch — integer (16-bit) switch dispatch.
;
;	The backend emits:
;	    LD D,<value>
;	    JSR __switch
;	    .word Sw<n>           ; inline pointer to the jump table
;	The table Sw<n> is laid out (gen_switchdata / gen_case_data):
;	    .word count          ; number of case entries
;	    .word value0  .word target0
;	    ...
;	    .word default        ; default target (always present)
;
;	On entry D = switch value.  The JSR pushed a return address pointing at
;	the inline ".word Sw<n>"; we read the table base from it and then DROP
;	that word, because we transfer control straight into the case body —
;	the case body ends in RTS, which must pop the *caller's* return address
;	(the switch helper never returns to the call site).  Y is used as the
;	loop counter and is not preserved (control leaves via the case body).
;
	.export __switch
	.code

__switch:
	LD X,(SP)		; X = &(.word Sw<n>)  (the JSR return address)
	LD X,(X+0)		; X = table base (Sw<n>)
	LEA SP,SP+2		; drop the JSR return word; TOS is now the
				; function's own return address for the case RTS
	LD Y,(X++)		; Y = count ; X -> first value/target pair
	CMP Y,$0000		; empty table?
	BEQ sdefault
snext:
	CMP D,(X)		; value match?
	BEQ sfound
	LEA X,X+4		; skip this (value,target) pair
	LEA Y,Y-1
	BNE snext
sdefault:
	; X now points at the default target word (just past the last pair)
	LD X,(X+0)
	JMP X
sfound:
	LD X,(X+2)		; target for this case
	JMP X
