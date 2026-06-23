int main(){int x;int *p;int a[4];int i,s;
 p=&x;*p=1234; if(*p!=1234)return 1;
 for(i=0;i<4;i++)a[i]=i+1; s=0; for(i=0;i<4;i++)s=s+a[i];
 if(s!=10)return 2; if(a[2]!=3)return 3; return 0;}
