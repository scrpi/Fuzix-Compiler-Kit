#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

#include "sm83.h"

static uint16_t pc;
static uint8_t reg[10];
#define REG_B	0
#define REG_C	1
#define REG_D	2
#define REG_E	3
#define REG_H	4
#define REG_L	5
#define REG_M	6		/* (HL) aliasing */
#define REG_F	6
#define REG_A	7
#define REG_SPH	8
#define REG_SP	9
#define RR_BC	0
#define RR_DE	1
#define RR_HL	2
#define RR_SP	3
#define RR_AF	3
static uint8_t ir;
static unsigned ime;
static unsigned prefix_cb;
static unsigned trace;

#define F_Z		0x80	/* Zero */
#define F_S		0x40	/* Last operation was subtractive */
#define F_H		0x20	/* Half carry for DAA */
#define F_C		0x10	/* Carry */

/* Decode pieces */

uint8_t x,y, z;
uint8_t p, q;

static void invalid(void)
{
    fprintf(stderr, "Invalid instruction %02X at %04X\n",
        ir, pc);
    exit(1);
}

static void error(const char *p)
{
    fprintf(stderr, "Internal: %s", p);
    exit(1);
}

static uint8_t next(void)
{
    return mem_read8(pc++);
}

static uint16_t next16(void)
{
    uint16_t r = mem_read8(pc++);
    r |= mem_read8(pc++) << 8;
    return r;
}

/*
 *	Helpers
 */

static uint8_t *pairptr(unsigned n)
{
    return reg + 2 * n;		/* BC DE HL */
}

static uint8_t *pairptr2(unsigned n)
{
    if (n == 3)
        return reg + REG_SPH;
    return reg + 2 * n;
}

static uint16_t getpair(unsigned n)
{
    uint16_t v;
    uint8_t *p;
    /* AF is slightly odd */
    if (n == RR_AF)
        return (reg[REG_A] << 8) | reg[REG_F];
    p = pairptr(n);
    v = *p++ << 8;
    v |= *p;
    return v;
}

static void setpair(unsigned n, unsigned v)
{
    uint8_t *p;
    if (n == RR_AF) {
        reg[REG_A] = v >> 8;
        reg[REG_F] = v;
        return;
    }
    p = pairptr(n);
    *p++ = v >> 8;
    *p = v;
}

static uint16_t getpair2(unsigned n)
{
    uint16_t v;
    uint8_t *p = pairptr2(n);
    v = *p++ << 8;
    v |= *p;
    return v;
}

static uint8_t getreg(unsigned n)
{
    if (n == REG_M)
        return mem_read8(getpair(RR_HL));
    return reg[n];
}

static void setreg(unsigned n, uint8_t v)
{
    if (n == REG_M)
        mem_write8(getpair(RR_HL), v);
    else
        reg[n] = v;
}

/* 16bit inc/dec used for push/pop for the postinc/dec ops and
   for inc/dec or regpairs */
static void decpair(unsigned n)
{
    uint8_t *p = pairptr2(n);
    if (p[1] == 0)
        (*p)--;
    p[1]--;
}

static void incpair(unsigned n)
{
    uint8_t *p = pairptr2(n);
    p[1]++;
    if (p[1] == 0)
        (*p)++;
}

static void push16(uint16_t n)
{
    decpair(RR_SP);
    mem_write8(getpair2(RR_SP), n >> 8);
    decpair(RR_SP);
    mem_write8(getpair2(RR_SP), n);
}

static uint16_t pop16(void)
{
    uint16_t n = mem_read8(getpair2(RR_SP));
    incpair(RR_SP);
    n |= mem_read8(getpair2(RR_SP)) << 8;
    incpair(RR_SP);
    return n;
}

static uint8_t alu_adc(uint8_t a, uint8_t b)
{
    unsigned r = a + b;
    unsigned c = 0;
    if (reg[REG_F] & F_C) {
        c = 1; 
        r++;
    }
    reg[REG_F] &= F_Z;
    if (r & 0x100)
        reg[REG_F] |= F_C;
    if ((a & 0x0F) + (b & 0x0F) + c > 0x0F)
        reg[REG_F] |= F_H;
    return r;
}

