/* lib_mix.c — combine *, /, % and switch in single expressions.
 * Returns 0 on success, else the index of the first failing check. */

int f(int a, int b, int c, int d) { return (a * b) / c % d; }
unsigned g(unsigned a, unsigned b, unsigned c) { return a * b / c; }

int classify(int n)
{
	int k = (n * 3) % 5;          /* mix * and % feeding a switch */
	switch (k) {
	case 0: return 100;
	case 1: return 101;
	case 2: return 102;
	case 3: return 103;
	default: return 104;          /* k == 4 */
	}
}

int main(void)
{
	/* (a*b)/c % d : (10*20)/7 % 4 = 200/7=28, 28%4=0 */
	if (f(10, 20, 7, 4) != 0) return 1;
	/* (3*4)/5 % 100 = 12/5=2, 2%100=2 */
	if (f(3, 4, 5, 100) != 2) return 2;
	/* negatives: (-10*20)/7 % 4 = -200/7=-28, -28%4=0 */
	if (f(-10, 20, 7, 4) != 0) return 3;
	/* (-7*3)/2 % 5 = -21/2=-10, -10%5=0 */
	if (f(-7, 3, 2, 5) != 0) return 4;
	/* (7*3)/2 % 4 = 21/2=10, 10%4=2 */
	if (f(7, 3, 2, 4) != 2) return 5;

	/* unsigned a*b/c : 300*200/7 = 60000/7 = 8571 */
	if (g(300, 200, 7) != 8571) return 6;
	/* 1000*60/123 = 60000/123 = 487 */
	if (g(1000, 60, 123) != 487) return 7;

	/* switch fed by an arithmetic mix */
	if (classify(0) != 100) return 8;    /* 0*3%5 = 0 */
	if (classify(1) != 103) return 9;    /* 3%5 = 3 */
	if (classify(2) != 101) return 10;   /* 6%5 = 1 */
	if (classify(3) != 104) return 11;   /* 9%5 = 4 -> default */
	if (classify(5) != 100) return 12;   /* 15%5 = 0 */

	return 0;
}
