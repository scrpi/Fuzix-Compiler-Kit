/* regression: !/bool/if on a char must test only the low byte, and a boolean
   result must be a clean 16-bit int (these bugs were masked by exit-code low
   byte; check the high byte via >>8). */
unsigned char a;
int hi(int v){return v>>8;}
int main(){int r;
 r=0x3400; a=0; if(a) return 1;          /* stale A must not make a look true */
 r=0x1200; a=0; r=(!a); if(hi(r)!=0) return 2;  /* !a == int 1, high byte 0 */
 a=5; if(!a) return 3;
 return 0;}
