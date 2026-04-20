long left4(long x)
{
	return x << 4;
}

unsigned long right4u(unsigned long x)
{
	return x >> 4;
}

long right4(long x)
{
	return x >> 4;
}


long left8(unsigned long x)
{
	return x << 8;
}

unsigned long right8u(unsigned long x)
{
	return x >> 8;
}

long right8(long x)
{
	return x >> 8;
}

long left16(unsigned long x)
{
	return x << 16;
}

unsigned long right16u(unsigned long x)
{
	return x >> 16;
}

long right16(long x)
{
	return x >> 16;
}

long left24(unsigned long x)
{
	return x << 24;
}

unsigned long right24u(unsigned long x)
{
	return x >> 24;
}

long right24(long x)
{
	return x >> 24;
}

long left26(unsigned long x)
{
	return x << 26;
}

unsigned long right26u(unsigned long x)
{
	return x >> 26;
}

long right26(long x)
{
	return x >> 26;
}

long left17(unsigned long x)
{
	return x << 17;
}

unsigned long right17u(unsigned long x)
{
	return x >> 17;
}

long right17(long x)
{
	return x >> 17;
}

long left9(unsigned long x)
{
	return x << 9;
}

long right9(long x)
{
	return x >> 9;
}

unsigned long right9u(unsigned long x)
{
	return x >> 9;
}

long lshift(unsigned long x, unsigned long y)
{
	return x << y;
}

long rshiftu(unsigned long x, unsigned long y)
{
	return x >> y;
}

long rshifts(long x, unsigned long y)
{
	return x >> y;
}

long lshifteql(unsigned long a, unsigned long b)
{
	a <<= b;
	return a;
}

long rshiftequl(unsigned long a, unsigned long b)
{
	a >>= b;
	return a;
}

long rshifteql(long a, unsigned long b)
{
	a >>= b;
	return a;
}

int main(int argc, char *argv[])
{
	/* Basic tests for simple constant shifting */
	if (left4(2) != 32)
		return 1;
	if (right4(32) != 2)
		return 2;
	if (right4u(32) != 2)
		return 3;
	/* Check sign bits */
	if (right4(0x80000000) != 0xF8000000)
		return 4;
	if (right4u(0x80000000) != 0x08000000)
		return 5;

	/* Optimized cases on some targets */
	if (left8(1) != 0x100)
		return 10;
	if (left16(1) != 0x10000)
		return 11;
	if (left24(1) != 0x1000000)
		return 12;
	if (left9(1) != 0x200)
		return 13;
	if (left17(1) != 0x20000)
		return 14;
	if (left26(1) != 0x4000000)
		return 15;

	if (right8u(0x1234200) != 0x12342)
		return 20;
	if (right16u(0x40000) != 0x4)
		return 21;
	if (right24u(0x2000000) != 0x2)
		return 22;
	if (right9u(0x20000) != 0x100)
		return 23;
	if (right17u(0x40000) != 0x2)
		return 24;
	if (right26u(0x8000000) != 0x2)
		return 25;

	/* Same signed */
	if (right8(0x1234200) != 0x12342)
		return 30;
	if (right16(0x40000) != 0x4)
		return 31;
	if (right24(0x2000000) != 0x2)
		return 32;
	if (right9(0x20000) != 0x100)
		return 33;
	if (right17(0x40000) != 0x2)
		return 34;
	if (right26(0x8000000) != 0x2)
		return 35;

	/* Now check the sign bit handling */
	if (right8(0x92342000) != 0xFF923420)
		return 40;
	if (right16(0x81230000) != 0xFFFF8123)
		return 41;
	if (right24(0x80000000) != 0xFFFFFF80)
		return 42;
	if (right9(0x800000FF) != 0xFFC00000)
		return 43;
	if (right17(0xF0000000) != 0xFFFFF800)
		return 44;
	if (right26(0x80000000) != 0xFFFFFFE0)
		return 45;

	/* Test shifts around 24 optimization case */
	if (lshift(0x55, 25) != 0xAA000000)
		return 50;
	if (lshift(0xF5, 24) != 0xF5000000)
		return 51;
	if (rshiftu(0x30000000, 28) != 0x03)
		return 52;
	if (rshiftu(0xF0000000, 28) != 0x0F)
		return 53;
	if (rshifts(0x30000000, 28) != 0x03)
		return 54;
	if (rshifts(0xF0000000, 28) != 0xFFFFFFFF)
		return 55;
	if (rshiftu(0xF0000000, 24) != 0xF0)
		return 56;
	if (rshifts(0xF0000000, 24) != 0xFFFFFFF0)
		return 57;

	/* Test shifts around 16 optimization case */
	if (lshift(0xF5, 16) != 0xF50000)
		return 51;
	if (rshiftu(0xF0000000, 16) != 0xF000)
		return 56;
	if (rshifts(0xF0000000, 16) != 0xFFFFF000)
		return 57;
	if (lshift(0xF5, 20) != 0xF500000)
		return 58;
	if (rshiftu(0xF0000000, 20) != 0xF00)
		return 59;
	if (rshifts(0xF0000000, 20) != 0xFFFFFF00)
		return 60;

	/* Test shifts around 8 optimization case */
	if (lshift(0xF5, 8) != 0xF500)
		return 51;
	if (rshiftu(0xF0000000, 8) != 0x00F00000)
		return 56;
	if (rshifts(0xF0000000, 8) != 0xFFF00000)
		return 57;
	if (lshift(0xF5, 12) != 0xF5000)
		return 58;
	if (rshiftu(0xF0000000, 12) != 0x000F0000)
		return 59;
	if (rshifts(0xF0000000, 12) != 0xFFFF0000)
		return 60;

	return 0;
}
