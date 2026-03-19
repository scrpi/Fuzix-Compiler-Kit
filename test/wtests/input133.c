void cprintf(char *fmt, ...);

extern int fred[];
int fred[23];

char mary[100];
extern char mary[];

/* For C99 testing this is void main() and meaningful but we are C89 for now */
int main() { cprintf("OK\n"); return 0; }
