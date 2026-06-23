/* char arguments occupy a word on the stack; a parameter after a char arg must
   still land at the right offset (regression for the push/cleanup/layout
   mismatch). Pure native -- switch-on-char is covered in lib_switch.c. */
int f(char c){return c+1;}
int g(char a,int b){return a+b;}
int h(char a,char b,int c){return a+b+c;}
int main(){
 if(f(41)!=42)return 1;
 if(g(2,40)!=42)return 2;
 if(h(1,2,39)!=42)return 3;
 return 0;}
