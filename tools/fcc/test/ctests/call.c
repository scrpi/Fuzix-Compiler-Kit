int add(int x,int y){return x+y;}
int fib(int n){if(n<2)return n;return fib(n-1)+fib(n-2);}
int main(){if(add(20,22)!=42)return 1; if(fib(10)!=55)return 2; return 0;}