static uint8_t alu_sbc(uint8_t a, uint8_t b)
{
    unsigned r = a - b;
    unsigned c = 0;
    if (reg[REG_F] & F_C) {
        c = 1;
        r--;
    }
    reg[REG_F] &= F_Z;
    reg[REG_F] |= F_S;
    if (r & 0x100)
        reg[REG_F] |= F_C;
    if ((a & 0x0F) + c > (b & 0x0F))
        reg[REG_F] |= F_H;
    return r;
}


static void do_jr(unsigned yes)
{
    int8_t n = next();
    if (yes)
        pc += n;
}

static void do_jp(unsigned yes)
{
    uint16_t n = next16();
    if (yes)
        pc = n;
}

static void do_call(unsigned yes)
{
    uint16_t n = next16();
    if (yes) {
        push16(pc);
        pc = n;
    }
}

static void do_ret(unsigned yes)
{
    if (yes)
        pc = pop16();
}

static void do_loadpair(unsigned rr)
{
    uint8_t *p = pairptr2(rr);
    p[1] = next();
    *p = next();
}

static void do_addpair(unsigned rr)
{
    uint8_t *p = pairptr2(rr);

    reg[REG_F] &= F_Z;
    reg[REG_L] = alu_adc(reg[REG_L], p[1]);
    reg[REG_H] = alu_adc(reg[REG_H], *p);
}

static unsigned test_cc(uint8_t cc)
{
    switch(cc) {
    case 0:
        return !(reg[REG_F] & F_Z);
    case 1:
        return reg[REG_F] & F_Z;
    case 2:
        return !(reg[REG_F] & F_C);
    case 3:
        return reg[REG_F] & F_C;
    default:
        error("test_cc");
    }
    return 0;
}

/*
 *	ALU: used for all the 8bit logic and maths ops and some other
 *	stuff.
 */

static void alu8_op(unsigned op, uint8_t v)
{
    /* Do operation between A and the value v. Adjust flags; */
    reg[REG_F] &= ~F_Z;
    switch(op) {
    case 0:	/* ADD */
        reg[REG_F] &= ~F_C;
        /* Fall into ADC */
    case 1:	/* ADC */
        reg[REG_A] = alu_adc(reg[REG_A], v);
        if (reg[REG_A] == 0)
            reg[REG_F] |= F_Z;
        break;
    case 7:	/* CP - SUB without saving */
        reg[REG_F] &= ~F_C;
        if (alu_sbc(reg[REG_A], v) == 0)
            reg[REG_F] |= F_Z;
        break;
    case 2:	/* SUB */
        reg[REG_F] &= ~F_C;
        /* Fall into SBC */
    case 3:	/* SBC */
        reg[REG_A] = alu_sbc(reg[REG_A], v);
        if (reg[REG_A] == 0)
            reg[REG_F] |= F_Z;
        break;
    case 4:	/* AND */
        reg[REG_A] &= v;
        reg[REG_F] = F_H;
        if (reg[REG_A] == 0)
            reg[REG_F] |= F_Z;
        break;
    case 5:	/* XOR */
        reg[REG_A] ^= v;
        reg[REG_F] = 0;
        if (reg[REG_A] == 0)
            reg[REG_F] |= F_Z;
        break;
    case 6:	/* OR */
        reg[REG_A] |= v;
        reg[REG_F] = 0;
        if (reg[REG_A] == 0)
            reg[REG_F] |= F_Z;
        break;
    }
}

/*
 *	Sort of 8080 but not quite
 */

