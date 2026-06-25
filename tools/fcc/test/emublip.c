/*
 * emublip.c — standalone, table-driven BLIP instruction-level emulator.
 *
 * Mirrors the Fuzix Compiler Kit's emu85.c structure: a thin machine harness
 * (flat 64 KiB RAM + magic memory-mapped I/O) wrapped around a CPU core with a
 * fetch-decode-execute loop. The decode table (page/byte -> length + trailing
 * kind) is GENERATED from isa/opcodes.toml by
 *   tools/isa/gen_opcodes.py emit-emutab > blip-emutab.h
 * so the decode can never drift from the ratified opcode map (the same
 * discipline as the assembler's blip-optab.h). Execution semantics follow the
 * BLIP execution-semantics reference (CC layout M,-,H,I,N,Z,V,C; per-op-class
 * flag effects; PSHS/PULS high-address-first; LE return addresses; the indexed/
 * auto-inc/dec/accumulator-offset/PC-relative EA rules; branch base = end of
 * instruction).
 *
 * Build / run: see tools/fcc/test/run-testblip.sh.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#include "blip-emutab.h"

/* ── machine state ── */
static uint8_t ram[65536];
static uint8_t A, B, CC;
static uint16_t X, Y, SP, PC;

/* CC bit masks (M,-,H,I,N,Z,V,C). */
#define F_M 0x80
#define F_H 0x20
#define F_I 0x10
#define F_N 0x08
#define F_Z 0x04
#define F_V 0x02
#define F_C 0x01

static int trace = 0;

/* ── D as a 16-bit view of A:B (A high, B low) ── */
static uint16_t getD(void) { return (uint16_t)((A << 8) | B); }
static void setD(uint16_t v) { A = (uint8_t)(v >> 8); B = (uint8_t)v; }

/* ── magic I/O on store (emu85.c-style), avoiding the 0xFFE0+ vector page ── */
static void blip_write(uint16_t addr, uint8_t val)
{
	static uint8_t intlo;
	int x;

	switch (addr) {
	case 0xFF00: /* latch low byte of a 16-bit int to print */
		intlo = val;
		ram[addr] = val;
		return;
	case 0xFF01: /* print signed 16-bit (hi<<8 | lo) as "%d\n" */
		x = (val << 8) | intlo;
		if (x >= 0x8000)
			x -= 0x10000;
		printf("%d\n", x);
		fflush(stdout);
		ram[addr] = val;
		return;
	case 0xFF02: /* putchar */
		putchar(val);
		fflush(stdout);
		ram[addr] = val;
		return;
	case 0xFF03: /* exit(val); nonzero also reports a failure on stderr */
		if (val)
			fprintf(stderr, "***FAIL %d\n", val);
		exit(val);
	default:
		ram[addr] = val;
		return;
	}
}

static uint8_t rd8(uint16_t a) { return ram[a]; }
static void wr8(uint16_t a, uint8_t v) { blip_write(a, v); }
static uint16_t rd16(uint16_t a) /* little-endian */
{
	return (uint16_t)(ram[a] | (ram[(uint16_t)(a + 1)] << 8));
}
static void wr16(uint16_t a, uint16_t v) /* little-endian */
{
	wr8(a, (uint8_t)v);
	wr8((uint16_t)(a + 1), (uint8_t)(v >> 8));
}

/* ── instruction fetch (PC advances) ── */
static uint8_t fetch8(void) { return ram[PC++]; }
static uint16_t fetch16(void)
{
	uint16_t lo = fetch8();
	uint16_t hi = fetch8();
	return (uint16_t)(lo | (hi << 8));
}

/* ── illegal-opcode trap ── */
static void illegal(int page, int byte)
{
	fprintf(stderr,
		"***ILLEGAL opcode page %d byte 0x%02X at PC=0x%04X\n",
		page, byte, (uint16_t)(PC));
	exit(2);
}

/* ── flag helpers ── */
static void set_nz8(uint8_t r)
{
	CC &= ~(F_N | F_Z);
	if (r & 0x80) CC |= F_N;
	if (r == 0)   CC |= F_Z;
}
static void set_nz16(uint16_t r)
{
	CC &= ~(F_N | F_Z);
	if (r & 0x8000) CC |= F_N;
	if (r == 0)     CC |= F_Z;
}
static void setf(uint8_t mask, int cond)
{
	if (cond) CC |= mask; else CC &= ~mask;
}

/* 8-bit add/sub flag computation (full N,Z,V,C,H). carryin used by ADC/SBC. */
static uint8_t add8(uint8_t a, uint8_t b, int cin)
{
	unsigned r = a + b + (cin ? 1 : 0);
	uint8_t res = (uint8_t)r;
	set_nz8(res);
	setf(F_C, r & 0x100);
	setf(F_V, (~(a ^ b) & (a ^ res)) & 0x80);
	setf(F_H, ((a & 0x0F) + (b & 0x0F) + (cin ? 1 : 0)) & 0x10);
	return res;
}
static uint8_t sub8(uint8_t a, uint8_t b, int bin)
{
	unsigned r = a - b - (bin ? 1 : 0);
	uint8_t res = (uint8_t)r;
	set_nz8(res);
	setf(F_C, r & 0x100);               /* borrow */
	setf(F_V, ((a ^ b) & (a ^ res)) & 0x80);
	/* H undefined for SUB/SBC/CMP per spec; leave as-is */
	return res;
}
static uint16_t add16(uint16_t a, uint16_t b, int cin)
{
	unsigned r = a + b + (cin ? 1 : 0);
	uint16_t res = (uint16_t)r;
	set_nz16(res);
	setf(F_C, r & 0x10000);
	setf(F_V, (~(a ^ b) & (a ^ res)) & 0x8000);
	return res;
}
static uint16_t sub16(uint16_t a, uint16_t b, int bin)
{
	unsigned r = a - b - (bin ? 1 : 0);
	uint16_t res = (uint16_t)r;
	set_nz16(res);
	setf(F_C, r & 0x10000);
	setf(F_V, ((a ^ b) & (a ^ res)) & 0x8000);
	return res;
}

/* LD/ST memory|immediate class: N,Z from result, V=0, C/H untouched. */
static void ldst_flags8(uint8_t r) { set_nz8(r); CC &= ~F_V; }
static void ldst_flags16(uint16_t r) { set_nz16(r); CC &= ~F_V; }

/* AND/OR/EOR/BIT/TST/SEX class: N,Z from result, V=0, C/H untouched. */
static void logic_flags8(uint8_t r) { set_nz8(r); CC &= ~F_V; }

/* ── decoded-operand storage for the current instruction ── */
static uint16_t op_imm;   /* imm8/imm16 value (zero-extended) */
static int16_t  op_off;   /* off8/off16 signed offset */
static uint16_t op_abs;   /* abs16 address */
static int16_t  op_rel;   /* rel8/rel16 signed displacement */
static uint8_t  op_mask;  /* mask8 */
static uint8_t  op_sel;   /* movsel */
static uint16_t end_pc;   /* PC at end of instruction (branch/PC-rel base) */

/* ── EA helpers built from a base register + signed offset ── */
static uint16_t ea_add(uint16_t base, int off) { return (uint16_t)(base + off); }

/* accumulator-offset EAs: A/B unsigned 8-bit, D 16-bit, base unchanged */
static uint16_t ea_xa(void)  { return (uint16_t)(X + A); }
static uint16_t ea_xb(void)  { return (uint16_t)(X + B); }
static uint16_t ea_xd(void)  { return (uint16_t)(X + getD()); }
static uint16_t ea_ya(void)  { return (uint16_t)(Y + A); }
static uint16_t ea_yb(void)  { return (uint16_t)(Y + B); }
static uint16_t ea_yd(void)  { return (uint16_t)(Y + getD()); }

