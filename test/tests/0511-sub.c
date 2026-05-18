int sub(char *p) {
        int v = 100, d = 3;
        *p = v - 10 * d;
        return v;
}

int main(int argc, char *argv[])
{
        char x;
        if (sub(&x) != 100)
                return 1;
        return 0;
}
