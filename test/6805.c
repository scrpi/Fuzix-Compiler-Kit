/*
 *	The 6804/5/HC08 are a family of almost 6800 microcontrollers that
 *	live in their own little universe, never quite being 6800 compatible
 *
 *	6805:
 *	The processor removes the B register, the V flag and S becomes an 8bit
 *	stack. X becomes byte sized and some bit and other oddments are
 *	added. Decoding is much simpler so we our implementation is quite
 *	different.
 *
 *	68HC08:
 *	Puts back a 16bit stack and the V flag. X becomes H:X if wanted
 *	for 16bit indexing and various other bits are nailed on to deal
 *	with the stack and the like sensibly.
 *
 *	TODO:
 *	68HC08 extra ops finish
 *	68HC08 extra flags
 *	I/O model
 *	Interrupts and vectoring
 */


#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "6805.h"

#define REG_D		((cpu->a << 8) | (cpu->b))
#define CARRY		(cpu->p & P_C)
#define HALFCARRY	(cpu->p & P_H)

/*
 *	Instruction data and timing
 *	6805, 146805, 68HC08
 */

static struct m6805_instruction inst[256] = {
    /* 0x00 */
    { "brset 0,D,O", { 10, 5, 5 } },
    { "brclr 0,D,O", { 10, 5, 5 } },
    { "brset 1,D,O", { 10, 5, 5 } },
    { "brclr 1,D,O", { 10, 5, 5 } },
    { "brset 2,D,O", { 10, 5, 5 } },
    { "brclr 2,D,O", { 10, 5, 5 } },
    { "brset 3,D,O", { 10, 5, 5 } },
    { "brclr 3,D,O", { 10, 5, 5 } },
    { "brset 4,D,O", { 10, 5, 5 } },
    { "brclr 4,D,O", { 10, 5, 5 } },
    { "brset 5,D,O", { 10, 5, 5 } },
    { "brclr 5,D,O", { 10, 5, 5 } },
    { "brset 6,D,O", { 10, 5, 5 } },
    { "brclr 6,D,O", { 10, 5, 5 } },
    { "brset 7,D,O", { 10, 5, 5 } },
    { "brclr 7,D,O", { 10, 5, 5 } },
    /* 0x10 */
    { "bset 0,D", { 7, 5, 4 } },
    { "bclr 0,D", { 7, 5, 4 } },
    { "bset 1,D", { 7, 5, 4 } },
    { "bclr 1,D", { 7, 5, 4 } },
    { "bset 2,D", { 7, 5, 4 } },
    { "bclr 2,D", { 7, 5, 4 } },
    { "bset 3,D", { 7, 5, 4 } },
    { "bclr 3,D", { 7, 5, 4 } },
    { "bset 4,D", { 7, 5, 4 } },
    { "bclr 4,D", { 7, 5, 4 } },
    { "bset 5,D", { 7, 5, 4 } },
    { "bclr 5,D", { 7, 5, 4 } },
    { "bset 6,D", { 7, 5, 4 } },
    { "bclr 6,D", { 7, 5, 4 } },
    { "bset 7,D", { 7, 5, 4 } },
    { "bclr 7,D", { 7, 5, 4 } },
    /* 0x20 */
    { "bra O", { 4, 3, 3 } },
    { "brn O", { 4, 3, 3 } },
    { "bhi O", { 4, 3, 3 } },
    { "bls O", { 4, 3, 3 } },
    { "bcc O", { 4, 3, 3 } },
    { "bcs O", { 4, 3, 3 } },
    { "bne O", { 4, 3, 3 } },
    { "beq O", { 4, 3, 3 } },
    { "bhcc O", { 4, 3, 3 } },
    { "bhcs O", { 4, 3, 3 } },
    { "bpl O", { 4, 3, 3 } },
    { "bmi O", { 4, 3, 3 } },
    { "bmc O", { 4, 3, 3 } },
    { "bms O", { 4, 3, 3 } },
    { "bil O", { 4, 3, 3 } },
    { "bih O", { 4, 3, 3 } },
    /* 0x30 */
    { "neg D", { 6, 5, 4 } },
    { "cbeq", { 0, 0, 5 } },
    { NULL, { 0, 0, 0 } },
    { "com D", { 6, 5, 4 } },
    { "lsr D", { 6, 5, 4 } },
    { "sthx D", { 0, 0, 4 } },
    { "ror D", { 6, 5, 4 } },
    { "asr D", { 6, 5, 4 } },
    { "lsl D", { 6, 5, 4 } },
    { "rol D", { 6, 5, 4 } },
    { "dec D", { 6, 5, 4 } },
    { "dbnz D,O", { 0, 0, 5 } },
    { "inc D", { 6, 5, 4 } },
    { "tst D", { 6, 4, 3 } },
    { NULL, { 0, 0, 0 } },
    { "clr D", { 6, 5, 3 } },
    /* 0x40 */
    { "nega",{ 4, 3, 1 } },
    { "cbeqa #,O", { 0, 0, 4 } },
    { "mul", { 0, 0, 5 } },
    { "coma",{ 4, 3, 1 } },
    { "lsra",{ 4, 3, 1 } },
    { "ldhx ##", { 0, 0, 3 } },
    { "rora",{ 4, 3, 1 } },
    { "asra",{ 4, 3, 1 } },
    { "lsla",{ 4, 3, 1 } },
    { "rola",{ 4, 3, 1 } },
    { "deca",{ 4, 3, 1 } },
    { "dbnza O", { 0, 0, 3 } },
    { "inca",{ 4, 3, 1 } },
    { "tsta",{ 4, 3, 1 } },
    { "movTODO", { 0, 0, 4 } },	/* DD */
    { "clra",{ 4, 3, 1 } },
    /* 0x50 */
    { "negx",{ 4, 3, 1 } },
    { "cbeqx D,O", { 0, 0, 4 } },
    { "div", { 0, 0, 7 } },
    { "comx",{ 4, 3, 1 } },
    { "lsrx",{ 4, 3, 1 } },
    { "ldhx D", { 0, 0, 4 } },
    { "rorx",{ 4, 3, 1 } },
    { "asrx",{ 4, 3, 1 } },
    { "lslx",{ 4, 3, 1 } },
    { "rolx",{ 4, 3, 1 } },
    { "decx",{ 4, 3, 1 } },
    { "dbnzx", { 0, 0, 3 } },
    { "incx",{ 4, 3, 1 } },
    { "tstx",{ 4, 3, 1 } },
    { "movTODO", { 0, 0, 0 } },	/* DIX+ */
    { "clrx", { 4, 3, 1 } },
    /* 0x60 */
    { "neg 1", { 7, 6, 4 } },
    { "cbeq 1", { 0, 0, 5 } },
    { "nsa", { 0, 0, 3 } },
    { "com 1", { 7, 6, 4 } },
    { "lsr 1", { 7, 6, 4 } },
    { NULL, { 0, 0, 0 } },
    { "ror 1", { 7, 6, 4 } },
    { "asr 1", { 7, 6, 4 } },
    { "lsl 1", { 7, 6, 4 } },
    { "rol 1", { 7, 6, 4 } },
    { "dec 1", { 7, 6, 4 } },
    { "dbnz 1,O", { 0, 0, 5 } },
    { "inc 1", { 7, 6, 4 } },
    { "tst 1", { 7, 5, 3 } },
    { "movTODO", { 0, 0, 3 } },	/* IMD */
    { "clr 1", { 7, 6, 3 } },
    /* 0x70 */
    { "neg X", { 6, 5, 3 } },
    { "cbeq X", { 0, 0, 4 } },
    { "daa", { 0, 0, 2 } },
    { "com X", { 6, 5, 3 } },
    { "lsr X", { 6, 5, 3 } },
    { NULL, 0, 0, },
    { "ror X", { 6, 5, 3 } },
    { "asr X", { 6, 5, 3 } },
    { "lsl X", { 6, 5, 3 } },
    { "rol X", { 6, 5, 3 } },
    { "dec X", { 6, 5, 3 } },
    { "dbnz X,O", { 0, 0, 4 } },
    { "inc X", { 6, 5, 3 } },
    { "tst X", { 6, 4, 2 } },
    { "movTODO", { 0, 0, 4 } },
    { "clr X", { 6, 5, 2 } },
    
