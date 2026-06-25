/* ret.c — the minimal C program: just return a value.
 *
 * Even this exercises the crt0 path (LD SP,$nnnn; JSR _main; LD D,X; ST B,($FF03)) and a function
 * prologue/epilogue + RTS, so it is the smallest end-to-end check that call/return and the exit
 * port work on the gate-level CPU. Expected: no output, exit status 42. */
int main(void)
{
	return 42;
}
