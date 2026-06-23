/* Compound assignment and ++/-- on complex lvalues, compiled to native BLIP.
 * Returns 0 if every check passes, else the index (1..N) of the first failure
 * (observed as the emulator exit code). Run by run-libtest.sh; the *, /, %
 * cases pull __mul/__div/__rem from libblip.a, everything else is native.
 *
 * Covers each operator across int/char, signed/unsigned, and all lvalue shapes
 * (local, global, *p, arr[i]), result-value semantics, a non-simple rhs (the
 * general push path), pointer arithmetic, and post/pre ++/--. Shift counts are
 * constants (variable counts are the documented variable-shift gap).
 */

int g;
int garr[5];
int arr2[3];
unsigned ug;

int main(void)
{
	int a, b;
	unsigned u;
	int *p;
	signed char sc;
	unsigned char uc;

	/* ---- int local, each operator independently ---- */
	a = 10; a += 5;        if (a != 15)     return 1;
	a = 10; a -= 3;        if (a != 7)      return 2;
	a = 10; a *= 4;        if (a != 40)     return 3;
	a = 41; a /= 5;        if (a != 8)      return 4;
	a = 41; a %= 5;        if (a != 1)      return 5;
	a = 0x0F0F; a &= 0x00FF; if (a != 0x000F) return 6;
	a = 0x0F00; a |= 0x00F0; if (a != 0x0FF0) return 7;
	a = 0x0FF0; a ^= 0x00FF; if (a != 0x0F0F) return 8;
	a = 1;   a <<= 5;      if (a != 32)     return 9;
	a = 320; a >>= 4;      if (a != 20)     return 10;

	/* ---- signed divide/modulo/multiply with negatives ---- */
	a = -41; a /= 5;       if (a != -8)     return 11;   /* trunc toward 0 */
	a = -41; a %= 5;       if (a != -1)     return 12;
	a = 41;  a /= -5;      if (a != -8)     return 13;
	a = -7;  a *= -6;      if (a != 42)     return 14;
	a = -256; a >>= 4;     if (a != -16)    return 15;   /* arithmetic >> */

	/* ---- unsigned divide/modulo/shift ---- */
	u = 50000u; u /= 7u;   if (u != 7142u)  return 16;
	u = 50000u; u %= 7u;   if (u != 6u)     return 17;
	u = 0x8000u; u >>= 4;  if (u != 0x0800u) return 18;  /* logical >> */

	/* ---- result value of the assignment expression ---- */
	a = 10; b = (a += 5);  if (b != 15 || a != 15) return 19;

	/* ---- non-simple rhs (general push path) ---- */
	a = 5; b = 3; a += b * 4; if (a != 17)  return 20;

	/* ---- globals ---- */
	g = 100; g += 23;      if (g != 123)    return 21;
	g = 7;   g *= 6;       if (g != 42)     return 22;
	g = 0xAAAA; g &= 0x0FF0; if (g != 0x0AA0) return 23;

	/* ---- through a pointer ---- */
	a = 10;  p = &a; *p += 90; if (a != 100) return 24;
	a = 200; p = &a; *p /= 8;  if (a != 25)  return 25;

	/* ---- array element ---- */
	garr[2] = 9;  garr[2] *= 5;  if (garr[2] != 45) return 26;
	garr[1] = 30; garr[1] -= 12; if (garr[1] != 18) return 27;

	/* ---- signed char ---- */
	sc = 10;   sc += 5;    if (sc != 15)    return 28;
	sc = 100;  sc -= 40;   if (sc != 60)    return 29;
	sc = 7;    sc *= 9;    if (sc != 63)    return 30;
	sc = 100;  sc /= 7;    if (sc != 14)    return 31;
	sc = -100; sc /= 7;    if (sc != -14)   return 32;   /* signed widen */
	sc = 0x5A; sc &= 0x0F; if (sc != 0x0A)  return 33;
	sc = 1;    sc <<= 4;   if (sc != 16)    return 34;

	/* ---- unsigned char ---- */
	uc = 200;  uc += 50;   if (uc != 250)   return 35;
	uc = 0xF0; uc >>= 4;   if (uc != 0x0F)  return 36;   /* logical widen */
	uc = 200;  uc /= 8;    if (uc != 25)    return 37;

	/* ---- pointer arithmetic op-equals (scaled by element size) ---- */
	p = arr2; p += 2; *p = 7; if (arr2[2] != 7) return 38;
	p = arr2 + 2; p -= 1; *p = 9; if (arr2[1] != 9) return 39;

	/* ---- ++/-- on complex lvalues (array, *p) ---- */
	garr[3] = 5; garr[3]++;       if (garr[3] != 6) return 40;          /* NORETURN */
	garr[3] = 5; b = garr[3]++;   if (b != 5 || garr[3] != 6) return 41; /* post: old */
	garr[3] = 5; b = ++garr[3];   if (b != 6 || garr[3] != 6) return 42; /* pre: new  */
	a = 10; p = &a; (*p)++;       if (a != 11) return 43;
	a = 10; p = &a; b = (*p)--;   if (b != 10 || a != 9) return 44;     /* post-dec: old */

	/* ---- ++ on a pointer through a pointer (scaled delta) ---- */
	{
		int *q = arr2;
		int **pp = &q;
		(*pp)++;                  /* advance q by one int */
		if (q != arr2 + 1) return 45;
	}

	return 0;
}