    /* 0x80 */
    { "rti", { 9, 9, 7 } },
    { "rts", { 6, 6, 4 } },
    { NULL, { 0, 0, 0 } },
    { "swi", { 11, 10, 9 } },
    { "tap", { 0, 0, 2 } },
    { "tpa", { 0, 0, 1 } },
    { "pula", { 0, 0, 2 } },
    { "psha", { 0, 0, 2 } },
    { "pulx", { 0, 0, 2 } },
    { "pshx", { 0, 0, 2 } },
    { "pulh", { 0, 0, 2 } },
    { "pshh", { 0, 0, 2 } },
    { "clrh", { 0, 0, 1 } },
    { NULL, { 0, 0, 0 } },
    { "stop", { 0, 2, 1 } },
    { "wait", { 0, 2, 1 } },
    /* 0x90 */
    { "bge O", { 0, 0, 3 } },
    { "blt O", { 0, 0, 3 } },
    { "bgt O", { 0, 0, 3 } },
    { "ble O", { 0, 0, 3 } },
    { "txs", { 0, 0, 2 } },
    { "tsx", { 0, 0, 2 } },
    { NULL, { 0, 0, 0 } },
    { "tax", { 2, 2, 1 } },
    { "clc", { 2, 2, 1 } },
    { "sec", { 2, 2, 1 } },
    { "cli", { 2, 2, 1 } },
    { "sei", { 2, 2, 1 } },
    { "rsp", { 2, 2, 1 } },
    { "nop", { 2, 2, 1 } },
    { NULL, { 0, 0, 0 } },
    { "txa", { 2, 2, 1 } },
    /* 0xA0 */
    { "sub #", { 2, 2, 2 } },
    { "cmp #", { 2, 2, 2 } },
    { "sbc #", { 2, 2, 2 } },
    { "cpx #", { 2, 2, 2 } },
    { "and #", { 2, 2, 2 } },
    { "bit #", { 2, 2, 2 } },
    { "lda #", { 2, 2, 2 } },
    { "ais O", { 0, 0, 2 } },	/* HC08 specific tucked into block */
    { "eor #", { 2, 2, 2 } },
    { "adc #", { 2, 2, 2 } },
    { "ora #", { 2, 2, 2 } },
    { "add #", { 2, 2, 2 } },
    { NULL, { 0, 0, 0 } },
    { "bsr #", { 6, 6, 4 } },
    { "ldx #", { 2, 2, 1 } },
    { "aix", { 0, 0, 2 } },		/* HC08 */
    /* 0xB0 */
    { "sub D", { 4, 3, 3 } },
    { "cmp D", { 4, 3, 3 } },
    { "sbc D", { 4, 3, 3 } },
    { "cpx D", { 4, 3, 3 } },
    { "and D", { 4, 3, 3 } },
    { "bit D", { 4, 3, 3 } },
    { "lda D", { 4, 3, 3 } },
    { "sta D", { 5, 4, 3 } },
    { "eor D", { 4, 3, 3 } },
    { "adc D", { 4, 3, 3 } },
    { "ora D", { 4, 3, 3 } },
    { "add D", { 4, 3, 3 } },
    { "jmp D", { 3, 2, 2 } },
    { "jsr D", { 7, 5, 4 } },
    { "ldx D", { 4, 3, 3 } },
    { "stx D", { 5, 4, 3 } },
    /* 0xC0 */
    { "sub E", { 5, 4, 4 } },
    { "cmp E", { 5, 4, 4 } },
    { "sbc E", { 5, 4, 4 } },
    { "cpx E", { 5, 4, 4 } },
    { "and E", { 5, 4, 4 } },
    { "bit E", { 5, 4, 4 } },
    { "lda E", { 5, 4, 4 } },
    { "sta E", { 6, 5, 4 } },
    { "eor E", { 5, 4, 4 } },
    { "adc E", { 5, 4, 4 } },
    { "ora E", { 5, 4, 4 } },
    { "add E", { 5, 4, 4 } },
    { "jmp E", { 4, 3, 3 } },
    { "jsr E", { 8, 6, 6 } },
    { "ldx E", { 5, 4, 4 } },
    { "stx E", { 6, 5, 4 } },
    /* 0xD0 */
    { "sub 2", { 6, 5, 4 } },
    { "cmp 2", { 6, 5, 4 } },
    { "sbc 2", { 6, 5, 4 } },
    { "cpx 2", { 6, 5, 4 } },
    { "and 2", { 6, 5, 4 } },
    { "bit 2", { 6, 5, 4 } },
    { "lda 2", { 6, 5, 4 } },
    { "sta 2", { 7, 6, 4 } },
    { "eor 2", { 6, 5, 4 } },
    { "adc 2", { 6, 5, 4 } },
    { "ora 2", { 6, 5, 4 } },
    { "add 2", { 6, 5, 4 } },
    { "jmp 2", { 5, 4, 4 } },
    { "jsr 2", { 9, 7, 6 } },
    { "ldx 2", { 6, 5, 4 } },
    { "stx 2", { 7, 6, 4 } },
    /* 0xE0 */
    { "sub 1", { 5, 4, 3 } },
    { "cmp 1", { 5, 4, 3 } },
    { "sbc 1", { 5, 4, 3 } },
    { "cpx 1", { 5, 4, 3 } },
    { "and 1", { 5, 4, 3 } },
    { "bit 1", { 5, 4, 3 } },
    { "lda 1", { 5, 4, 3 } },
    { "sta 2", { 6, 5, 3 } },
    { "eor 1", { 5, 4, 3 } },
    { "adc 1", { 5, 4, 3 } },
    { "ora 1", { 5, 4, 3 } },
    { "add 1", { 5, 4, 3 } },
    { "jmp 1", { 4, 3, 3 } },
    { "jsr 1", { 8, 6, 5 } },
    { "ldx 1", { 5, 4, 3 } },
    { "stx 1", { 6, 5, 3 } },
    /* 0xF0 */
    { "sub X", { 4, 3, 2 } },
    { "cmp X", { 4, 3, 2 } },
    { "sbc X", { 4, 3, 2 } },
    { "cpx X", { 4, 3, 2 } },
    { "and X", { 4, 3, 2 } },
    { "bit X", { 4, 3, 2 } },
    { "lda X", { 4, 3, 2 } },
    { "sta X", { 5, 4, 2 } },
    { "eor X", { 4, 3, 2 } },
    { "adc X", { 4, 3, 2 } },
    { "ora X", { 4, 3, 2 } },
    { "add X", { 4, 3, 2 } },
    { "jmp X", { 3, 2, 2 } },
    { "jsr X", { 7, 5, 4 } },
    { "ldx X", { 4, 3, 2 } },
    { "stx X", { 5, 4, 2 } }
};

