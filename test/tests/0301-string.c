static char buffer[256];

static char *xstrcpy(char *dest, const char *src) {
	char *saved_dest = dest;
	while(*dest++ = *src++) {
		// Empty block
	}
	return saved_dest;
}

static int xstrcmp(const char *s1, const char *s2) {
	while (*s1 && (*s1==*s2)) {
		++s1;
		++s2;
	}
	return (*s1-*s2);
}

int main() {
	int cmpresult;

	// Load buffer with a simple string
	xstrcpy(buffer, "One");

	// Char by char comparison
	if(buffer[0] != 'O' || 
       buffer[1] != 'n' || 
       buffer[2] != 'e' || 
       buffer[3] != '\0')
		return 1;

	// Same comparison with helper function
	cmpresult = xstrcmp(buffer, "One");
	if (cmpresult !=0 )
		return 2;

	// All tests passed
	return 0;
}