static void page0(void)
{
    uint8_t n;
    uint16_t addr;

    switch(z) {
    case 0:
        switch(y) {
        case 0:
            break;
        case 1:
            /* SM83 quirk */
            /* ld (nnnn),sp - the ony 16bit store of reg it has */
            addr = next16();
            mem_write8(addr++, reg[REG_SP]);            
            mem_write8(addr, reg[REG_SPH]);
            break;
        case 2:
            /* STOP n8 SM83 specific */
            break;
        case 3:
            do_jr(1);
            break;
        case 4:
        case 5:
        case 6:
        case 7:
            do_jr(test_cc(y - 4));
            break;
        }
        break;
    case 1:
        if (q == 0)            
            do_loadpair(p);
            /* load 16 rp */
        else
            /* add 16 rp */
            do_addpair(p);
        break;
    case 2:
        switch(ir) {
            case 002:
                mem_write8(getpair(RR_BC), reg[REG_A]);
                break;
            case 012:
                reg[REG_A] = mem_read8(getpair(RR_BC));
                break;
            case 022:
                mem_write8(getpair(RR_DE), reg[REG_A]);
                break;
            case 032:
                reg[REG_A] = mem_read8(getpair(RR_DE));
                break;
            /* These are not the same as 8080 */
            case 042:	/* LD (HL+),A */
                mem_write8(getpair(RR_HL), reg[REG_A]);
                incpair(RR_HL);
                break;
            case 052:	/* LD A,(HL+) */
                reg[REG_A] = mem_read8(getpair(RR_HL));
                incpair(RR_HL);
                break;
            case 062:	/* LD (HL-),A */
                mem_write8(getpair(RR_HL), reg[REG_A]);
                decpair(RR_HL);
                break;
            case 072:	/* LD A,(HL-) */
                reg[REG_A] = mem_read8(getpair(RR_HL));
                decpair(RR_HL);
                break;
        }
        break;
    case 3:
        if (q == 0)
            incpair(p);
        else
            decpair(p);
        break;
    case 4:
        n = getreg(y);
        setreg(y, ++n);
        reg[REG_F] &= ~(F_S|F_Z|F_H);
        if (!(n & 0x0F))
            reg[REG_F] |= F_H;
        if (n == 0)
            reg[REG_F] |= F_Z;
        break;
    case 5:
        n = getreg(y);
        setreg(y, --n);
        reg[REG_F] &= ~(F_Z|F_H);
        if ((n & 0x0F) == 0x0F)
            reg[REG_F] |= F_H;
        if (n == 0)
            reg[REG_F] |= F_Z;
        break;
    case 6:
        setreg(y, next());
        break;
    case 7:
        /* shifts */
        switch(y) {
        case 0:	/* RLCA */
            reg[REG_F] = 0;
            n = reg[REG_A];
            reg[REG_A] <<= 1;
            if (n & 0x80) {
                reg[REG_A] |= 0x01;
                reg[REG_F] |= F_C;
            }
            break;
        case 1:	/* RRCA */
            reg[REG_F] = 0;
            n = reg[REG_A];
            reg[REG_A] >>= 1;
            if (n & 0x01) {
                reg[REG_A] |= 0x80;
                reg[REG_F] |= F_C;
            }
            break;
        case 2:	/* RLA */
            n = reg[REG_A];
            reg[REG_A] <<= 1;
            if (reg[REG_F] & F_C)
                reg[REG_A] |= 1;
            reg[REG_F] &= ~F_C;
            if (n & 0x80)
                reg[REG_F] |= F_C;
            break;
        case 3:	/* RRA */
            n = reg[REG_A];
            reg[REG_A] >>= 1;
            if (reg[REG_F] & F_C)
                reg[REG_A] |= 0x80;
            reg[REG_F] &= ~F_C;
            if (n & 0x1)
                reg[REG_F] |= F_C;
            break;
        case 4:	/* DAA */
            addr = reg[REG_A];	/* We need the overflow bits */
            reg[REG_F] &= ~F_Z;	/* Will compute this later */
            if (reg[REG_F] & F_S) {	/* Subtract */
                if (reg[REG_F] & F_H)
                    addr -= 0x06;
                if (reg[REG_F] & F_C)
                    addr -= 0x60;
            } else {	/* Addition */
                if ((reg[REG_F] & F_H) || (addr & 0x0F) > 0x09)
                    addr += 0x06;
                if ((reg[REG_F] & F_C) || (addr & 0xFF) > 0x9F)
                    addr += 0x60;
            }
            reg[REG_F] &= ~(F_C|F_Z|F_H);
            /* Now adjust flags */
            if (addr & 0x100)
                reg[REG_F] |= F_C;
            addr &= 0xFF;
            if (addr == 0)
                reg[REG_F] |= F_Z;
            break;
        case 5:	/* CPL */
            reg[REG_A] = ~reg[REG_A];
            reg[REG_F] |= F_S | F_H;
            break;
        case 6:	/* SCF */
            reg[REG_F] &= ~(F_S|F_H);
            reg[REG_F] |= F_C;
            break;
        case 7:	/* CCF */
            reg[REG_F] &= ~(F_S|F_H);
            reg[REG_F] ^= F_C;
            break;
        }
        break;
    }
}
 