/*
 *	Debug and trace support
 */

static char *m6805_flags(struct m6805 *cpu)
{
    static char buf[7];
    int i;

    for (i = 0; i < 6; i++) {
        if (cpu->p & (1 << i))
            buf[i] = "CVZNIH"[i];
        else
            buf[i] = '-';
    }
    return buf;
}

static void m6805_cpu_state(struct m6805 *cpu)
{
    if (cpu->type == CPU_68HC08)
        fprintf(stderr, "%04X : %6s %02X|%02X %04X %02X:%02X %04X | ",
            cpu->pc, m6805_flags(cpu), cpu->a, cpu->h, cpu->x, cpu->s);
    else
        fprintf(stderr, "%04X : %6s %02X|%02X %02X %02X | ",
            cpu->pc, m6805_flags(cpu), cpu->a, cpu->x, cpu->s);
}

static void m6805_disassemble(struct m6805 *cpu, uint16_t pc)
{
    uint8_t op = m6805_do_debug_read(cpu, pc++);
    uint16_t data;
    uint16_t addr;
    uint16_t off = 0;
    int pcontent = 0;
    const char *x = NULL;

    m6805_cpu_state(cpu);
    
    x = inst[op].op;
    /* TODO 68HC08 prefixing */

    if (x == NULL) {
        fprintf(stderr, "<ILLEGAL %02X>\n", op);
        return;
    }
    while(*x) {
        switch(*x) {
        case '#':
            /* Immediate byte */
            addr = m6805_do_debug_read(cpu, pc++);
            fprintf(stderr, "%02X", addr);
            break;
        case 'D':
            /* Direct */
            addr = m6805_do_debug_read(cpu, pc++);
            pcontent = 1;
            fprintf(stderr, "%02X", addr);
            break;
        case 'E':
            /* Extended */
            addr = m6805_do_debug_read(cpu, pc++) << 8;
            addr |= m6805_do_debug_read(cpu, pc++);
            pcontent = 1;
            fprintf(stderr, "%04X", addr);
            break;
        case 'O':
            /* Branch */
            data = m6805_do_debug_read(cpu, pc++);
            data = (int8_t)data + pc;
            pcontent = 1;
            fprintf(stderr, "%04X", data);
            /* Indexed */
        case '2':
            off = m6805_do_debug_read(cpu, pc++) << 8;
        case '1':
            off |= m6805_do_debug_read(cpu, pc++);
        case 'X':
            fprintf(stderr, "%04X", off);
            addr += cpu->x;
            pcontent = 1;
            break;
        default:
            fputc(*x, stderr);
            break;
        }
        x++;
    }
    if (pcontent) {
        if (pcontent == 2) {
            data = m6805_do_debug_read(cpu, addr++) << 8;
            data |= m6805_do_debug_read(cpu, addr);
            fprintf(stderr, " [%04X]", data);
        } else {
            fprintf(stderr, " [%02X]", m6805_do_debug_read(cpu, addr));
        }
    }
    fprintf(stderr, "\n");
}

