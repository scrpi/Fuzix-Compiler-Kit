int main(){int a,b;a=7;b=6;
 if(a+b!=13)return 1; if(a-b!=1)return 2; if((a&b)!=6)return 3;
 if((a|b)!=7)return 4; if((a^b)!=1)return 5; if(-a!=-7)return 6;
 if(~a!=-8)return 7; if(!0!=1)return 8; if(!5!=0)return 9; return 0;}