/* post-increment / pre-decrement on a named register */
static uint16_t post_inc(uint16_t *r, int n) { uint16_t ea = *r; *r += n; return ea; }
static uint16_t pre_dec(uint16_t *r, int n)  { *r -= n; return *r; }

/* register move selector codes */
#define M_D 0
#define M_X 1
#define M_Y 2
#define M_SP 3
#define M_PC 4
#define M_A 8
#define M_B 9
#define M_CC 0xA

static int sel_is16(int code) { return code <= M_PC; }
static uint16_t sel_get(int code)
{
	switch (code) {
	case M_D: return getD();
	case M_X: return X;
	case M_Y: return Y;
	case M_SP: return SP;
	case M_PC: return PC;
	case M_A: return A;
	case M_B: return B;
	case M_CC: return CC;
	}
	return 0;
}
static void sel_put(int code, uint16_t v)
{
	switch (code) {
	case M_D: setD(v); break;
	case M_X: X = v; break;
	case M_Y: Y = v; break;
	case M_SP: SP = v; break;
	/* M_PC is source-only (D-48); never a destination */
	case M_A: A = (uint8_t)v; break;
	case M_B: B = (uint8_t)v; break;
	case M_CC: CC = (uint8_t)v; break;
	}
}

/* ── PSHS / PULS: high-address-first, low mask bit at low address (TOS) ── */
/* register order by mask bit: CC(0) A(1) B(2) -(3) X(4) Y(5) SP(6) PC(7).
 * SP bit (6) pushes the *other/banked* SP image; in this user-only emulator
 * there is no second bank, so we push/pull SP itself (round-trips). */
/* Final in-memory layout, from the lowest address (new TOS) upward:
 *   CC, B, A, X(LE), Y(LE), SP(LE), PC(LE)
 * i.e. CC (mask bit 0) is lowest, the A/B pair stores as a little-endian D
 * (B at the lower address so reading (SP) recovers D=A:B), and each 16-bit
 * register is little-endian. This matches the spec §3 worked examples
 * (PSHS $06 -> B at TOS, A at TOS+1; PSHS $26 -> D then Y). We achieve it by
 * pushing high-address-first: PC, SP, Y, X, A, B, CC (SP decrements first). */
static void do_pshs(uint8_t mask)
{
	if (mask & 0x80) { SP -= 2; wr16(SP, PC); }
	if (mask & 0x40) { SP -= 2; wr16(SP, SP /*banked image; see note*/); }
	if (mask & 0x20) { SP -= 2; wr16(SP, Y); }
	if (mask & 0x10) { SP -= 2; wr16(SP, X); }
	if (mask & 0x02) { SP -= 1; wr8(SP, A); }
	if (mask & 0x04) { SP -= 1; wr8(SP, B); }
	if (mask & 0x01) { SP -= 1; wr8(SP, CC); }
}
static void do_puls(uint8_t mask)
{
	/* pull in reverse of the push: CC, B, A, X, Y, SP, PC */
	if (mask & 0x01) { CC = rd8(SP); SP += 1; }
	if (mask & 0x04) { B = rd8(SP); SP += 1; }
	if (mask & 0x02) { A = rd8(SP); SP += 1; }
	if (mask & 0x10) { X = rd16(SP); SP += 2; }
	if (mask & 0x20) { Y = rd16(SP); SP += 2; }
	if (mask & 0x40) { /* banked SP image */ (void)rd16(SP); SP += 2; }
	if (mask & 0x80) { PC = rd16(SP); SP += 2; }
}

/* ── branch condition tests ── */
static int cond_taken(int byte_lo)
{
	int N = !!(CC & F_N), Z = !!(CC & F_Z), V = !!(CC & F_V), C = !!(CC & F_C);
	switch (byte_lo) {
	case 0: return 1;                 /* BRA  / LBRA */
	case 1: return 0;                 /* BRN  / LBRN */
	case 2: return !C && !Z;          /* BHI  */
	case 3: return C || Z;            /* BLS  */
	case 4: return !C;                /* BCC  */
	case 5: return C;                 /* BCS  */
	case 6: return !Z;                /* BNE  */
	case 7: return Z;                 /* BEQ  */
	case 8: return !V;                /* BVC  */
	case 9: return V;                 /* BVS  */
	case 10: return !N;               /* BPL  */
	case 11: return N;                /* BMI  */
	case 12: return !(N ^ V);         /* BGE  */
	case 13: return (N ^ V);          /* BLT  */
	case 14: return !Z && !(N ^ V);   /* BGT  */
	case 15: return Z || (N ^ V);     /* BLE  */
	}
	return 0;
}

/* push a 16-bit return address (LE, SP grows down) and jump */
static void call(uint16_t target)
{
	SP -= 2;
	wr16(SP, end_pc);
	PC = target;
}

/* shift/rotate result+flags for an 8-bit value; op selects the kind */
enum { SH_LSR, SH_ASR, SH_ASL, SH_ROL, SH_ROR };
static uint8_t shift8(uint8_t v, int kind)
{
	uint8_t r;
	int cout;
	int cin = CC & F_C;
	switch (kind) {
	case SH_LSR: cout = v & 1; r = v >> 1; break;
	case SH_ASR: cout = v & 1; r = (uint8_t)((v >> 1) | (v & 0x80)); break;
	case SH_ASL: cout = v & 0x80; r = (uint8_t)(v << 1); break;
	case SH_ROL: cout = v & 0x80; r = (uint8_t)((v << 1) | (cin ? 1 : 0)); break;
	case SH_ROR: cout = v & 1; r = (uint8_t)((v >> 1) | (cin ? 0x80 : 0)); break;
	default: r = v; cout = 0; break;
	}
	set_nz8(r);
	setf(F_C, cout);
	/* V = N xor C (shift class) */
	setf(F_V, (!!(r & 0x80)) ^ (!!(cout)));
	return r;
}