/*
 *	The 6805 stack operations
 */

static void m6805_push(struct m6805 *cpu, uint8_t val)
{
    cpu->s--;
    if (cpu->type != CPU_68HC08)
        cpu->s &= 0xFF;
    m6805_do_write(cpu, cpu->s, val);
}

static void m6805_push16(struct m6805 *cpu, uint16_t val)
{
    m6805_push(cpu, val);
    m6805_push(cpu, val >> 8);
}

static uint8_t m6805_pull(struct m6805 *cpu)
{
    ++cpu->s;
    if (cpu->type != CPU_68HC08)
        cpu->s &= 0xFF;
    return m6805_do_read(cpu, ++cpu->s);
}

static uint16_t m6805_pull16(struct m6805 *cpu)
{
    uint16_t r = m6805_pull(cpu) << 8;
    r |= m6805_pull(cpu);
    return r;
}

static void m6805_push_interrupt(struct m6805 *cpu)
{
    m6805_push16(cpu, cpu->pc);
    m6805_push(cpu, cpu->x);
    if (cpu->type == CPU_68HC08)
        m6805_push(cpu, cpu->h);
    m6805_push(cpu, cpu->a);
    m6805_push(cpu, cpu->p);
}

static int m6805_vector(struct m6805 *cpu, uint16_t vector)
{
    int clocks = 2;
    if (cpu->state == MODE_WAIT) {
        m6805_push_interrupt(cpu);
        if (cpu->type == CPU_68HC08)
            clocks += 12;
        else
            clocks += 10;
    }
    cpu->p |= P_I;
    /* What's the vector Victor ? */
    cpu->pc = m6805_do_read(cpu, vector) << 8;
    cpu->pc |= m6805_do_read(cpu, vector + 1);
    cpu->state = MODE_RUN;
    if (cpu->debug)
        fprintf(stderr, "*** Vector %04X\n", vector);
    return clocks;
}