static void page1(void)
{
    if (y == z && y == REG_M)
        sm83_halted();
    setreg(y, getreg(z));	/* handles (HL) */
}

static void page2(void)
{
    uint8_t n = getreg(z);
    alu8_op(y, n);
}

/* TODO: review needed */
static void alu_add_sp(unsigned r, uint8_t ob)
{
    int16_t v = (int8_t)ob;
    reg[REG_F] = 0;
    /* Do the low byte with flags */
    reg[r] = alu_adc(reg[REG_SP], v & 0xFF);
    /* Now do high byte */
    r--;
    reg[r] = reg[REG_SPH];
    if (reg[REG_F] & F_C)
        reg[r]++;
    reg[r] += v >> 8;
}

/* This gets a bit more complicated */
static void page3(void)
{
    switch(z) {
    case 0:
        /* Upper half is different to 8080
            LDH (A8),A ADD SP,E8 LDH A,(A8) LD HL,SP+e8 */
        if (y < 4)
            do_ret(test_cc(y));
        switch(y) {
        case 4:
            mem_write8(0xFF00 + next(), reg[REG_A]);
            break;
        case 5:
            /* ADD SP,e updates the flags based upon the low byte
               operation. Presumably the upper half is an incrementer
               only */
            alu_add_sp(REG_SP, next());
            break;
        case 6:
            reg[REG_A] = mem_read8(0xFF00 + next());
            break;
        case 7:	/* LD HL,SP+e basically ADD SP,e with a different target */
            alu_add_sp(REG_L, next());
            break;
        }
        break;
    case 1:
        if (q == 0) {
            uint16_t n = pop16();
            setpair(p, n);
            break;
        } else {
            switch(p) {
            case 0:
                do_ret(1);
                break;
            case 1:	/* RETI Specific to SM83 */
                ime = 1;
                do_ret(1);
                break;
            case 2:	/* PCHL */
                pc = getpair(RR_HL);
                break;
            case 3:	/* SPHL */
                reg[REG_SP] = reg[REG_L];
                reg[REG_SPH] = reg[REG_H];
                break;
            }
        }
        break;
    case 2:
        /* Upper half is different to 8080
            LDH (C),A LD (A16),A LDH A,(C) LD A,(A16) */
        if (y < 4)
            do_jp(test_cc(y));
        switch(y) {
        case 4:
            mem_write8(0xFF00 + reg[REG_C], reg[REG_A]);
            break;
        case 5:
            mem_write8(next16(), reg[REG_A]);
            break;
        case 6:
            reg[REG_A] = mem_read8(0xFF00 + reg[REG_C]);
            break;
        case 7:
            reg[REG_A] = mem_read8(next16());
            break;
        }
        break;
    case 3:
        /* Real mix on 8080 but only DI EI and CB on SM83 */
        switch(ir) {
        case 0xC3:
            do_jp(1);
            break;
        case 0xF3:
            ime = 0;
            break;
        case 0xFB:
            ime = 1;
            break;
        case 0xCB:
            prefix_cb = 1;
            break;
        default:
            invalid();
        }
        break;
    case 4:
        if (y > 1)
            invalid();	/* Other conditions missing on SM83 */
        do_call(test_cc(y));
        break;
    case 5:
        /* Again cut down compared to 8080 */
        if (q == 0) {
            uint16_t n = getpair(p);
            push16(n);
        } else if (ir == 0xCD)
            do_call(1);
        else
            invalid();
        break;
    case 6:
        alu8_op(y, next());
        break;
    case 7:
        pc = y << 3;
        break;
    }
}