/* ── the step: fetch one instruction, decode via table, execute ── */
static void blip_step(void)
{
	uint16_t start = PC;
	int page = 0;
	int byte = fetch8();
	if (byte == 0x80) { page = 1; byte = fetch8(); }

	const struct emuop *e = &blip_emutab[page][byte];
	if (!e->valid)
		illegal(page, byte);

	/* fetch the trailing operand per the generated kind */
	op_imm = 0; op_off = 0; op_abs = 0; op_rel = 0; op_mask = 0; op_sel = 0;
	switch (e->kind) {
	case EK_NONE: break;
	case EK_IMM8: op_imm = fetch8(); break;
	case EK_IMM16: op_imm = fetch16(); break;
	case EK_OFF8: op_off = (int8_t)fetch8(); break;
	case EK_OFF16: op_off = (int16_t)fetch16(); break;
	case EK_ABS16: op_abs = fetch16(); break;
	case EK_REL8: op_rel = (int8_t)fetch8(); break;
	case EK_REL16: op_rel = (int16_t)fetch16(); break;
	case EK_MASK8: op_mask = fetch8(); break;
	case EK_MOVSEL: op_sel = fetch8(); break;
	}
	end_pc = PC; /* base for branches and PC-relative EAs */

	if (trace)
		fprintf(stderr,
			"%04X: [%d:%02X] %-14s A=%02X B=%02X X=%04X Y=%04X SP=%04X CC=%02X\n",
			start, page, byte, e->mnem, A, B, X, Y, SP, CC);

	int key = (page << 8) | byte;
	switch (key) {

	/* ───────────────────── page 0 ───────────────────── */

	/* Byte loads into A (0x00..0x0A) */
	case 0x000: A = (uint8_t)op_imm; ldst_flags8(A); break;
	case 0x001: A = rd8(ea_add(SP, op_off)); ldst_flags8(A); break;
	case 0x002: A = rd8(SP); ldst_flags8(A); break;
	case 0x003: A = rd8(X); ldst_flags8(A); break;
	case 0x004: A = rd8(ea_add(X, op_off)); ldst_flags8(A); break;
	case 0x005: A = rd8(post_inc(&X, 1)); ldst_flags8(A); break;
	case 0x006: A = rd8(ea_xd()); ldst_flags8(A); break;
	case 0x007: A = rd8(op_abs); ldst_flags8(A); break;
	case 0x008: A = rd8(Y); ldst_flags8(A); break;
	case 0x009: A = rd8(post_inc(&Y, 1)); ldst_flags8(A); break;
	case 0x00A: A = rd8(ea_add(Y, op_off)); ldst_flags8(A); break;
	/* Byte loads into B (0x0B..0x15) */
	case 0x00B: B = (uint8_t)op_imm; ldst_flags8(B); break;
	case 0x00C: B = rd8(ea_add(SP, op_off)); ldst_flags8(B); break;
	case 0x00D: B = rd8(SP); ldst_flags8(B); break;
	case 0x00E: B = rd8(X); ldst_flags8(B); break;
	case 0x00F: B = rd8(ea_add(X, op_off)); ldst_flags8(B); break;
	case 0x010: B = rd8(post_inc(&X, 1)); ldst_flags8(B); break;
	case 0x011: B = rd8(ea_xd()); ldst_flags8(B); break;
	case 0x012: B = rd8(op_abs); ldst_flags8(B); break;
	case 0x013: B = rd8(Y); ldst_flags8(B); break;
	case 0x014: B = rd8(post_inc(&Y, 1)); ldst_flags8(B); break;
	case 0x015: B = rd8(ea_add(Y, op_off)); ldst_flags8(B); break;
	/* Byte stores from A (0x16..0x1D) */
	case 0x016: wr8(ea_add(SP, op_off), A); ldst_flags8(A); break;
	case 0x017: wr8(X, A); ldst_flags8(A); break;
	case 0x018: wr8(ea_add(X, op_off), A); ldst_flags8(A); break;
	case 0x019: wr8(post_inc(&X, 1), A); ldst_flags8(A); break;
	case 0x01A: wr8(op_abs, A); ldst_flags8(A); break;
	case 0x01B: wr8(Y, A); ldst_flags8(A); break;
	case 0x01C: wr8(ea_add(Y, op_off), A); ldst_flags8(A); break;
	case 0x01D: wr8(post_inc(&Y, 1), A); ldst_flags8(A); break;
	/* Byte stores from B (0x1E..0x25) */
	case 0x01E: wr8(ea_add(SP, op_off), B); ldst_flags8(B); break;
	case 0x01F: wr8(X, B); ldst_flags8(B); break;
	case 0x020: wr8(ea_add(X, op_off), B); ldst_flags8(B); break;
	case 0x021: wr8(post_inc(&X, 1), B); ldst_flags8(B); break;
	case 0x022: wr8(op_abs, B); ldst_flags8(B); break;
	case 0x023: wr8(Y, B); ldst_flags8(B); break;
	case 0x024: wr8(ea_add(Y, op_off), B); ldst_flags8(B); break;
	case 0x025: wr8(post_inc(&Y, 1), B); ldst_flags8(B); break;

	/* 16-bit loads/stores (0x26..0x41) */
	case 0x026: setD(op_imm); ldst_flags16(getD()); break;
	case 0x027: X = op_imm; ldst_flags16(X); break;
	case 0x028: Y = op_imm; ldst_flags16(Y); break;
	case 0x029: SP = op_imm; ldst_flags16(SP); break;
	case 0x02A: setD(rd16(op_abs)); ldst_flags16(getD()); break;
	case 0x02B: X = rd16(op_abs); ldst_flags16(X); break;
	case 0x02C: Y = rd16(op_abs); ldst_flags16(Y); break;
	case 0x02D: wr16(op_abs, getD()); ldst_flags16(getD()); break;
	case 0x02E: wr16(op_abs, X); ldst_flags16(X); break;
	case 0x02F: wr16(op_abs, Y); ldst_flags16(Y); break;
	case 0x030: setD(rd16(X)); ldst_flags16(getD()); break;
	case 0x031: wr16(X, getD()); ldst_flags16(getD()); break;
	case 0x032: setD(rd16(ea_add(X, op_off))); ldst_flags16(getD()); break;
	case 0x033: wr16(ea_add(X, op_off), getD()); ldst_flags16(getD()); break;
	case 0x034: setD(rd16(post_inc(&X, 2))); ldst_flags16(getD()); break;
	case 0x035: wr16(post_inc(&X, 2), getD()); ldst_flags16(getD()); break;
	case 0x036: setD(rd16(ea_add(SP, op_off))); ldst_flags16(getD()); break;
	case 0x037: X = rd16(ea_add(SP, op_off)); ldst_flags16(X); break;
	case 0x038: Y = rd16(ea_add(SP, op_off)); ldst_flags16(Y); break;
	case 0x039: wr16(ea_add(SP, op_off), getD()); ldst_flags16(getD()); break;
	case 0x03A: wr16(ea_add(SP, op_off), X); ldst_flags16(X); break;
	case 0x03B: wr16(ea_add(SP, op_off), Y); ldst_flags16(Y); break;
	case 0x03C: setD(rd16(ea_xd())); ldst_flags16(getD()); break;
	case 0x03D: wr16(ea_xd(), getD()); ldst_flags16(getD()); break;
	case 0x03E: setD(rd16(Y)); ldst_flags16(getD()); break;
	case 0x03F: wr16(Y, getD()); ldst_flags16(getD()); break;
	case 0x040: setD(rd16(ea_add(Y, op_off))); ldst_flags16(getD()); break;
	case 0x041: wr16(ea_add(Y, op_off), getD()); ldst_flags16(getD()); break;

	/* ADD A,... (0x42..0x49) */
	case 0x042: A = add8(A, (uint8_t)op_imm, 0); break;
	case 0x043: A = add8(A, rd8(X), 0); break;
	case 0x044: A = add8(A, rd8(ea_add(X, op_off)), 0); break;
	case 0x045: A = add8(A, rd8(ea_xd()), 0); break;
	case 0x046: A = add8(A, rd8(ea_add(SP, op_off)), 0); break;
	case 0x047: A = add8(A, rd8(op_abs), 0); break;
	case 0x048: A = add8(A, rd8(post_inc(&X, 1)), 0); break;
	case 0x049: A = add8(A, rd8(Y), 0); break;
	/* ADD B,... (0x4A..0x51) */
	case 0x04A: B = add8(B, (uint8_t)op_imm, 0); break;
	case 0x04B: B = add8(B, rd8(X), 0); break;
	case 0x04C: B = add8(B, rd8(ea_add(X, op_off)), 0); break;
	case 0x04D: B = add8(B, rd8(ea_xd()), 0); break;
	case 0x04E: B = add8(B, rd8(ea_add(SP, op_off)), 0); break;
	case 0x04F: B = add8(B, rd8(op_abs), 0); break;
	case 0x050: B = add8(B, rd8(post_inc(&X, 1)), 0); break;
	case 0x051: B = add8(B, rd8(Y), 0); break;
	/* SUB A,... (0x52..0x59) */
	case 0x052: A = sub8(A, (uint8_t)op_imm, 0); break;
	case 0x053: A = sub8(A, rd8(X), 0); break;
	case 0x054: A = sub8(A, rd8(ea_add(X, op_off)), 0); break;
	case 0x055: A = sub8(A, rd8(ea_xd()), 0); break;
	case 0x056: A = sub8(A, rd8(ea_add(SP, op_off)), 0); break;
	case 0x057: A = sub8(A, rd8(op_abs), 0); break;
	case 0x058: A = sub8(A, rd8(post_inc(&X, 1)), 0); break;
	case 0x059: A = sub8(A, rd8(Y), 0); break;
	/* SUB B,... (0x5A..0x61) */
	case 0x05A: B = sub8(B, (uint8_t)op_imm, 0); break;
	case 0x05B: B = sub8(B, rd8(X), 0); break;
	case 0x05C: B = sub8(B, rd8(ea_add(X, op_off)), 0); break;
	case 0x05D: B = sub8(B, rd8(ea_xd()), 0); break;
	case 0x05E: B = sub8(B, rd8(ea_add(SP, op_off)), 0); break;
	case 0x05F: B = sub8(B, rd8(op_abs), 0); break;
	case 0x060: B = sub8(B, rd8(post_inc(&X, 1)), 0); break;
	case 0x061: B = sub8(B, rd8(Y), 0); break;
	/* CMP A,... (0x62..0x67) — flags only */
	case 0x062: sub8(A, (uint8_t)op_imm, 0); break;
	case 0x063: sub8(A, rd8(X), 0); break;
	case 0x064: sub8(A, rd8(ea_add(X, op_off)), 0); break;
	case 0x065: sub8(A, rd8(ea_add(SP, op_off)), 0); break;
	case 0x066: sub8(A, rd8(op_abs), 0); break;
	case 0x067: sub8(A, rd8(Y), 0); break;
	/* CMP B,... (0x68..0x6C) */
	case 0x068: sub8(B, (uint8_t)op_imm, 0); break;
	case 0x069: sub8(B, rd8(X), 0); break;
	case 0x06A: sub8(B, rd8(ea_add(X, op_off)), 0); break;
	case 0x06B: sub8(B, rd8(op_abs), 0); break;
	case 0x06C: sub8(B, rd8(Y), 0); break;
	/* AND A,... (0x6D..0x72) */
	case 0x06D: A &= (uint8_t)op_imm; logic_flags8(A); break;
	case 0x06E: A &= rd8(X); logic_flags8(A); break;
	case 0x06F: A &= rd8(ea_add(X, op_off)); logic_flags8(A); break;
	case 0x070: A &= rd8(op_abs); logic_flags8(A); break;
	case 0x071: A &= rd8(post_inc(&X, 1)); logic_flags8(A); break;
	case 0x072: A &= rd8(Y); logic_flags8(A); break;
	/* AND B,... (0x73..0x78) */
	case 0x073: B &= (uint8_t)op_imm; logic_flags8(B); break;
	case 0x074: B &= rd8(X); logic_flags8(B); break;
	case 0x075: B &= rd8(ea_add(X, op_off)); logic_flags8(B); break;
	case 0x076: B &= rd8(op_abs); logic_flags8(B); break;
	case 0x077: B &= rd8(post_inc(&X, 1)); logic_flags8(B); break;
	case 0x078: B &= rd8(Y); logic_flags8(B); break;
	/* OR A,... (0x79..0x7E) */
	case 0x079: A |= (uint8_t)op_imm; logic_flags8(A); break;
	case 0x07A: A |= rd8(X); logic_flags8(A); break;
	case 0x07B: A |= rd8(ea_add(X, op_off)); logic_flags8(A); break;
	case 0x07C: A |= rd8(op_abs); logic_flags8(A); break;
	case 0x07D: A |= rd8(post_inc(&X, 1)); logic_flags8(A); break;
	case 0x07E: A |= rd8(Y); logic_flags8(A); break;
	/* OR B,... (0x7F, 0x81..0x85; 0x80 is the page prefix) */
	case 0x07F: B |= (uint8_t)op_imm; logic_flags8(B); break;
	case 0x081: B |= rd8(X); logic_flags8(B); break;
	case 0x082: B |= rd8(ea_add(X, op_off)); logic_flags8(B); break;
	case 0x083: B |= rd8(op_abs); logic_flags8(B); break;
	case 0x084: B |= rd8(post_inc(&X, 1)); logic_flags8(B); break;
	case 0x085: B |= rd8(Y); logic_flags8(B); break;

	/* 16-bit ALU on D + wide compare + D shifts (0x86..0x97) */
	case 0x086: setD(add16(getD(), op_imm, 0)); break;
	case 0x087: setD(add16(getD(), rd16(op_abs), 0)); break;
	case 0x088: setD(add16(getD(), rd16(ea_add(SP, op_off)), 0)); break;
	case 0x089: setD(add16(getD(), rd16(X), 0)); break;
	case 0x08A: setD(add16(getD(), rd16(ea_add(X, op_off)), 0)); break;
	case 0x08B: setD(add16(getD(), rd16(ea_xd()), 0)); break;
	case 0x08C: setD(sub16(getD(), op_imm, 0)); break;
	case 0x08D: setD(sub16(getD(), rd16(op_abs), 0)); break;
	case 0x08E: setD(sub16(getD(), rd16(ea_add(SP, op_off)), 0)); break;
	case 0x08F: sub16(getD(), op_imm, 0); break;          /* CMP D,$ */
	case 0x090: sub16(getD(), rd16(op_abs), 0); break;
	case 0x091: sub16(getD(), rd16(ea_add(SP, op_off)), 0); break;
	case 0x092: sub16(X, op_imm, 0); break;               /* CMP X,$ */
	case 0x093: sub16(Y, op_imm, 0); break;               /* CMP Y,$ */
	case 0x094: sub16(SP, op_imm, 0); break;              /* CMP SP,$ */
	case 0x095: { int n = (uint8_t)op_imm; if (n > 16) n = 16;
		uint16_t d = getD();
		for (int i = 0; i < n; i++) {
			setf(F_C, d & 0x8000); d = (uint16_t)(d << 1);
		}
		set_nz16(d); setf(F_V, (!!(d & 0x8000)) ^ (!!(CC & F_C)));
		setD(d); } break;                                  /* ASL D,$n */
	case 0x096: { int n = (uint8_t)op_imm; if (n > 16) n = 16;
		uint16_t d = getD();
		for (int i = 0; i < n; i++) { setf(F_C, d & 1); d = (uint16_t)(d >> 1); }
		set_nz16(d); setf(F_V, (!!(d & 0x8000)) ^ (!!(CC & F_C)));
		setD(d); } break;                                  /* LSR D,$n */
	case 0x097: { int n = (uint8_t)op_imm; if (n > 16) n = 16;
		uint16_t d = getD();
		for (int i = 0; i < n; i++) { setf(F_C, d & 1); d = (uint16_t)((d >> 1) | (d & 0x8000)); }
		set_nz16(d); setf(F_V, (!!(d & 0x8000)) ^ (!!(CC & F_C)));
		setD(d); } break;                                  /* ASR D,$n */

	/* RMW & register-direct unary (0x98..0xB1) */
	case 0x098: { setf(F_V, A == 0x7F); A = (uint8_t)(A + 1); set_nz8(A); } break; /* INC A */
	case 0x099: { setf(F_V, A == 0x80); A = (uint8_t)(A - 1); set_nz8(A); } break; /* DEC A */
	case 0x09A: A = 0; CC &= ~(F_N | F_V | F_C); CC |= F_Z; break;             /* CLR A */
	case 0x09B: set_nz8(A); CC &= ~F_V; break;                                  /* TST A */
	case 0x09C: A = shift8(A, SH_LSR); break;
	case 0x09D: A = shift8(A, SH_ASR); break;
	case 0x09E: A = shift8(A, SH_ASL); break;
	case 0x09F: { setf(F_V, B == 0x7F); B = (uint8_t)(B + 1); set_nz8(B); } break; /* INC B */
	case 0x0A0: { setf(F_V, B == 0x80); B = (uint8_t)(B - 1); set_nz8(B); } break; /* DEC B */
	case 0x0A1: B = 0; CC &= ~(F_N | F_V | F_C); CC |= F_Z; break;             /* CLR B */
	case 0x0A2: set_nz8(B); CC &= ~F_V; break;                                  /* TST B */
	case 0x0A3: B = shift8(B, SH_LSR); break;
	case 0x0A4: B = shift8(B, SH_ASR); break;
	case 0x0A5: B = shift8(B, SH_ASL); break;
	case 0x0A6: { uint8_t v = rd8(X); setf(F_V, v == 0x7F); v++; set_nz8(v); wr8(X, v); } break;
	case 0x0A7: { uint16_t ea = ea_add(X, op_off); uint8_t v = rd8(ea); setf(F_V, v == 0x7F); v++; set_nz8(v); wr8(ea, v); } break;
	case 0x0A8: { uint16_t ea = ea_add(SP, op_off); uint8_t v = rd8(ea); setf(F_V, v == 0x7F); v++; set_nz8(v); wr8(ea, v); } break;
	case 0x0A9: { uint8_t v = rd8(X); setf(F_V, v == 0x80); v--; set_nz8(v); wr8(X, v); } break;
	case 0x0AA: { uint16_t ea = ea_add(X, op_off); uint8_t v = rd8(ea); setf(F_V, v == 0x80); v--; set_nz8(v); wr8(ea, v); } break;
	case 0x0AB: { uint16_t ea = ea_add(SP, op_off); uint8_t v = rd8(ea); setf(F_V, v == 0x80); v--; set_nz8(v); wr8(ea, v); } break;
	case 0x0AC: wr8(X, 0); CC &= ~(F_N | F_V | F_C); CC |= F_Z; break;          /* CLR (X) */
	case 0x0AD: wr8(ea_add(X, op_off), 0); CC &= ~(F_N | F_V | F_C); CC |= F_Z; break;
	case 0x0AE: set_nz8(rd8(X)); CC &= ~F_V; break;                             /* TST (X) */
	case 0x0AF: set_nz8(rd8(ea_add(X, op_off))); CC &= ~F_V; break;
	case 0x0B0: { uint8_t v = rd8(op_abs); setf(F_V, v == 0x7F); v++; set_nz8(v); wr8(op_abs, v); } break;
	case 0x0B1: { uint8_t v = rd8(op_abs); setf(F_V, v == 0x80); v--; set_nz8(v); wr8(op_abs, v); } break;

	/* Control flow — short branches (0xB2..0xC1) */
	case 0x0B2: case 0x0B3: case 0x0B4: case 0x0B5:
	case 0x0B6: case 0x0B7: case 0x0B8: case 0x0B9:
	case 0x0BA: case 0x0BB: case 0x0BC: case 0x0BD:
	case 0x0BE: case 0x0BF: case 0x0C0: case 0x0C1:
		if (cond_taken(byte - 0xB2))
			PC = (uint16_t)(end_pc + op_rel);
		break;
	case 0x0C2: call((uint16_t)(end_pc + op_rel)); break;     /* BSR */
	case 0x0C3: PC = rd16(SP); SP += 2; break;                /* RTS */
	case 0x0C4: PC = op_abs; break;                           /* JMP $nnnn */
	case 0x0C5: PC = X; break;                                /* JMP X */
	case 0x0C6: PC = Y; break;                                /* JMP Y */
	case 0x0C7: PC = rd16(X); break;                          /* JMP (X) */
	case 0x0C8: PC = rd16(ea_add(X, op_off)); break;          /* JMP (X+n8) */
	case 0x0C9: PC = rd16(ea_xd()); break;                    /* JMP (X+D) */
	case 0x0CA: call(op_abs); break;                          /* JSR $nnnn */
	case 0x0CB: call(rd16(X)); break;                         /* JSR (X) */
	case 0x0CC: call(Y); break;                               /* JSR Y */
	case 0x0CD: call(X); break;                               /* JSR X */
	case 0x0CE: call(rd16(ea_add(X, op_off))); break;         /* JSR (X+n8) */
	case 0x0CF: call(rd16(ea_xd())); break;                   /* JSR (X+D) */

	/* System / inherent / LEA / moves (0xD0..0xE8) */
	case 0x0D0: break;                                        /* NOP */
	case 0x0D1: A = (B & 0x80) ? 0xFF : 0x00;                 /* SEX */
		set_nz16(getD()); CC &= ~F_V; break;
	case 0x0D2: { uint16_t p = (uint16_t)(A * B); setD(p);   /* MUL: Z,C only */
		setf(F_Z, p == 0); setf(F_C, B & 0x80); } break;
	case 0x0D3: X = (uint16_t)(X + B); break;                 /* ABX */
	case 0x0D4: do_pshs(op_mask); break;
	case 0x0D5: do_puls(op_mask); break;
	case 0x0D6: CC &= (uint8_t)op_imm; break;                 /* ANDCC (supervisor here) */
	case 0x0D7: CC |= (uint8_t)op_imm; break;                 /* ORCC */
	case 0x0D8: sel_put(M_D, X); break;                      /* LD D,X (CC unaffected) */
	case 0x0D9: X = getD(); break;                           /* LD X,D */
	case 0x0DA: { uint8_t v = rd8(X); set_nz8(v); CC &= ~F_V; wr8(X, 0xFF); } break;          /* TAS (X) */
	case 0x0DB: { uint16_t ea = ea_add(X, op_off); uint8_t v = rd8(ea); set_nz8(v); CC &= ~F_V; wr8(ea, 0xFF); } break;
	case 0x0DC: X = ea_add(X, op_off); setf(F_Z, X == 0); break;   /* LEA X,X+n8 (Z only) */
	case 0x0DD: X = ea_xa(); setf(F_Z, X == 0); break;
	case 0x0DE: X = ea_xb(); setf(F_Z, X == 0); break;
	case 0x0DF: X = ea_xd(); setf(F_Z, X == 0); break;
	case 0x0E0: X = post_inc(&X, 1); setf(F_Z, X == 0); break;     /* LEA X,X+ : EA=X then X+=1 -> net +1 */
	case 0x0E1: X = post_inc(&X, 2); setf(F_Z, X == 0); break;     /* LEA X,X++ -> net +2 */
	case 0x0E2: X = pre_dec(&X, 1); setf(F_Z, X == 0); break;      /* LEA X,-X */
	case 0x0E3: X = ea_add(Y, op_off); setf(F_Z, X == 0); break;
	case 0x0E4: X = ea_add(SP, op_off); setf(F_Z, X == 0); break;
	case 0x0E5: Y = ea_add(Y, op_off); setf(F_Z, Y == 0); break;
	case 0x0E6: Y = ea_add(SP, op_off); setf(F_Z, Y == 0); break;
	case 0x0E7: SP = ea_add(SP, op_off); break;                   /* LEA SP — no flags */
	case 0x0E8: SP = ea_add(X, op_off); break;
	case 0x0E9: { uint16_t t = getD(); sel_put(M_D, Y); Y = t; } break;  /* XCHG D,Y (CC unaffected) */
	case 0x0EA: { uint16_t t = getD(); sel_put(M_D, X); X = t; } break;  /* XCHG D,X (CC unaffected) */

	/* ───────────────────── page 1 ───────────────────── */

	case 0x100: { /* DAA */
		uint8_t a = A; uint8_t add = 0; int c = (CC & F_C);
		if ((a & 0x0F) > 9 || (CC & F_H)) add |= 0x06;
		if (a > 0x99 || c) { add |= 0x60; c = 1; }
		a = (uint8_t)(a + add); A = a; set_nz8(A); setf(F_C, c);
		} break;
	case 0x103: case 0x104: case 0x105: /* SWI/SWI2/SWI3: set I (no vectoring here) */
		CC |= F_I; break;
	case 0x106: CC &= (uint8_t)op_imm; break;                /* CWAI */
	case 0x107: CC |= F_I; break;                            /* SEI */
	case 0x108: CC &= ~F_I; break;                           /* CLI */
	case 0x101: break;                                       /* SYNC */
	case 0x109: fprintf(stderr, "***HALT at %04X\n", start); exit(0); /* HALT */
	case 0x102: /* RTI: pop CC then PC (minimal frame) */
		CC = rd8(SP); SP += 1; PC = rd16(SP); SP += 2; break;
	case 0x10A: case 0x10B: break;                           /* LDMMU/STMMU: no MMU model */
	/* USP-banking moves: model USP as a shadow of SP (single-stack emu) */
	case 0x10C: case 0x10D: case 0x10E:
	case 0x10F: case 0x110: case 0x111:
	case 0x112: case 0x113: case 0x114: break;               /* treat as nop in flat model */

	/* cold TAS */
	case 0x115: { uint8_t v = rd8(Y); set_nz8(v); CC &= ~F_V; wr8(Y, 0xFF); } break;
	case 0x116: { uint16_t ea = ea_add(Y, op_off); uint8_t v = rd8(ea); set_nz8(v); CC &= ~F_V; wr8(ea, 0xFF); } break;
	case 0x117: { uint16_t ea = ea_add(SP, op_off); uint8_t v = rd8(ea); set_nz8(v); CC &= ~F_V; wr8(ea, 0xFF); } break;
	case 0x118: { uint8_t v = rd8(op_abs); set_nz8(v); CC &= ~F_V; wr8(op_abs, 0xFF); } break;

	/* cold LEA (n16 / PC-relative) */
	case 0x119: X = ea_add(X, op_off); setf(F_Z, X == 0); break;          /* LEA X,X+n16 */
	case 0x11A: Y = ea_add(Y, op_off); setf(F_Z, Y == 0); break;          /* LEA Y,Y+n16 */
	case 0x11B: SP = ea_add(SP, op_off); break;                           /* LEA SP,SP+n16 */
	case 0x11C: X = (uint16_t)(end_pc + op_off); setf(F_Z, X == 0); break; /* LEA X,PC+n8 */
	case 0x11D: Y = (uint16_t)(end_pc + op_off); setf(F_Z, Y == 0); break; /* LEA Y,PC+n8 */
	case 0x11E: SP = ea_add(Y, op_off); break;                            /* LEA SP,Y+n8 */

	/* long branches (0x1F..0x2E) */
	case 0x11F: case 0x120: case 0x121: case 0x122:
	case 0x123: case 0x124: case 0x125: case 0x126:
	case 0x127: case 0x128: case 0x129: case 0x12A:
	case 0x12B: case 0x12C: case 0x12D: case 0x12E:
		if (cond_taken(byte - 0x1F))
			PC = (uint16_t)(end_pc + op_rel);
		break;
	case 0x12F: call((uint16_t)(end_pc + op_rel)); break;    /* LBSR */

	/* cold JMP (0x30..0x3A) */
	case 0x130: PC = rd16(ea_add(X, op_off)); break;         /* JMP (X+n16) */
	case 0x131: PC = rd16(ea_xa()); break;
	case 0x132: PC = rd16(ea_xb()); break;
	case 0x133: PC = rd16(Y); break;                         /* JMP (Y) */
	case 0x134: PC = rd16(ea_add(Y, op_off)); break;
	case 0x135: PC = rd16(ea_add(Y, op_off)); break;
	case 0x136: PC = rd16(ea_ya()); break;
	case 0x137: PC = rd16(ea_yb()); break;
	case 0x138: PC = rd16(ea_yd()); break;
	case 0x139: PC = rd16((uint16_t)(end_pc + op_off)); break;
	case 0x13A: PC = rd16((uint16_t)(end_pc + op_off)); break;
	/* cold JSR (0x3B..0x45) */
	case 0x13B: call(rd16(ea_add(X, op_off))); break;
	case 0x13C: call(rd16(ea_xa())); break;
	case 0x13D: call(rd16(ea_xb())); break;
	case 0x13E: call(rd16(Y)); break;
	case 0x13F: call(rd16(ea_add(Y, op_off))); break;
	case 0x140: call(rd16(ea_add(Y, op_off))); break;
	case 0x141: call(rd16(ea_ya())); break;
	case 0x142: call(rd16(ea_yb())); break;
	case 0x143: call(rd16(ea_yd())); break;
	case 0x144: call(rd16((uint16_t)(end_pc + op_off))); break;
	case 0x145: call(rd16((uint16_t)(end_pc + op_off))); break;

	/* cold byte load/store (0x46..0x69) */
	case 0x146: wr8(SP, A); ldst_flags8(A); break;           /* ST A,(SP) */
	case 0x147: wr8(SP, B); ldst_flags8(B); break;           /* ST B,(SP) */
	case 0x148: A = rd8(post_inc(&X, 2)); ldst_flags8(A); break;   /* LD A,(X++) */
	case 0x149: B = rd8(post_inc(&X, 2)); ldst_flags8(B); break;
	case 0x14A: A = rd8(pre_dec(&X, 2)); ldst_flags8(A); break;    /* LD A,(--X) */
	case 0x14B: B = rd8(pre_dec(&X, 2)); ldst_flags8(B); break;
	case 0x14C: A = rd8(pre_dec(&X, 1)); ldst_flags8(A); break;    /* LD A,(-X) */
	case 0x14D: B = rd8(pre_dec(&X, 1)); ldst_flags8(B); break;
	case 0x14E: wr8(post_inc(&X, 2), A); ldst_flags8(A); break;    /* ST A,(X++) */
	case 0x14F: wr8(post_inc(&X, 2), B); ldst_flags8(B); break;
	case 0x150: wr8(pre_dec(&X, 2), A); ldst_flags8(A); break;     /* ST A,(--X) */
	case 0x151: wr8(pre_dec(&X, 2), B); ldst_flags8(B); break;
	case 0x152: wr8(pre_dec(&X, 1), A); ldst_flags8(A); break;     /* ST A,(-X) */
	case 0x153: wr8(pre_dec(&X, 1), B); ldst_flags8(B); break;
	case 0x154: A = rd8(ea_xa()); ldst_flags8(A); break;          /* LD A,(X+A) */
	case 0x155: A = rd8(ea_xb()); ldst_flags8(A); break;          /* LD A,(X+B) */
	case 0x156: B = rd8(ea_xa()); ldst_flags8(B); break;
	case 0x157: B = rd8(ea_xb()); ldst_flags8(B); break;
	case 0x158: wr8(ea_xa(), A); ldst_flags8(A); break;
	case 0x159: wr8(ea_xb(), A); ldst_flags8(A); break;
	case 0x15A: wr8(ea_xd(), A); ldst_flags8(A); break;          /* ST A,(X+D) */
	case 0x15B: wr8(ea_xa(), B); ldst_flags8(B); break;
	case 0x15C: wr8(ea_xb(), B); ldst_flags8(B); break;
	case 0x15D: wr8(ea_xd(), B); ldst_flags8(B); break;
	case 0x15E: A = rd8(ea_add(X, op_off)); ldst_flags8(A); break; /* LD A,(X+n16) */
	case 0x15F: B = rd8(ea_add(X, op_off)); ldst_flags8(B); break;
	case 0x160: wr8(ea_add(X, op_off), A); ldst_flags8(A); break;
	case 0x161: wr8(ea_add(X, op_off), B); ldst_flags8(B); break;
	case 0x162: A = rd8(ea_add(SP, op_off)); ldst_flags8(A); break; /* LD A,(SP+n16) */
	case 0x163: B = rd8(ea_add(SP, op_off)); ldst_flags8(B); break;
	case 0x164: wr8(ea_add(SP, op_off), A); ldst_flags8(A); break;
	case 0x165: wr8(ea_add(SP, op_off), B); ldst_flags8(B); break;
	case 0x166: A = rd8(pre_dec(&Y, 1)); ldst_flags8(A); break;   /* LD A,(-Y) */
	case 0x167: B = rd8(pre_dec(&Y, 1)); ldst_flags8(B); break;
	case 0x168: wr8(pre_dec(&Y, 1), A); ldst_flags8(A); break;    /* ST A,(-Y) */
	case 0x169: wr8(pre_dec(&Y, 1), B); ldst_flags8(B); break;

	/* cold 16-bit load/store (0x6A..0x93) */
	case 0x16A: X = rd16(Y); ldst_flags16(X); break;             /* LD X,(Y) */
	case 0x16B: wr16(Y, X); ldst_flags16(X); break;             /* ST X,(Y) */
	case 0x16C: Y = rd16(X); ldst_flags16(Y); break;            /* LD Y,(X) */
	case 0x16D: wr16(X, Y); ldst_flags16(Y); break;
	case 0x16E: setD(rd16(SP)); ldst_flags16(getD()); break;    /* LD D,(SP) */
	case 0x16F: X = rd16(SP); ldst_flags16(X); break;
	case 0x170: Y = rd16(SP); ldst_flags16(Y); break;
	case 0x171: wr16(SP, getD()); ldst_flags16(getD()); break;
	case 0x172: wr16(SP, X); ldst_flags16(X); break;
	case 0x173: wr16(SP, Y); ldst_flags16(Y); break;
	case 0x174: X = rd16(post_inc(&X, 2)); ldst_flags16(X); break; /* LD X,(X++) */
	case 0x175: Y = rd16(post_inc(&X, 2)); ldst_flags16(Y); break;
	case 0x176: wr16(post_inc(&X, 2), Y); ldst_flags16(Y); break;
	case 0x177: setD(rd16(post_inc(&Y, 2))); ldst_flags16(getD()); break; /* LD D,(Y++) */
	case 0x178: wr16(post_inc(&Y, 2), getD()); ldst_flags16(getD()); break;
	case 0x179: X = rd16(post_inc(&Y, 2)); ldst_flags16(X); break;
	case 0x17A: wr16(post_inc(&Y, 2), X); ldst_flags16(X); break;
	case 0x17B: setD(rd16(pre_dec(&X, 2))); ldst_flags16(getD()); break; /* LD D,(--X) */
	case 0x17C: wr16(pre_dec(&X, 2), getD()); ldst_flags16(getD()); break;
	case 0x17D: wr16(pre_dec(&X, 2), Y); ldst_flags16(Y); break;
	case 0x17E: setD(rd16(pre_dec(&Y, 2))); ldst_flags16(getD()); break;
	case 0x17F: wr16(pre_dec(&Y, 2), getD()); ldst_flags16(getD()); break;
	case 0x180: wr16(pre_dec(&Y, 2), X); ldst_flags16(X); break;
	case 0x181: Y = rd16(ea_add(X, op_off)); ldst_flags16(Y); break; /* LD Y,(X+n8) */
	case 0x182: wr16(ea_add(X, op_off), Y); ldst_flags16(Y); break;
	case 0x183: X = rd16(ea_add(Y, op_off)); ldst_flags16(X); break;
	case 0x184: wr16(ea_add(Y, op_off), X); ldst_flags16(X); break;
	case 0x185: setD(rd16(ea_add(X, op_off))); ldst_flags16(getD()); break; /* LD D,(X+n16) */
	case 0x186: X = rd16(ea_add(X, op_off)); ldst_flags16(X); break;
	case 0x187: wr16(ea_add(X, op_off), getD()); ldst_flags16(getD()); break;
	case 0x188: wr16(ea_add(X, op_off), X); ldst_flags16(X); break;
	case 0x189: setD(rd16(ea_add(SP, op_off))); ldst_flags16(getD()); break; /* LD D,(SP+n16) */
	case 0x18A: X = rd16(ea_add(SP, op_off)); ldst_flags16(X); break;
	case 0x18B: Y = rd16(ea_add(SP, op_off)); ldst_flags16(Y); break;
	case 0x18C: wr16(ea_add(SP, op_off), getD()); ldst_flags16(getD()); break;
	case 0x18D: wr16(ea_add(SP, op_off), X); ldst_flags16(X); break;
	case 0x18E: wr16(ea_add(SP, op_off), Y); ldst_flags16(Y); break;
	case 0x18F: Y = rd16(ea_xd()); ldst_flags16(Y); break;      /* LD Y,(X+D) */
	case 0x190: wr16(ea_xd(), Y); ldst_flags16(Y); break;
	case 0x191: setD(rd16(ea_yd())); ldst_flags16(getD()); break; /* LD D,(Y+D) */
	case 0x192: SP = rd16(op_abs); ldst_flags16(SP); break;     /* LD SP,($nnnn) */
	case 0x193: wr16(op_abs, SP); ldst_flags16(SP); break;      /* ST SP,($nnnn) */

	/* cold byte ALU + ADC/SBC/EOR/BIT (0x94..0xC1) */
	case 0x194: A = add8(A, rd8(SP), 0); break;
	case 0x195: B = add8(B, rd8(SP), 0); break;
	case 0x196: A = sub8(A, rd8(SP), 0); break;
	case 0x197: B = sub8(B, rd8(SP), 0); break;
	case 0x198: sub8(A, rd8(SP), 0); break;                     /* CMP A,(SP) */
	case 0x199: sub8(B, rd8(SP), 0); break;
	case 0x19A: A &= rd8(SP); logic_flags8(A); break;
	case 0x19B: B &= rd8(SP); logic_flags8(B); break;
	case 0x19C: A |= rd8(SP); logic_flags8(A); break;
	case 0x19D: B |= rd8(SP); logic_flags8(B); break;
	case 0x19E: A = add8(A, (uint8_t)op_imm, CC & F_C); break;  /* ADC A,$ */
	case 0x19F: B = add8(B, (uint8_t)op_imm, CC & F_C); break;
	case 0x1A0: A = add8(A, rd8(op_abs), CC & F_C); break;
	case 0x1A1: B = add8(B, rd8(op_abs), CC & F_C); break;
	case 0x1A2: A = add8(A, rd8(X), CC & F_C); break;
	case 0x1A3: B = add8(B, rd8(X), CC & F_C); break;
	case 0x1A4: A = add8(A, rd8(ea_add(X, op_off)), CC & F_C); break;
	case 0x1A5: B = add8(B, rd8(ea_add(X, op_off)), CC & F_C); break;
	case 0x1A6: A = add8(A, rd8(ea_add(SP, op_off)), CC & F_C); break;
	case 0x1A7: B = add8(B, rd8(ea_add(SP, op_off)), CC & F_C); break;
	case 0x1A8: A = sub8(A, (uint8_t)op_imm, CC & F_C); break;  /* SBC A,$ */
	case 0x1A9: B = sub8(B, (uint8_t)op_imm, CC & F_C); break;
	case 0x1AA: A = sub8(A, rd8(op_abs), CC & F_C); break;
	case 0x1AB: B = sub8(B, rd8(op_abs), CC & F_C); break;
	case 0x1AC: A = sub8(A, rd8(X), CC & F_C); break;
	case 0x1AD: B = sub8(B, rd8(X), CC & F_C); break;
	case 0x1AE: A = sub8(A, rd8(ea_add(X, op_off)), CC & F_C); break;
	case 0x1AF: B = sub8(B, rd8(ea_add(X, op_off)), CC & F_C); break;
	case 0x1B0: A = sub8(A, rd8(ea_add(SP, op_off)), CC & F_C); break;
	case 0x1B1: B = sub8(B, rd8(ea_add(SP, op_off)), CC & F_C); break;
	case 0x1B2: A ^= (uint8_t)op_imm; logic_flags8(A); break;   /* EOR A,$ */
	case 0x1B3: B ^= (uint8_t)op_imm; logic_flags8(B); break;
	case 0x1B4: A ^= rd8(op_abs); logic_flags8(A); break;
	case 0x1B5: B ^= rd8(op_abs); logic_flags8(B); break;
	case 0x1B6: A ^= rd8(X); logic_flags8(A); break;
	case 0x1B7: B ^= rd8(X); logic_flags8(B); break;
	case 0x1B8: A ^= rd8(ea_add(X, op_off)); logic_flags8(A); break;
	case 0x1B9: B ^= rd8(ea_add(X, op_off)); logic_flags8(B); break;
	case 0x1BA: logic_flags8(A & (uint8_t)op_imm); break;       /* BIT A,$ */
	case 0x1BB: logic_flags8(B & (uint8_t)op_imm); break;
	case 0x1BC: logic_flags8(A & rd8(op_abs)); break;
	case 0x1BD: logic_flags8(B & rd8(op_abs)); break;
	case 0x1BE: logic_flags8(A & rd8(X)); break;
	case 0x1BF: logic_flags8(B & rd8(X)); break;
	case 0x1C0: logic_flags8(A & rd8(ea_add(X, op_off))); break;
	case 0x1C1: logic_flags8(B & rd8(ea_add(X, op_off))); break;

	/* cold 16-bit ALU & wide compare (0xC2..0xD7) */
	case 0x1C2: setD(add16(getD(), op_imm, CC & F_C)); break;   /* ADC D,$ */
	case 0x1C3: setD(add16(getD(), rd16(op_abs), CC & F_C)); break;
	case 0x1C4: setD(add16(getD(), rd16(ea_add(SP, op_off)), CC & F_C)); break;
	case 0x1C5: setD(add16(getD(), rd16(X), CC & F_C)); break;
	case 0x1C6: setD(add16(getD(), rd16(ea_add(X, op_off)), CC & F_C)); break;
	case 0x1C7: setD(sub16(getD(), op_imm, CC & F_C)); break;   /* SBC D,$ */
	case 0x1C8: setD(sub16(getD(), rd16(op_abs), CC & F_C)); break;
	case 0x1C9: setD(sub16(getD(), rd16(ea_add(SP, op_off)), CC & F_C)); break;
	case 0x1CA: setD(sub16(getD(), rd16(X), CC & F_C)); break;
	case 0x1CB: setD(sub16(getD(), rd16(ea_add(X, op_off)), CC & F_C)); break;
	case 0x1CC: setD(add16(getD(), rd16(post_inc(&X, 2)), 0)); break; /* ADD D,(X++) */
	case 0x1CD: setD(add16(getD(), rd16(pre_dec(&X, 2)), 0)); break;  /* ADD D,(--X) */
	case 0x1CE: setD(sub16(getD(), rd16(X), 0)); break;        /* SUB D,(X) */
	case 0x1CF: setD(sub16(getD(), rd16(ea_add(X, op_off)), 0)); break;
	case 0x1D0: setD(sub16(getD(), rd16(ea_xd()), 0)); break;
	case 0x1D1: sub16(getD(), rd16(X), 0); break;              /* CMP D,(X) */
	case 0x1D2: sub16(getD(), rd16(ea_add(X, op_off)), 0); break;
	case 0x1D3: sub16(X, rd16(op_abs), 0); break;             /* CMP X,($nnnn) */
	case 0x1D4: sub16(Y, rd16(op_abs), 0); break;
	case 0x1D5: sub16(SP, rd16(op_abs), 0); break;
	case 0x1D6: sub16(X, rd16(ea_add(SP, op_off)), 0); break;
	case 0x1D7: sub16(X, rd16(X), 0); break;                  /* CMP X,(X) */

	/* cold unary RMW (0xD8..0xE5) */
	case 0x1D8: { uint8_t v = (uint8_t)(0 - A); setf(F_V, A == 0x80); setf(F_C, A != 0); set_nz8(v); A = v; } break; /* NEG A */
	case 0x1D9: A = (uint8_t)~A; set_nz8(A); CC &= ~F_V; CC |= F_C; break;  /* COM A */
	case 0x1DA: A = shift8(A, SH_ROL); break;
	case 0x1DB: A = shift8(A, SH_ROR); break;
	case 0x1DC: { uint8_t v = (uint8_t)(0 - B); setf(F_V, B == 0x80); setf(F_C, B != 0); set_nz8(v); B = v; } break; /* NEG B */
	case 0x1DD: B = (uint8_t)~B; set_nz8(B); CC &= ~F_V; CC |= F_C; break;  /* COM B */
	case 0x1DE: B = shift8(B, SH_ROL); break;
	case 0x1DF: B = shift8(B, SH_ROR); break;
	case 0x1E0: { uint8_t v = rd8(post_inc(&X, 1)); uint16_t ea = (uint16_t)(X - 1); setf(F_V, v == 0x7F); v++; set_nz8(v); wr8(ea, v); } break; /* INC (X+) */
	case 0x1E1: { uint16_t ea = X; uint8_t v = rd8(ea); X += 1; setf(F_V, v == 0x80); v--; set_nz8(v); wr8(ea, v); } break; /* DEC (X+) */
	case 0x1E2: { uint8_t v = rd8(Y); setf(F_V, v == 0x7F); v++; set_nz8(v); wr8(Y, v); } break; /* INC (Y) */
	case 0x1E3: { uint8_t v = rd8(Y); setf(F_V, v == 0x80); v--; set_nz8(v); wr8(Y, v); } break; /* DEC (Y) */
	case 0x1E4: wr8(Y, 0); CC &= ~(F_N | F_V | F_C); CC |= F_Z; break;       /* CLR (Y) */
	case 0x1E5: set_nz8(rd8(Y)); CC &= ~F_V; break;                          /* TST (Y) */

	default:
		illegal(page, byte);
	}
}