static int m6805_vector_masked(struct m6805 *cpu, uint16_t vector)
{
    cpu->mode  = MODE_RUN;
    if (cpu->p & P_I)
        return 0;
    return m6805_vector(cpu, vector);
}

/*
 *	The different flag behaviours
 */

/* Set N and Z according to the result only */
static void m6805_flags_nz(struct m6805 *cpu, uint8_t r)
{
    cpu->p &= ~(P_Z|P_N);
    if (r == 0)
        cpu->p |= P_Z;
    if (r & 0x80)
        cpu->p |= P_N;
}

/* 8bit maths operation: ABA ADC ADD */
static uint8_t m6805_maths8(struct m6805 *cpu, uint8_t a, uint8_t b, uint8_t r)
{
    cpu->p &= ~(P_H|P_N|P_Z|P_C|P_V);
    if (r & 0x80)
        cpu->p |= P_N;
    if (r == 0)
        cpu->p |= P_Z;
    if (cpu->type == CPU_68HC08) {
        /* V for addition is (!r & x & m) | (r & !x & !m) */
        if (r & 0x80) {
            if (!((a | b) & 0x80))
                cpu->p |= P_V;
        } else {
            if (a & b & 0x80)
                cpu->p |= P_V;
        }
    }
    /* C for addition is (a & b) | (a & !r) | (b & !r) */
    if (a & b & 0x80)
        cpu->p |= P_C;
    if (a & ~r & 0x80)
        cpu->p |= P_C;
    if (b & ~r & 0x80)
        cpu->p |= P_C;
    /* And half carry for DAA */
    if ((a & b & 0x08) || ((b & ~r) & 0x08) || ((a & ~r) & 0x08))
        cpu->p |= P_H;
    return r;
}

/* 8bit maths operation without half carry - used by most instructions
   only ADC/ADD/ABA support H/C */
static uint8_t m6805_maths8_noh(struct m6805 *cpu, uint8_t a, uint8_t b, uint8_t r)
{
    cpu->p &= ~(P_N|P_Z|P_C|P_V);

    if (cpu->type == CPU_68HC08) {
        /* V for addition is (!r & x & m) | (r & !x & !m) */
        if (r & 0x80) {
            if (!((a | b) & 0x80))
                cpu->p |= P_V;
        } else {
            if (a & b & 0x80)
                cpu->p |= P_V;
        }
    }
    if (r & 0x80)
        cpu->p |= P_N;
    if (r == 0)
        cpu->p |= P_Z;
    if (~a & b & 0x80)
        cpu->p |= P_C;
    if (b & r & 0x80)
        cpu->p |= P_C;
    if (~a & r & 0x80)
        cpu->p |= P_C;
        
    return r;
}

/* 8bit logic */
static void m6805_logic8(struct m6805 *cpu, uint8_t r)
{
    m6805_flags_nz(cpu, r);
}

/* 8bit shifts */
static void m6805_shift8(struct m6805 *cpu, uint8_t r, int c)
{
    m6805_flags_nz(cpu, r);
    cpu->p &= ~P_C;
    if (c)
        cpu->p |= P_C;
}

static uint16_t get_hx(struct m6805 *cpu)
{
    uint16_t r = cpu->x;
    r |= cpu->h << 8;		/* Always set to 0 on HC05 */
    return r;
}

static unsigned is_prefix(unsigned opcode)
{
    if (opcode == 0x9E)
        return 1;
    return 0;
}

static unsigned condition(struct m6805 *cpu, unsigned cond)
{
    switch(cond) {
    case 0x00:	/* RA */
        return 1;
    case 0x01:	/* HI */
        if (cpu->p & (P_C | P_Z))
            return 0;
        return 1;
    case 0x02:	/* CC */
        if (cpu->p & P_C)
            return 0;
        return 1;
    case 0x03:	/* NE */
        if (cpu->p & P_Z)
            return 0;
        return 1;
    case 0x04:	/* HCC */
        if (cpu->p & P_H)
            return 0;
        return 1;
    case 0x05:	/* PL */
        if (cpu->p & P_N)
            return 0;
        return 1;
    case 0x06:	/* MC */
        if (cpu->p & P_I)
            return 0;
        return 1;
    case 0x07:	/* IL*/
        if (extint(cpu))
            return 0;
        return 1;
    }
}

static void branch(struct m6805 *cpu, unsigned opcode)
{
    /* 0x2X where X is the a 3bit condition code and a 1 bit true/false */
    unsigned truth = condition(cpu, (opcode >> 1) & 7);
    int8_t rel;
    truth ^= opcode & 1;
    rel = m6805_do_read(cpu, cpu->pc++);
    if (truth)
        cpu->pc += rel;
}