static void do_rot(void)
{
    uint8_t v;
    uint8_t m;
    /* Operation Y in reg Z */
    m = getreg(z);
    switch(y) {
    case 0:	/* RLC */
        v = m;
        reg[REG_F] = 0;
        if (m & 0x80)
            reg[REG_F] |= F_C;
        m <<= 1;
        if (v & 0x80)
            m |= 0x01;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 1:	/* RRC */
        v = m;
        reg[REG_F] = 0;
        if (m & 0x01)
            reg[REG_F] |= F_C;
        m >>= 1;
        if (v & 1)
            m |= 0x80;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 2:	/* RL */
        v = m & 0x80;
        m <<= 1;
        if (reg[REG_F] & F_C)
            m |= 0x01;
        reg[REG_F] = v ? F_C : 0;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 3:	/* RR */
        v = m & 1;
        m >>= 1;
        if (reg[REG_F] & F_C)
            m |= 0x80;
        reg[REG_F] = v ? F_C : 0;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 4:	/* SLA */
        reg[REG_F] = 0;
        if (m & 0x80)
            reg[REG_F] = F_C;
        m <<= 1;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 5:	/* SRA */
        reg[REG_F] = 0;
        if (m & 1)
            reg[REG_F] = F_C;
        m >>= 1;
        if (m & 0x40)
            m |= 0x80;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 6:	/* SWAP */
        reg[REG_F] = 0;
        m = ((m >> 4) & 0x0F) | ((m & 0x0F) << 4);
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    case 7:	/* SRL */
        reg[REG_F] = 0;
        if (m & 1)
            reg[REG_F] = F_C;
        m >>= 1;
        if (m == 0)
            reg[REG_F] |= F_Z;
        break;
    }
    setreg(z, m);
}

static void do_bit(void)
{
    uint8_t m = getreg(z);
    if (m & (1 << y))
        reg[REG_F] = F_H;
    else
        reg[REG_F] = F_H | F_Z;
}

static void do_res(void)
{
    uint8_t m = getreg(z);
    m &= ~(1 << y);
    setreg(z, m);
}

static void do_set(void)
{
    uint8_t m = getreg(z);
    m |= 1 << y;
    setreg(z, m);
}

/* No weird DD CB etc */
static void pagecb(void)
{
    switch(x) {
    case 0:
        do_rot();
        break;
    case 1:
        do_bit();
        break;
    case 2:
        do_res();
        break;
    case 3:
        do_set();
        break;
    }
    prefix_cb = 0;
}

static void execute_op(void)
{
    ir = next();
    x = (ir >> 6) & 3;
    y = (ir >> 3) & 7;
    z = ir & 7;
    p = y >> 1;
    q = y & 1;

    if (prefix_cb)
        pagecb();
    else {
        switch(x) {
        case 0x00:
            page0();
            break;
        case 0x01:
            page1();
            break;
        case 0x02:
            page2();
            break;
        case 0x03:
            page3();
            break;
        }
    }
}


/* Disassembly */

/* Turn an opcode into a string with upper case letters to be substituted

    B	bit number in Y
    C	condition code in (Y & 3)
    I	8bit signed
    N	8bit unsigned
    NN	16bit unsigned
    P	register pair in P (BC DE HL AF)
    R	register in Y
    R2	register pair in P (BC DE HL SP)
    Y	Y in RST form
    Z	register in Z
*/

static uint16_t dis_pc;

static uint8_t dis_next(void)
{
    return mem_read8_debug(dis_pc++);
}

