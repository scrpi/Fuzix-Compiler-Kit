/* 32-bit long support, compiled to native BLIP (D:Y working pair) with the
 * supportblip long helpers (__mull, __divl/__divul, __reml/__remul, __shll/
 * __shrl/__shrul).  Returns 0 if every check passes, else the index of the
 * first failure (emulator exit code).  Run by run-libtest.sh.
 *
 * Long values are checked byte-by-byte through a char pointer; comparisons and
 * bool return int and are tested directly.
 */

unsigned long gr;
long ga, gb;
unsigned long ua, ub;

static int chk(unsigned char b0, unsigned char b1, unsigned char b2, unsigned char b3)
{
	unsigned char *p = (unsigned char *)&gr;
	if (p[0] != b0) return 1;
	if (p[1] != b1) return 1;
	if (p[2] != b2) return 1;
	if (p[3] != b3) return 1;
	return 0;
}

/* Returned 32-bit values come back in the D:Y pair (isa.md §7). */
static unsigned long add1(unsigned long x)
{
	return x + 1;
}

int main(void)
{
	long a, b;
	unsigned long u;
	int i;

	/* ---- arithmetic (carry/borrow across the word boundary) ---- */
	gr = 0x12345678;                    if (chk(0x78,0x56,0x34,0x12)) return 1;
	ga=0x0000FFFF; gb=1; gr=ga+gb;      if (chk(0x00,0x00,0x01,0x00)) return 2;
	ga=0x00010000; gb=1; gr=ga-gb;      if (chk(0xFF,0xFF,0x00,0x00)) return 3;
	ga=0xF0F0F0F0; gb=0x0FF00FF0; gr=ga&gb; if (chk(0xF0,0x00,0xF0,0x00)) return 4;
	ga=0xF0F00000; gb=0x00000F0F; gr=ga|gb; if (chk(0x0F,0x0F,0xF0,0xF0)) return 5;
	ga=0xFF00FF00; gb=0x0F0F0F0F; gr=ga^gb; if (chk(0x0F,0xF0,0x0F,0xF0)) return 6;
	ga=0x0F0F0F0F; gr=~ga;              if (chk(0xF0,0xF0,0xF0,0xF0)) return 7;
	a=1; gr=(unsigned long)(-a);        if (chk(0xFF,0xFF,0xFF,0xFF)) return 8;

	/* ---- casts ---- */
	i=-5;   gr=(unsigned long)(long)i;  if (chk(0xFB,0xFF,0xFF,0xFF)) return 9;  /* sign-ext */
	u=0xF000; gr=u;                     if (chk(0x00,0xF0,0x00,0x00)) return 10; /* zero-ext */
	a=0x12345678; i=(int)a;             if (i != 0x5678) return 11;              /* narrow */

	/* ---- comparisons (signed/unsigned) ---- */
	a=-5;  b=3;          if (!(a < b)) return 12;
	a=-100; b=-50;       if (!(a < b)) return 13;
	ua=0x80000000; ub=1; if (!(ua > ub)) return 14;  /* unsigned big */
	a=0x80000000; b=1;   if (!(a < b)) return 15;     /* signed negative */
	a=0x00010005; b=0x00010009; if (!(a < b)) return 16; /* high eq, low diff */
	a=42; b=42;          if (!(a == b) || a != b) return 17;

	/* ---- bool ---- */
	a=0;            if (a) return 18;
	a=0x00010000;   if (!a) return 19;
	a=0;            if (!a != 1) return 20;

	/* ---- shifts ---- */
	u=1; gr=u<<31;                      if (chk(0x00,0x00,0x00,0x80)) return 21;
	u=0x80000000; gr=u>>4;              if (chk(0x00,0x00,0x00,0x08)) return 22; /* logical */
	a=-256; gr=(unsigned long)(a>>4);   if (chk(0xF0,0xFF,0xFF,0xFF)) return 23; /* arithmetic = -16 */
	i=3; u=1; gr=u<<i;                  if (chk(0x08,0x00,0x00,0x00)) return 24; /* variable */

	/* ---- multiply ---- */
	ua=0xABCD; ub=0x1234; gr=ua*ub;     if (chk(0xA4,0x4F,0x37,0x0C)) return 25; /* 0x0C374FA4 */
	ua=12345; ub=67890; gr=ua*ub;       if (chk(0x22,0x6C,0xF4,0x31)) return 26; /* 0x31F46C22 */
	a=-7; b=6; gr=(unsigned long)(a*b);  if (chk(0xD6,0xFF,0xFF,0xFF)) return 27; /* -42 */

	/* ---- unsigned divide/modulo ---- */
	ua=0xABCDEF12; ub=0x1234; gr=ua/ub; if (chk(0x2C,0x70,0x09,0x00)) return 28;
	ua=0xABCDEF12; ub=0x1234; gr=ua%ub; if (chk(0x22,0x0E,0x00,0x00)) return 29;
	ua=0x80000000; ub=0xFFFF; gr=ua/ub; if (chk(0x00,0x80,0x00,0x00)) return 30; /* overflow path */

	/* ---- signed divide/modulo (truncate toward zero) ---- */
	a=-100; b=7;  gr=(unsigned long)(a/b); if (chk(0xF2,0xFF,0xFF,0xFF)) return 31; /* -14 */
	a=-100; b=7;  gr=(unsigned long)(a%b); if (chk(0xFE,0xFF,0xFF,0xFF)) return 32; /* -2 */
	a=-100; b=-7; gr=(unsigned long)(a/b); if (chk(0x0E,0x00,0x00,0x00)) return 33; /* 14 */
	a=-2000000000; b=3; gr=(unsigned long)(a/b); if (chk(0x56,0x79,0x43,0xD8)) return 34;

	/* ---- 32-bit value returned across a call (the D:Y return ABI) ---- */
	gr = add1(0x0001FFFF);              if (chk(0x00,0x00,0x02,0x00)) return 35; /* 0x00020000 */
	gr = add1(0xFFFFFFFF);              if (chk(0x00,0x00,0x00,0x00)) return 36; /* carry out, wraps to 0 */

	return 0;
}