static void bsetclr(struct m6805 *cpu, unsigned opcode)
{
    unsigned bit = 1 << ((opcode & 0x0E) >> 1);
    uint8_t mem = m6805_do_read(cpu, cpu->pc++);
    if (opcode & 1)
        mem &= ~bit;
    else
        mem |= bit;
}

static void brsetclr(struct m6805 *cpu, unsigned opcode)
{
    unsigned bit = (opcode & 0x0E) >> 1;
    uint8_t mem = m6805_do_read(cpu, cpu->pc++);
    cpu->p &= ~P_C;
    if (mem & (1 << bit))
        cpu->p |= P_C;
    /* Do a carry branch */
    branch(cpu, (opcode & 1) ? 0x24 : 0x2C);
}

static unsigned carry(struct m6805 *cpu)
{
    return (cpu->p & P_C) ? 1 : 0;
}

static uint8_t single_op(struct m6805 *cpu, unsigned opcode, uint8_t v)
{
    unsigned c;

    switch(opcode & 0x0F) {
    case 0x00:	/* negate */
        m6805_maths8_noh(cpu, 0, v, -v);
        v = -v;
        break;
    case 0x01:	/* invalid */
    case 0x02:	/* invalid */
        invalid(cpu, opcode);
    case 0x03:	/* complement */
        v = ~v;
     /* FIXME   m6805_maths8_noh(cpu, 0, v); */
        cpu->p |= P_C;
        break;
    case 0x04:	/* lsr */
        v >>= 1;
        break;
    case 0x05:	/* ?? */
        invalid(cpu, opcode);
    case 0x06:	/* ror */
        c = v & 1;
        v >>= 1;
        if (carry(cpu))
            v |= 0x80;
        m6805_shift8(cpu, v, c);
        break;        
    case 0x07:	/* asr */
        c = v & 1;
        v >>= 1;
        if (v & 0x40)
            v |= 0x80;
        m6805_shift8(cpu, v, c);
        break;        
    case 0x08:	/* lsl */
        c = v & 0x80;
        v <<= 1;
        m6805_shift8(cpu, v, c);
        break;        
    case 0x09:	/* rol */
        c = v & 0x80;
        v <<= 1;
        v |= carry(cpu);
        m6805_shift8(cpu, v, c);
        break;        
    case 0x0A:	/* dec */
        v--;
        m6805_flags_nz(cpu, v);
        break;
    case 0x0B:
        invalid(cpu, opcode);
    case 0x0C:	/* inc */
        v++;
        m6805_flags_nz(cpu, v);
        break;
    case 0x0D:	/* tst */
        m6805_flags_nz(cpu, v);
        break;
    case 0x0E:
        invalid(cpu, opcode);
    case 0x0F:	/* clr */
        /* TODO: Careful - clr is RMW ? */
        m6805_flags_nz(cpu, 0);
        return 0;
    }
    return v;
}

static void dual_operand(struct m6805 *cpu, unsigned opcode, uint16_t addr)
{
    uint8_t val;

    opcode &= 0x0F;

    if (opcode != 0x07 && opcode != 0x0F && opcode != 0x0C && opcode != 0x0D)
        val = m6805_do_read(cpu, addr);

    switch(opcode) {
    case 0x00:	/* SUB */
        cpu->a = m6805_maths8_noh(cpu, cpu->a, val, cpu->a - val);
        return;
    case 0x01:	/* CMP */
        m6805_maths8_noh(cpu, cpu->a, val, cpu->a - val);
        return;
    case 0x02:	/* SBB */
        cpu->a = m6805_maths8_noh(cpu, cpu->a, val, cpu->a - val - carry(cpu));
        return;
    case 0x03:	/* CPX */
        m6805_maths8_noh(cpu, cpu->x, val, cpu->x - val);
        return;
    case 0x04:	/* AND */
        cpu->a &= val;
        m6805_flags_nz(cpu, cpu->a);
        break;
    case 0x05:	/* BIT */
        m6805_flags_nz(cpu, cpu->a & val);
        break;
    case 0x06:	/* LDA */
        m6805_flags_nz(cpu, cpu->a);
        return;
    case 0x07:	/* STA */
        m6805_do_write(cpu, addr, cpu->a);
        m6805_flags_nz(cpu, cpu->a);
        break;
    case 0x08:	/* EOR */
        cpu->a ^= val;
        m6805_flags_nz(cpu, cpu->a);
        break;
    case 0x09:	/* ADC */
        cpu->a = m6805_maths8(cpu, cpu->a, val, cpu->a + val + carry(cpu));
        break;
    case 0x0A:	/* ORA */
        cpu->a |= val;
        m6805_flags_nz(cpu, cpu->a);
        break;
    case 0x0B:	/* ADD */
        cpu->a = m6805_maths8(cpu, cpu->a, val, cpu->a + val);
        break;
    case 0x0D:	/* JSR (PC = ) */
        m6805_push16(cpu, cpu->pc);
        /* Fall through */
    case 0x0C:	/* JMP (PC = ) */
        cpu->pc = addr;
        return;
    case 0x0E:	/* LDX */
        cpu->x = val;
        m6805_flags_nz(cpu, cpu->x);
        break;
    case 0x0F:	/* STX */
        m6805_do_write(cpu, addr, cpu->x);
        m6805_flags_nz(cpu, cpu->x);
        break;
    }
}