/* ── optional symbol map (argv[2]) for the -d trace ── */
static void load_symbols(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[256];
	if (!f) return;
	while (fgets(line, sizeof line, f)) {
		unsigned addr; char type; char name[17];
		if (sscanf(line, "%x %c %16s", &addr, &type, name) == 3) {
			/* names are accepted but not indexed in this minimal harness */
		}
	}
	fclose(f);
}

int main(int argc, char *argv[])
{
	int fd;
	const char *image, *symmap = NULL;

	if (argc >= 2 && strcmp(argv[1], "-d") == 0) {
		trace = 1;
		argv++; argc--;
	}
	if (argc < 2) {
		fprintf(stderr, "usage: emublip [-d] image [symbolmap]\n");
		exit(1);
	}
	image = argv[1];
	if (argc >= 3) symmap = argv[2];

	fd = open(image, O_RDONLY);
	if (fd == -1) { perror(image); exit(1); }
	if (read(fd, ram, 65536) < 1) {
		fprintf(stderr, "emublip: empty/bad image\n");
		perror(image);
		exit(1);
	}
	close(fd);
	if (symmap) load_symbols(symmap);

	/* reset: flat -b image linked at 0; supervisor mode so CC writes are free */
	A = B = 0;
	X = Y = 0;
	PC = 0;
	SP = 0xFEFF;
	CC = F_M | F_I;

	for (long n = 0; n < 50000000L; n++)
		blip_step();

	fprintf(stderr, "***TIMEOUT (instruction cap reached)\n");
	exit(3);
}
