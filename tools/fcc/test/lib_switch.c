/* lib_switch.c — exercise __switch (int) and __switchc (char) dispatch.
 * Returns 0 on success, else the index of the first failing check.
 *
 * Note: the char switch (__switchc) is driven from a char *local* in main
 * rather than through a char-parameter function call.  Passing a char by value
 * is an independent code-gen defect in backend-blip.c (it pushes a 2-byte word
 * with PSHS $06 but cleans up only 1 byte with LEA SP,SP+1), which corrupts the
 * stack regardless of the support library.  Switching on a local sidesteps that
 * unrelated bug so the test exercises __switchc itself. */

int sw(int x)
{
	switch (x) {
	case 1: return 10;
	case 2: return 20;
	case 7: return 70;
	case 100: return 1000;
	default: return -1;
	}
}

int main(void)
{
	char c;
	int r;

	if (sw(1) != 10) return 1;
	if (sw(2) != 20) return 2;
	if (sw(7) != 70) return 3;
	if (sw(100) != 1000) return 4;
	if (sw(3) != -1) return 5;       /* default */
	if (sw(0) != -1) return 6;       /* default */
	if (sw(101) != -1) return 7;     /* default */

	/* __switchc, driven from char locals (see header note) */
	c = 'a';
	switch (c) { case 'a': r = 1; break; case 'b': r = 2; break; case 'z': r = 26; break; default: r = 0; break; }
	if (r != 1) return 8;
	c = 'b';
	switch (c) { case 'a': r = 1; break; case 'b': r = 2; break; case 'z': r = 26; break; default: r = 0; break; }
	if (r != 2) return 9;
	c = 'z';
	switch (c) { case 'a': r = 1; break; case 'b': r = 2; break; case 'z': r = 26; break; default: r = 0; break; }
	if (r != 26) return 10;
	c = 'q';
	switch (c) { case 'a': r = 1; break; case 'b': r = 2; break; case 'z': r = 26; break; default: r = 0; break; }
	if (r != 0) return 11;          /* default */

	return 0;
}
