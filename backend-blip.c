#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "compiler.h"
#include "backend.h"

/*
 *	BLIP code generator (cc2 backend).
 *
 *	Derived from backend-default.c. BLIP is little-endian (isa.md §3), so the
 *	default little-endian data emission is kept. The working value lives in D
 *	(16-bit / pointer) or B (8-bit, the low half of D); BLIP loads/ALU set N,Z
 *	(isa.md §8.5), so conditional branches test the result directly.
 *
 *	STATUS (bring-up): structural code (segments, stack frame, branches, calls,
 *	data) is native BLIP assembly that asblip accepts; arithmetic/loads/stores
 *	currently fall back to helper calls (JSR __op), which need a BLIP support
 *	library to link. The §7 register ABI (args in B/X, 16-bit return in X) and
 *	native arithmetic are the next steps. The emitted syntax is the §4.1 house
 *	style consumed by tools/fcc (asblip).
 */

#define BYTE(x)		(((unsigned)(x)) & 0xFF)
#define WORD(x)		(((unsigned)(x)) & 0xFFFF)

/* So the generic backend knows how to re-type pointers */
unsigned target_ptr = UINT;

/* Bytes the call pushes between the arguments and the locals: the saved
   return address (JSR pushes a 2-byte PC). */
#define ARGBASE 2

/* State for the current function */
static unsigned frame_len;	/* Number of bytes of stack frame */
static unsigned sp;		/* Stack pointer offset tracking */

struct node *gen_rewrite(struct node *n)
{
	return n;
}

struct node *gen_rewrite_node(struct node *n)
{
	/* The driver does not adjust argument offsets - the backend must. An
	   argument at raw offset k is reached at (SP + k + frame_len + ARGBASE):
	   above the locals and the saved return address. frame_len is set by
	   gen_frame, which the driver runs before the body expressions are
	   rewritten, so it is valid here. */
	if (n->op == T_ARGUMENT)
		n->value += frame_len + ARGBASE;
	return n;
}

/* Export the C symbol. namestr/name already carry the leading '_'. */
void gen_export(const char *name)
{
	printf("\t.export %s\n", name);
}

void gen_segment(unsigned s)
{
	switch(s) {
	case A_CODE:
		printf("\t.code\n");
		break;
	case A_DATA:
		printf("\t.data\n");
		break;
	case A_LITERAL:
		printf("\t.literal\n");
		break;
	case A_BSS:
		printf("\t.bss\n");
		break;
	default:
		error("gseg");
	}
}

void gen_prologue(const char *name)
{
	printf("%s:\n", name);
}

/* Allocate the stack frame: SP grows down, so subtract the frame size. */
void gen_frame(unsigned size, unsigned aframe)
{
	frame_len = size;
	sp += size;
	if (size)
		printf("\tLEA SP,SP-%u\n", size);
}

void gen_epilogue(unsigned size, unsigned argsize)
{
	if (sp != size)
		error("sp");
	sp -= size;
	if (size)
		printf("\tLEA SP,SP+%u\n", size);
	/* Return value: 16-bit/pointer in X, 8-bit in B (isa.md §7). The working
	   value is in D; move it to X so a 16-bit return lands in the ABI
	   register. 8-bit returns are already in B (D's low half) and X is
	   caller-saved, so the move is harmless for those; skip it only for void
	   functions where there is no result. */
	if (!(func_flags & F_VOIDRET))
		printf("\tLD X,D\n");
	printf("\tRTS\n");
}

void gen_label(const char *tail, unsigned n)
{
	printf("L%d%s:\n", n, tail);
}

/* Returns 0: we always jump to the shared exit label and let the epilogue
   restore the frame and return. */
unsigned gen_exit(const char *tail, unsigned n)
{
	printf("\tJMP L%d%s\n", n, tail);
	return 0;
}

void gen_jump(const char *tail, unsigned n)
{
	printf("\tJMP L%d%s\n", n, tail);
}

/*
 * Branch on the condition result. The op that produced it leaves N,Z set: a
 * native BLIP LD/ALU sets them (isa.md §8.5), and the boolean/comparison
 * helpers (__bool*, __cc*) are *required* by the BLIP helper ABI to return
 * with N,Z reflecting their result word (see README). So:
 *   LBEQ = branch if Z   = value zero  = condition false
 *   LBNE = branch if !Z  = value nonzero = condition true
 * The long (page-1, rel16) form is used so branch range is never a concern.
 */
void gen_jfalse(const char *tail, unsigned n)
{
	printf("\tLBEQ L%d%s\n", n, tail);
}

void gen_jtrue(const char *tail, unsigned n)
{
	printf("\tLBNE L%d%s\n", n, tail);
}

void gen_switch(unsigned n, unsigned type)
{
	gen_helpcall(NULL);
	printf("switch");
	helper_type(type, 0);
	printf("\n\t.word Sw%d\n", n);
}