static uint16_t dis_next16(void)
{
    uint16_t r = mem_read8_debug(dis_pc++);
    r |= mem_read8_debug(dis_pc++) << 8;
    return r;
}

static const char *rpair_name[4] = { "bc", "de", "hl", "af" };
static const char *rpair2_name[4] = { "bc", "de", "hl", "sp" };
static const char *cc_c[4] =  { "nz", "z", "nc", "c" };
static const char *regname[8] = {
    "b", "c", "d", "e", "h", "l", "(hl)", "a"
};

static void print_disasm(const char *ptr)
{
    while(*ptr) {
        if (!isupper(*ptr))
            fputc(*ptr, stderr);
        else switch(*ptr) {
        case 'B':
            fprintf(stderr, "%d", y);
            break;
        case 'C':
            fputs(cc_c[y & 3], stderr);
            break;
        case 'I':
            fprintf(stderr, "%d", (int8_t)dis_next());
            break;
        case 'N':
            if (ptr[1] == 'N') {
                fprintf(stderr, "0x%04X", dis_next16());
                ptr++;
            } else
                fprintf(stderr, "0x%02X", dis_next());
            break;
        case 'P':
            fputs(rpair_name[p], stderr);
            break;
        case 'R':
            if (ptr[1] == '2') {
                fputs(rpair2_name[p], stderr);
                ptr++;
            } else
                fputs(regname[y], stderr);
            break;
        case 'Y':
            fprintf(stderr, "%d", y << 3);
            break;
        case 'Z':
            fputs(regname[z], stderr);
            break;
        default:
            error("bad disasm");
        }
        ptr++;
    }
}

static const char *dis_page0(void)
{
    switch(z) {
    case 0:
        switch(y) {
        case 0:
            return "nop";
        case 1:
            /* SM83 quirk */
            /* ld (nnnn),sp - the ony 16bit store of reg it has */
            return "ld (NN),sp";
            break;
        case 2:
            /* STOP n8 SM83 specific */
            return "stop";
        case 3:
            return "jr I";
            break;
        case 4:
        case 5:
        case 6:
        case 7:
            return "jr C,I";
            break;
        }
        break;
    case 1:
        if (q == 0)
            return "ld R2, NN";
        else
            return "add hl, R2";
        break;
    case 2:
        switch(ir) {
            case 002:
                return "ld (bc),a";
            case 012:
                return "ld a,(bc)";
            case 022:
                return "ld (de),a";
            case 032:
                return "ld a,(de)";
            /* These are not the same as 8080 */
            case 042:	/* LD (HL+),A */
                return "ld (hl+),a";
            case 052:	/* LD A,(HL+) */
                return "ld a,(hl+)";
            case 062:	/* LD (HL-),A */
                return "ld (hl-),a";
            case 072:	/* LD A,(HL-) */
                return "ld a,(hl-)";
        }
        break;
    case 3:
        if (q == 0)
            return ("inc R2");
        else
            return ("dec R2");
        break;
    case 4:
        return "inc R";
    case 5:
        return "dec R";
    case 6:
        return "ld R,N";
    case 7:
        /* shifts */
        switch(y) {
        case 0:
            return "rlca";
        case 1:
            return "rrca";
        case 2:
            return "rla";
        case 3:
            return "rra";
        case 4:
            return "daa";
        case 5:
            return "cpl";
        case 6:
            return "scf";
        case 7:	/* CCF */
            return "ccf";
        }
        break;
    }
    return "??";
}
 
static const char *dis_page1(void)
{
    if (y == z && y == REG_M)
        return "halt";
    return "ld R,Z";
}

static const char *alun_r[8]= {
    "add a,Z",
    "adc a,Z",
    "sub a,Z",
    "sbc a,Z",
    "and a,Z",
    "xor a,Z",
    "or a,Z",
    "cp a,Z"
};

static const char *alun_i[8]= {
    "add a,N",
    "adc a,N",
    "sub a,N",
    "sbc a,N",
    "and a,N",
    "xor a,N",
    "or a,N",
    "cp a,N"
};