static void miscellaneous(struct m6805 *cpu, unsigned op)
{
    switch(op) {
    case 0x80:	/* RTI */
        /* TODO: 68HC08 */
        cpu->p = m6805_pull(cpu);
        cpu->a = m6805_pull(cpu);
        cpu->x = m6805_pull(cpu);
        /* Fall through */
    case 0x81:	/* RTS */
        cpu->pc = m6805_pull16(cpu);
        break;
    case 0x83:	/* SWI */
        m6805_push16(cpu, cpu->pc);
        m6805_push(cpu, cpu->x);
        m6805_push(cpu, cpu->a);
        m6805_push(cpu, cpu->p);
        cpu->p |= P_I;
        cpu->pc = m6805_do_read(cpu, 0xFFFC) << 8;
        cpu->pc |= m6805_do_read(cpu, 0xFFFD);
        break;
    case 0x84:	/* TAP */	
        cpu->p = cpu->a;
        break;
    case 0x85:	/* TPA */	
        cpu->a = cpu->p;
        break;
    case 0x86:	/* PULA */
        cpu->a = m6805_pull(cpu);
        break;
    case 0x87:	/* PSHA */
        m6805_push(cpu, cpu->a);
        break;
    case 0x88:	/* PULX */
        cpu->x = m6805_pull(cpu);
        break;
    case 0x89:	/* PSHX */
        m6805_push(cpu, cpu->x);
        break;
    case 0x8A:	/* PULH */
        cpu->h = m6805_pull(cpu);
        break;
    case 0x8B:	/* PSH */
        m6805_push(cpu, cpu->h);
        break;
    case 0x8C:	/* CLRH */
        cpu->h = 0;
        break;
    case 0x8E:	/* STOP */
        cpu->p &= ~P_I;
        cpu->mode = MODE_STOP;
        break;
    case 0x8F:	/* WAIT */
        cpu->s &= ~P_I;
        cpu->mode = MODE_WAIT;
        break;
    case 0x90:	/* BGE */
    case 0x91:	/* BLT */
    case 0x92:	/* BGT */
    case 0x93:	/* BLE */
        /* TODO */
    case 0x94:	/* TXS (really H:X) */
        cpu->s = cpu->x + (cpu->h << 8);
        break;
    case 0x95:	/* TSX (really H:X) */
        cpu->x = cpu->s;
        cpu->h = cpu->s >> 8;
        break;
    case 0x97:	/* TAX */
        cpu->a = cpu->x;
        break;
    case 0x98:	/* CLC */
        cpu->p &= P_C;
        break;
    case 0x99:	/* SEC */
        cpu->p |= P_C;
        break;
    case 0x9A:	/* CLI */
        cpu->p &= P_I;
        break;
    case 0x9B:	/* SEI */
        cpu->p |= P_I;
        break;
    case 0x9C:	/* RSP */
        cpu->s = 0x7F;
        break;
    case 0x9D:	/* NOP */
        break;
    case 0x9F:	/* TXA */
        cpu->a = cpu->x;
        break;
    default:
        invalid(cpu, op);
    }
}
    
