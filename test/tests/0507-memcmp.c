/* ANSIfied from dLibs 1.2 and handling of 0 length compare done as per
   convention (equality) */

int memcmp(const void *mem1, const void *mem2, int len)
{
	const signed char *p1 = mem1, *p2 = mem2;

	if (!len)
		return 0;

	while (--len && *p1 == *p2) {
		p1++;
		p2++;
	}
	return *p1 - *p2;
}

int main(int argc, char *argv[])
{
	if (memcmp("hello", "there", 5) == 0)
		return 1;
	if (memcmp("bacon", "fries", 5) >= 0)
		return 2;
	if (memcmp("fish", "pie", 3) >= 0)
		return 3;
	if (memcmp("zoo", "poo", 3) <= 0)
		return 4;
	if (memcmp("zoo", "poop", 3) <= 0)
		return 5;
	return 0;
}