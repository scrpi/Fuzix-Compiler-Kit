/* fib.c — print the first 11 Fibonacci numbers, then exit 0.
 *
 * Exercises a real program on the gate-level CPU: a loop with a condition branch, 16-bit add,
 * stack-frame locals, and repeated function calls (printint) with stack-passed args. Expected
 * output (one per line): 0 1 1 2 3 5 8 13 21 34 55 ; exit status 0. */
void printint(int);   /* crt0/libblip helper: print a signed decimal + newline via the I/O port */

int main(void)
{
	int a = 0, b = 1, i, t;

	for (i = 0; i < 11; i++) {
		printint(a);
		t = a + b;
		a = b;
		b = t;
	}
	return 0;
}