static const char *dis_page3(void)
{
    switch(z) {
    case 0:
        if (y < 4)
            return "ret C";
        switch(y) {
        case 4:
            return "ld (0xffN),a";
        case 5:
            return "add sp,I";
        case 6:
            return "ld a,(0xffN)";
        case 7:	/* LD HL,SP+e basically ADD SP,e with a different target */
            return "ld hl,sp+I";
        }
        break;
    case 1:
        if (q == 0) {
            return "pop P";
        } else {
            switch(p) {
            case 0:
                return "ret";
            case 1:	/* RETI Specific to SM83 */
                return "reti";
            case 2:	/* PCHL */
                return "jp (hl)";
            case 3:	/* SPHL */
                return "ld sp,hl";
            }
        }
        break;
    case 2:
        /* Upper half is different to 8080
            LDH (C),A LD (A16),A LDH A,(C) LD A,(A16) */
        if (y < 4)
            return "jp C,NN";
        switch(y) {
        case 4:
            return "ld (0xff00+c),a";
        case 5:
            return "ld (NN),a";
        case 6:
            return "ld a,(0xff00+c)";
        case 7:
            return "ld a,(NN)";
        }
        break;
    case 3:
        /* Real mix on 8080 but only DI EI and CB on SM83 */
        switch(ir) {
        case 0xC3:
            return "jp NN";
        case 0xF3:
            return "di";
        case 0xFB:
            return "ei";
        case 0xCB:
            prefix_cb = 1;
            break;
        default:
            return "??";
        }
        break;
    case 4:
        if (y > 1)	/* CHECK > 1 or > 3 */
            return "??";
        return "call C,NN";
    case 5:
        /* Again cut down compared to 8080 */
        if (q == 0) {
            return "push P";
        } else if (ir == 0xCD)
            return "call NN";
        else
            return "??";
        break;
    case 6:
        return alun_i[y];
    case 7:
        return "rst Y";
    }
    return "??";
}

static const char *rotn[8] = {
    "rlc Z",
    "rrc Z",
    "rl Z",
    "rr Z",
    "sla Z",
    "sra Z",
    "swap Z",
    "srl Z"
};

/* No weird DD CB etc */
static const char *dis_pagecb(void)
{
    switch(x) {
    case 0:
    /* Operation Y in reg Z */
        return rotn[y];
    case 1:
        return "bit B,Z";
    case 2:
        return "res B,Z";
    case 3:
        return "set B,Z";
    }
    return "??";
}

static void disasm_opcode(void)
{
    unsigned cb = 0;
    const char *map;

    ir = dis_next();
    while (ir == 0xCB) {
        cb = 1; 
        ir = dis_next();
    }
    x = (ir >> 6) & 3;
    y = (ir >> 3) & 7;
    z = ir & 7;
    p = y >> 1;
    q = y & 1;

//    fprintf(stderr,"*IR %02X %o Y %u Z %u\n", ir, ir, y, z);
    if (cb)
        map = dis_pagecb();
    else switch(x) {
    case 0:
        map = dis_page0();
        break;
    case 1:
        map = dis_page1();
        break;
    case 2:
        map = alun_r[y];
        break;
    case 3:
        map = dis_page3();
        break;
    }
    fprintf(stderr, "%04X[%02X]: %02X:%02X %02X%02X %02X%02X %02X%02X %02X%02X : ",
        pc, ir, reg[REG_F], reg[REG_A], reg[REG_B], reg[REG_C],
        reg[REG_D], reg[REG_E], reg[REG_H], reg[REG_L],
        reg[REG_SPH], reg[REG_SP]);
    print_disasm(map);
    fprintf(stderr, "\n");
}

/* We don't care about interrupts, timings etc for a compiler tester */
void sm83_execute(void)
{
    dis_pc = pc;
    /* If prefix_cb is set we already disassembled the full op */
    if (trace && !prefix_cb)
        disasm_opcode();
    execute_op();
}

void sm83_reset(void)
{
    pc = 0;
    ime = 0;
}

void sm83_trace(unsigned debug)
{
    trace = debug;
}