static int m6805_execute_one(struct m6805 *cpu)
{
    uint16_t fetch_pc = cpu->pc;
    uint16_t opcode;
    int clocks;
    uint8_t r;
    uint16_t addr;
    uint16_t idx = cpu->x;
    uint8_t pfx = 0;
    unsigned n;

    if (cpu->type == CPU_68HC08)
        idx |= cpu->h << 8;

    if (cpu->debug)
        m6805_disassemble(cpu, cpu->pc);

    do {
        cpu->pc++;
        pfx = opcode;
        opcode = m6805_do_read(cpu, cpu->pc);
        n = inst[opcode].clocks[cpu->type];
        if (n == 0)
            invalid(cpu, opcode);
        clocks += n;
    } while(is_prefix(opcode));

    /* 68HC08 index versus S prefix */
    if (pfx == 0x9E)
        idx = cpu->s;

    /* opcodes divide into blocks by the first hex digit */
    switch(opcode & 0x80) {
    case 0x00:		/* BRSET/BRCLR */
        /* 5 clocks on CMOS 10 on HMOS */
        brsetclr(cpu, opcode);
        break;
    case 0x10:		/* BSET/BCLR */
        /* 7 and 5 */
        bsetclr(cpu, opcode);
        break;
    case 0x20:		/* Branches */
        /* 4 and 3 */
        branch(cpu, opcode);
        break;
    case 0x30:		/* Single operand direct */
        addr = m6805_do_read(cpu, cpu->pc++);
        r = m6805_do_read(cpu, addr);
        r = single_op(cpu, opcode, r);
        m6805_do_write(cpu, addr, r);
        break;
    case 0x40:		/* Single operand A */
        cpu->a = single_op(cpu, opcode, cpu->a);
        break;
    case 0x50:		/* Single operand X */
        cpu->x = single_op(cpu, opcode, cpu->x);
        break;
    case 0x60:		/* Single operand ,X */
        r = m6805_do_read(cpu, idx);
        r = single_op(cpu, opcode, r);
        m6805_do_write(cpu, idx, r);
        break;
    case 0x70:		/* Single operand .8,x */
        addr = idx + m6805_do_read(cpu, cpu->pc++);
        r = m6805_do_read(cpu, addr);
        r = single_op(cpu, opcode, r);
        m6805_do_write(cpu, addr, r);
        break;
    case 0x80:
    case 0x90:
        miscellaneous(cpu, opcode);
        break;
    case 0xA0:		/* Dual operand A,imm */
        /* Special 0xAD stuffed here like on the 6803 */
        if (opcode == 0xAD) {
            m6805_push16(cpu, cpu->pc);
            cpu->pc += (int8_t)m6805_do_read(cpu, cpu->pc);
            break;
        }
        dual_operand(cpu, opcode, cpu->pc++);
        break;
    case 0xB0:		/* Dual operand A,dir */
        addr = m6805_do_read(cpu, cpu->pc++);
        dual_operand(cpu, opcode, addr);
        break;
    case 0xC0:		/* Dual operand A,ext */
        addr = m6805_do_read(cpu, cpu->pc++) << 8;
        addr |= m6805_do_read(cpu, cpu->pc++);
        dual_operand(cpu, opcode, addr);
        break;
    case 0xD0:		/* Dual operand A,ix2 */
        addr = m6805_do_read(cpu, cpu->pc++) << 8;
        addr |= m6805_do_read(cpu, cpu->pc++);
        dual_operand(cpu, opcode, idx + addr);
        break;
    case 0xE0:		/* Dual operand A,ix1 */
        addr = m6805_do_read(cpu, cpu->pc++);
        dual_operand(cpu, opcode, idx + addr);
        break;
    case 0xF0:		/* Dual operand A,ix */
        dual_operand(cpu, opcode, idx);
        break;
    }
}


/* Exception handling */

/* TODO: timing */

static int m6805_pre_execute(struct m6805 *cpu)
{
    /* TODO */
#if 0
    /* Interrupts are not latched */
    if (cpu->irq & IRQ_NMI) {
        cpu->irq &= ~IRQ_NMI;
        return m6805_vector(cpu, 0xFFFC);
    }

    if (cpu->irq & IRQ_IRQ1)
        return m6805_vector_masked(cpu, 0xFFF8);
    if (cpu->irq & IRQ_ICF)
        return m6805_vector_masked(cpu, 0xFFF6);
    if (cpu->irq & IRQ_OCF)
        return m6805_vector_masked(cpu, 0xFFF4);
    if (cpu->irq & IRQ_TOF)
        return m6805_vector_masked(cpu, 0xFFF2);
    if (cpu->irq & IRQ_SCI)
        return m6805_vector_masked(cpu, 0xFFF0);
#endif        
    return 0;
}


void m6805_clear_interrupt(struct m6805 *cpu, int irq)
{
    cpu->irq &= ~irq;
}

void m6805_raise_interrupt(struct m6805 *cpu, int irq)
{
    cpu->irq |= irq;
}

/*
 *	Execute a machine cycle and return how many clocks
 *	we took doing it.
 */
int m6805_execute(struct m6805 *cpu)
{
    int cycles;
    uint32_t n;
    /* Interrupts ? */
    cycles = m6805_pre_execute(cpu);
    /* A cycle passes but we are waiting */
    if (cpu->state != MODE_RUN)
        cycles = 1;
    else
        cycles += m6805_execute_one(cpu);

    /* Counter I/O goes here */
    return cycles;
}

void m6805_reset(struct m6805 *cpu, int type, int io, int mode)
{
    memset(cpu, 0, sizeof(*cpu));

    cpu->p = P_I;
    cpu->mode = mode;
    cpu->type = type;
    cpu->intio = io;
    cpu->pc = m6805_do_read(cpu, 0xFFFE) << 8;
    cpu->pc |= m6805_do_read(cpu, 0xFFFF);
}

/*
 *	TODO: I/O model
 */

void m6805_do_write(struct m6805 *cpu, uint16_t addr, uint8_t val)
{
    switch (cpu->intio) {
    default:
        m6805_write(cpu, addr, val);
        break;
    }
}

uint8_t m6805_do_debug_read(struct m6805 *cpu, uint16_t addr)
{
    switch (cpu->intio) {
    default:
        return m6805_debug_read(cpu, addr);
    }
}
