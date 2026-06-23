/* mid-expression pushes must not corrupt local/arg offsets */
int g(int a,int b,int c,int d){return a-(b-(c-d));}
int main(){int a,b,c,d;a=1;b=2;c=3;d=4;
 if(g(1,2,3,4)!=-2)return 1; if(a+b+c+d!=10)return 2; return 0;}
