/* lib_mul.c — exercise __mul (16x16 -> 16, low 16 bits).
 * Returns 0 on success, else the index of the first failing check. */

int mul(int a, int b) { return a * b; }
unsigned umul(unsigned a, unsigned b) { return a * b; }

int main(void)
{
	/* small */
	if (mul(6, 7) != 42) return 1;
	/* exercises both partial products (123*45 = 5535) */
	if (mul(123, 45) != 5535) return 2;
	/* 0x0102 * 0x0304 = 0x00030A08, low 16 = 0x0A08 = 2568 */
	if (umul(0x0102, 0x0304) != 0x0A08) return 3;
	/* commutative */
	if (mul(45, 123) != 5535) return 4;
	/* negative * positive: -3 * 100 = -300 */
	if (mul(-3, 100) != -300) return 5;
	/* negative * negative: -3 * -4 = 12 */
	if (mul(-3, -4) != 12) return 6;
	/* high bits discarded: 0x4000 * 4 = 0x10000 -> 0 (low 16) */
	if (umul(0x4000, 4) != 0) return 7;
	/* 257 * 257 = 66049 = 0x10201, low 16 = 0x0201 = 513 */
	if (umul(257, 257) != 513) return 8;
	/* x*1 and x*0 */
	if (mul(12345, 1) != 12345) return 9;
	if (mul(12345, 0) != 0) return 10;
	return 0;
}