void gen_switchdata(unsigned n, unsigned size)
{
	printf("Sw%d:\n", n);
	printf("\t.word %d\n", size);
}

void gen_case_label(unsigned tag, unsigned entry)
{
	printf("Sw%d_%d:\n", tag, entry);
}

void gen_case_data(unsigned tag, unsigned entry)
{
	printf("\t.word Sw%d_%d\n", tag, entry);
}

/* Helper calls: JSR to the C helper. make_node prints the op name + type
   suffix immediately after. */
void gen_helpcall(struct node *n)
{
	printf("\tJSR __");
}

void gen_helptail(struct node *n)
{
}

void gen_helpclean(struct node *n)
{
}

void gen_data_label(const char *name, unsigned align)
{
	printf("%s:\n", name);
}

void gen_space(unsigned value)
{
	printf("\t.ds %d\n", value);
}

void gen_text_data(struct node *n)
{
	printf("\t.word T%d\n", n->snum);
}

void gen_literal(unsigned n)
{
	if (n)
		printf("T%d:\n", n);
}

void gen_name(struct node *n)
{
	printf("\t.word %s+%d\n", namestr(n->snum), WORD(n->value));
}

void gen_value(unsigned type, unsigned long value)
{
	if (PTR(type)) {
		printf("\t.word %u\n", (unsigned) value);
		return;
	}
	switch (type) {
	case CCHAR:
	case UCHAR:
		printf("\t.byte %u\n", (unsigned) value & 0xFF);
		break;
	case CSHORT:
	case USHORT:
		printf("\t.word %d\n", (unsigned) value & 0xFFFF);
		break;
	case CLONG:
	case ULONG:
	case FLOAT:
		/* Little endian: low word first (isa.md §3) */
		printf("\t.word %d\n", (unsigned) (value & 0xFFFF));
		printf("\t.word %d\n", (unsigned) ((value >> 16) & 0xFFFF));
		break;
	default:
		error("unsuported type");
	}
}

void gen_start(void)
{
	printf("\t.code\n");
}

void gen_end(void)
{
}

void gen_tree(struct node *n)
{
	codegen_lr(n);
	printf(";\n");
}

static unsigned get_size(unsigned t)
{
	if (PTR(t))
		return 2;
	if (t == CSHORT || t == USHORT)
		return 2;
	if (t == CCHAR || t == UCHAR)
		return 1;
	if (t == CLONG || t == ULONG || t == FLOAT)
		return 4;
	if (t == CLONGLONG || t == ULONGLONG || t == DOUBLE)
		return 8;
	if (t == VOID)
		return 0;
	error("gs");
	return 0;
}

static unsigned get_stack_size(unsigned t)
{
	unsigned n = get_size(t);
	if (n == 1)
		return 2;
	return n;
}

unsigned gen_push(struct node *n)
{
	/* Push the working value. Bytes are pushed as a word to match the
	   helper stack convention (get_stack_size). */
	unsigned s = get_stack_size(n->type);
	sp += s;
	switch (s) {
	case 2:
		printf("\tPSHS $06\n");	/* D = A:B */
		return 1;
	case 4:
		printf("\tPSHS $26\n");	/* D + Y (high word) */
		return 1;
	default:
		/* fall back to a helper push for unusual sizes */
		return 0;
	}
}

unsigned gen_direct(struct node *n)
{
	switch(n->op) {
	/* Cleanup is special and must be handled here. Its node type is the
	   function return type, so the byte count is in n->right->value. */
	case T_CLEANUP:
		if (n->right->value)
			printf("\tLEA SP,SP+%u\n", (unsigned) n->right->value);
		sp -= n->right->value;
		return 1;
	}
	return 0;
}

unsigned gen_uni_direct(struct node *n)
{
	return 0;
}

unsigned gen_shortcut(struct node *n)
{
	return 0;
}

unsigned gen_node(struct node *n)
{
	/* Account for the left operand the driver evaluated and pushed. This
	   must run for every op, including those we handle natively below, so it
	   is done first. Call arguments are special - they are removed by the
	   call/return sequence and reported via T_CLEANUP, not here. */
	if (n->left && n->op != T_ARGCOMMA && n->op != T_FUNCCALL)
		sp -= get_stack_size(n->left->type);

	/* Native leaf: load a constant into the working register. BLIP LD sets
	   N,Z so a following conditional branch is valid. */
	if (n->op == T_CONSTANT) {
		switch (get_size(n->type)) {
		case 1:
			printf("\tLD B,$%02X\n", (unsigned)(n->value & 0xFF));
			return 1;
		case 2:
			printf("\tLD D,$%04X\n", (unsigned)(n->value & 0xFFFF));
			return 1;
		/* 4-byte constants fall through to the helper for now */
		}
	}
	return 0;
}
