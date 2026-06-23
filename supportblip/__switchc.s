;
;	__switchc — char (8-bit) switch dispatch.
;
;	The backend emits:
;	    LD B,<value>
;	    JSR __switchc
;	    .word Sw<n>
;	Table layout for a char switch (note byte case values):
;	    .word count
;	    .byte value0  .word target0     ; 3 bytes per entry
;	    .byte value1  .word target1
;	    ...
;	    .word default
;
;	On entry B = switch value (low byte).  As with __switch, the JSR return
;	word (pointing at ".word Sw<n>") gives the table base and is then
;	dropped so the case body's RTS pops the function's real return address.
;	Y is the counter (not preserved).
;
	.export __switchc
	.code

__switchc:
	LD X,(SP)		; X = &(.word Sw<n>)
	LD X,(X+0)		; X = table base
	LEA SP,SP+2		; drop the JSR return word
	LD Y,(X++)		; Y = count ; X -> first entry
	CMP Y,$0000
	BEQ scdefault
scnext:
	CMP B,(X)		; compare value byte
	BEQ scfound
	LEA X,X+3		; skip byte value + word target
	LEA Y,Y-1
	BNE scnext
scdefault:
	LD X,(X+0)		; default target word
	JMP X
scfound:
	LD X,(X+1)		; target follows the 1-byte value
	JMP X
