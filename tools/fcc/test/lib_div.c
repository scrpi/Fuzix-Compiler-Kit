/* lib_div.c — exercise __div / __divu / __rem / __remu (16-bit).
 * Returns 0 on success, else the index of the first failing check. */

int sdiv(int a, int b) { return a / b; }
int srem(int a, int b) { return a % b; }
unsigned udiv(unsigned a, unsigned b) { return a / b; }
unsigned urem(unsigned a, unsigned b) { return a % b; }

int main(void)
{
	/* unsigned divide / remainder */
	if (udiv(100, 7) != 14) return 1;
	if (urem(100, 7) != 2) return 2;
	if (udiv(50000, 123) != 406) return 3;      /* 50000/123 = 406 r 62 */
	if (urem(50000, 123) != 62) return 4;
	if (udiv(0, 5) != 0) return 5;
	if (udiv(65535, 256) != 255) return 6;      /* 0xFFFF/0x100 */
	if (urem(65535, 256) != 255) return 7;

	/* signed divide: quotient sign = xor of operand signs (trunc toward 0) */
	if (sdiv(100, 7) != 14) return 8;
	if (sdiv(-100, 7) != -14) return 9;
	if (sdiv(100, -7) != -14) return 10;
	if (sdiv(-100, -7) != 14) return 11;

	/* signed remainder: sign follows dividend (C99) */
	if (srem(100, 7) != 2) return 12;
	if (srem(-100, 7) != -2) return 13;
	if (srem(100, -7) != 2) return 14;
	if (srem(-100, -7) != -2) return 15;

	/* exact division -> zero remainder */
	if (sdiv(-99, 9) != -11) return 16;
	if (srem(-99, 9) != 0) return 17;

	/* divide by 1 / by self */
	if (sdiv(12345, 1) != 12345) return 18;
	if (sdiv(-12345, 12345) != -1) return 19;

	/* larger signed */
	if (sdiv(-30000, 123) != -243) return 20;   /* 30000/123 = 243 r 111 */
	if (srem(-30000, 123) != -111) return 21;

	return 0;
}
