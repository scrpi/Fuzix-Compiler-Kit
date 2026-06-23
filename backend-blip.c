#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "compiler.h"
#include "backend.h"

/*
 *	BLIP code generator (cc2 backend).
 *
 *	BLIP is little-endian (isa.md §3). The working value lives in D
 *	(16-bit / pointer) or B (8-bit, the low half of D). BLIP LD/ALU set N,Z
 *	(isa.md §8.5), so conditional branches test the result directly.
 *
 *	This backend generates NATIVE code for the cheap integer operations:
 *	loads/stores of globals and locals (fused at rewrite time into the
 *	T_NREF/T_LREF/T_NSTORE/T_LSTORE ops below), +,-,&,|,^, the six
 *	comparisons, unary -,~,!, T_BOOL, constant shifts, dereference/assign
 *	through a pointer, and direct calls by name. Only multiply/divide/
 *	remainder, long/float, switch and other heavy ops fall back to helper
 *	calls (JSR __op); those need the future support library.
 *
 *	Working-register model:
 *	  - 16-bit / pointer values live in D (A=high, B=low).
 *	  - 8-bit values live in B (the low half of D).
 *	  - X is a scratch pointer (caller-saved). Y is callee-saved and is not
 *	    used here.
 *
 *	"Easy expression" inlining: when the RHS of a binary op is a simple
 *	operand (constant / global / local-arg / address-of-global), gen_direct
 *	emits the op straight against that operand with NO push. When a push is
 *	unavoidable, gen_node operates against the value on the stack and the
 *	stack-relative offset of every (SP+n) access includes the dynamic push
 *	depth (sp), so locals/args stay addressable mid-expression.
 */

/* Code-generator-private node ops (T_USER space) */
#define T_NREF		(T_USER + 0)	/* Load of C global/static value */
#define T_CALLNAME	(T_USER + 1)	/* Function call by name */
#define T_NSTORE	(T_USER + 2)	/* Store to a C global/static */
#define T_LREF		(T_USER + 3)	/* Load of a local/argument value */
#define T_LSTORE	(T_USER + 4)	/* Store to a local/argument */

#define BYTE(x)		(((unsigned)(x)) & 0xFF)
#define WORD(x)		(((unsigned)(x)) & 0xFFFF)

/* So the generic backend knows how to re-type pointers */
unsigned target_ptr = UINT;

/* Bytes the call pushes between the arguments and the locals: the saved
   return address (JSR pushes a 2-byte PC). */
#define ARGBASE 2

/* State for the current function */
static unsigned frame_len;	/* Number of bytes of stack frame */
static unsigned sp;		/* Dynamic push depth (bytes pushed mid-expr) */
static unsigned label;		/* Local label allocator for inline branches */

static unsigned get_size(unsigned t);
static unsigned get_stack_size(unsigned t);
static unsigned shift_const(struct node *n, const char *op16, const char *op8);
static unsigned op_eq_node(struct node *n);
static unsigned post_incdec_node(struct node *n);
static unsigned shifteq_direct(struct node *n);

/*
 *	Size handling
 */
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

/*
 *	Tree rewriting
 */

static void squash_node(struct node *n, struct node *o)
{
	n->value = o->value;
	n->snum = o->snum;
	free_node(o);
}

static void squash_left(struct node *n, unsigned op)
{
	struct node *l = n->left;
	n->op = op;
	squash_node(n, l);
	n->left = NULL;
}

static void squash_right(struct node *n, unsigned op)
{
	struct node *r = n->right;
	n->op = op;
	squash_node(n, r);
	n->right = NULL;
}

/* How easy is this operand to use directly on the right of an op? Higher is
   better; we sort commutative operands so the easy one ends up on the right. */
static unsigned is_simple(struct node *n)
{
	unsigned op = n->op;
	if (op == T_CONSTANT)
		return 10;
	if (op == T_NAME || op == T_NREF)
		return 9;
	if (op == T_LREF)
		return 8;
	return 0;
}

struct node *gen_rewrite(struct node *n)
{
	return n;
}

struct node *gen_rewrite_node(struct node *n)
{
	register struct node *l = n->left;
	register struct node *r = n->right;
	register unsigned op = n->op;
	unsigned nt = n->type;

	/* Eliminate casts that don't change representation (sign-only, pointer
	   conversion, or identical) - matches the kit convention. */
	if (op == T_CAST && r && cast_fold_safe(r->op)) {
		if (nt == r->type || (nt ^ r->type) == UNSIGNED ||
			(PTR(nt) && PTR(r->type))) {
			free_node(n);
			r->type = nt;
			return r;
		}
	}

	/* Argument offsets: the driver does not adjust them, the backend must.
	   An argument at raw offset k is reached at (SP + k + frame_len +
	   ARGBASE): above the locals and the saved return address. This runs
	   bottom-up, so by the time a parent (e.g. T_DEREF) sees a child
	   T_ARGUMENT the child has ALREADY been adjusted - do it exactly once,
	   here, on the bare node. */
	if (op == T_ARGUMENT)
		n->value += frame_len + ARGBASE;

	/* Function call of a plain name -> a direct JSR by name. */
	if (op == T_FUNCCALL && r && r->op == T_NAME && PTR(r->type) == 1) {
		n->op = T_CALLNAME;
		n->snum = r->snum;
		n->value = r->value;
		free_node(r);
		n->right = NULL;
		r = NULL;
	}

	/* Merge a constant offset into an object reference so &obj[const] and
	   struct-field access become a single operand. */
	if (op == T_PLUS && r && r->op == T_CONSTANT &&
		(l->op == T_LOCAL || l->op == T_NAME || l->op == T_ARGUMENT)) {
		l->value += r->value;
		free_node(r);
		free_node(n);
		return l;
	}

	/* Fuse deref of a leaf address into a single load op. */
	if (op == T_DEREF && r) {
		if (r->op == T_NAME) {
			squash_right(n, T_NREF);
			return n;
		}
		if (r->op == T_LOCAL || r->op == T_ARGUMENT) {
			/* r->value already carries the (adjusted) frame offset */
			squash_right(n, T_LREF);
			return n;
		}
	}
	/* Fuse store to a leaf address into a single store op. The value to
	   store is n->right; the destination leaf is n->left. */
	if (op == T_EQ && l) {
		if (l->op == T_NAME) {
			squash_left(n, T_NSTORE);
			return n;
		}
		if (l->op == T_LOCAL || l->op == T_ARGUMENT) {
			squash_left(n, T_LSTORE);
			return n;
		}
	}

	/* Commutative ops: keep the easy-to-use operand on the right so
	   gen_direct can fold it without a push. */
	if (op == T_PLUS || op == T_AND || op == T_OR || op == T_HAT) {
		if (is_simple(n->left) > is_simple(n->right)) {
			n->right = l;
			n->left = r;
		}
	}
	return n;
}

/*
 *	Output helpers
 */

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
	if (size)
		printf("\tLEA SP,SP-%u\n", size);
}

void gen_epilogue(unsigned size, unsigned argsize)
{
	if (sp != 0)
		error("sp");
	if (size)
		printf("\tLEA SP,SP+%u\n", size);
	/* Return value: 16-bit/pointer in X, 8-bit in B (isa.md §7). The
	   working value is in D; move it to X so a 16-bit return lands in the
	   ABI register. 8-bit returns are already in B (D's low half) and X is
	   caller-saved, so the move is harmless; skip it only for void. */
	if (!(func_flags & F_VOIDRET))
		printf("\tLD X,D\n");
	printf("\tRTS\n");
}

void gen_label(const char *tail, unsigned n)
{
	printf("L%d%s:\n", n, tail);
}

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
 * Branch on the condition result. The op that produced it leaves N,Z set:
 *   LBEQ = branch if Z   = value zero  = condition false
 *   LBNE = branch if !Z  = value nonzero = condition true
 * The page-1 long form is used so branch range is never a concern.
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
		return 0;
	}
}

/*
 *	Emit a memory/immediate operand string for a "simple" RHS node, suitable
 *	directly after an ALU/LD opcode (e.g. "ADD D,<here>"). off is an extra
 *	byte offset into the object (used for the high byte of a 16-bit access).
 *	Returns 1 if it produced an operand, 0 if the node is not simple.
 */
static unsigned simple_rhs(struct node *r)
{
	switch (r->op) {
	case T_CONSTANT:
	case T_NAME:
	case T_NREF:
	case T_LREF:
		return 1;
	}
	return 0;
}

/* Print an immediate constant operand for the given size. */
static void imm_operand(unsigned long v, unsigned s)
{
	if (s == 1)
		printf("$%02X", (unsigned)(v & 0xFF));
	else
		printf("$%04X", (unsigned)(v & 0xFFFF));
}

/* Print a memory/value operand for a simple node, with extra byte offset. */
static void mem_operand(struct node *r, unsigned off, unsigned s)
{
	unsigned v = r->value + off;
	switch (r->op) {
	case T_CONSTANT:
		imm_operand(r->value, s);
		break;
	case T_NAME:
		/* Address of a global as an immediate value */
		printf("%s+%u", namestr(r->snum), v);
		break;
	case T_NREF:
		/* Value of a global (absolute memory) */
		printf("(%s+%u)", namestr(r->snum), v);
		break;
	case T_LREF:
		/* Value of a local/argument: stack relative + dynamic depth */
		printf("(SP+%u)", v + sp);
		break;
	default:
		error("mform");
	}
}

/* Emit "op D,<rhs>" for a 16-bit ALU op that has the full set of D operand
   forms (ADD/SUB/CMP). Returns 1 on success. */
static unsigned alu16_d(struct node *r, const char *op)
{
	if (!simple_rhs(r))
		return 0;
	printf("\t%s D,", op);
	mem_operand(r, 0, 2);
	printf("\n");
	return 1;
}

/* Emit "op B,<rhs>" for an 8-bit ALU op against a simple operand. The 8-bit
   ALU ops (ADD/SUB/CMP) accept (SP+n8); AND/OR/EOR do not, but those are
   routed through alu_bitwise instead. Returns 1 on success. */
static unsigned alu8_b(struct node *r, const char *op)
{
	if (!simple_rhs(r))
		return 0;
	printf("\t%s B,", op);
	mem_operand(r, 0, 1);
	printf("\n");
	return 1;
}

/*
 *	Bitwise AND/OR/EOR. There is no 16-bit form, and the byte forms have no
 *	(SP+n8) operand, so we handle each case explicitly and stay native:
 *	  - constant : op B,$lo  [op A,$hi]
 *	  - global   : op B,(name+0) [op A,(name+1)]
 *	  - local    : point X at the slot then op B,(X) [op A,(X+1)]
 */
static unsigned alu_bitwise(struct node *r, const char *op, unsigned s)
{
	if (!simple_rhs(r))
		return 0;
	switch (r->op) {
	case T_CONSTANT:
		printf("\t%s B,$%02X\n", op, (unsigned)(r->value & 0xFF));
		if (s == 2)
			printf("\t%s A,$%02X\n", op, (unsigned)((r->value >> 8) & 0xFF));
		return 1;
	case T_NAME:
		/* AND/OR/EOR of an address constant is rare; let the stack path
		   in gen_node handle it. */
		return 0;
	case T_NREF:
		printf("\t%s B,(%s+%u)\n", op, namestr(r->snum), (unsigned)r->value);
		if (s == 2)
			printf("\t%s A,(%s+%u)\n", op, namestr(r->snum), (unsigned)r->value + 1);
		return 1;
	case T_LREF:
		printf("\tLEA X,SP+%u\n", (unsigned)r->value + sp);
		printf("\t%s B,(X)\n", op);
		if (s == 2)
			printf("\t%s A,(X+1)\n", op);
		return 1;
	}
	return 0;
}

/*
 *	Comparisons. Compute (left - right) with CMP, then build a 0/1 boolean
 *	in D/B. The final LD sets N,Z from the result word (LD class sets N,Z),
 *	so the following LBEQ/LBNE is valid. bcc is the branch taken when the
 *	comparison is TRUE.
 */
/* Materialise a 0/1 boolean from the condition codes. A C boolean is always
   int, so the result is always the full 16-bit D: writing only B would leave
   the high byte (A) stale and corrupt the int result (and any LBEQ/LBNE that
   later tests the 16-bit value). */
static void make_bool_from_cc(const char *bcc)
{
	unsigned lt = label++;
	unsigned le = label++;
	printf("\t%s X%u\n", bcc, lt);
	printf("\tLD D,$0000\n");
	printf("\tLBRA X%u\n", le);
	printf("X%u:\n", lt);
	printf("\tLD D,$0001\n");
	printf("X%u:\n", le);
}

/* Map a comparison op to the branch mnemonic that is taken when true, for the
   given operand type (sign matters). */
static const char *cmp_branch(unsigned op, unsigned type)
{
	unsigned u = type & UNSIGNED;
	if (PTR(type))
		u = UNSIGNED;
	switch (op) {
	case T_EQEQ:
		return "LBEQ";
	case T_BANGEQ:
		return "LBNE";
	case T_LT:
		return u ? "LBCS" : "LBLT";
	case T_GT:
		return u ? "LBHI" : "LBGT";
	case T_LTEQ:
		return u ? "LBLS" : "LBLE";
	case T_GTEQ:
		return u ? "LBCC" : "LBGE";
	}
	return NULL;
}

/* Emit a CMP of D/B against the simple RHS, then build the boolean. The
   comparison size/sign come from the operand type (n->right->type). */
static unsigned cmp_simple(struct node *n)
{
	struct node *r = n->right;
	unsigned s = get_size(r->type);
	const char *bcc = cmp_branch(n->op, r->type);

	if (s > 2 || !simple_rhs(r) || bcc == NULL)
		return 0;
	if (s == 1) {
		printf("\tCMP B,");
		mem_operand(r, 0, 1);
		printf("\n");
	} else {
		printf("\tCMP D,");
		mem_operand(r, 0, 2);
		printf("\n");
	}
	make_bool_from_cc(bcc);
	n->flags |= ISBOOL;
	return 1;
}

/* Emit a CMP of D/B against the value on the top of stack (left was pushed,
   right is in D - but we need left-right; the kit pushes left then evaluates
   right, so D holds right and (SP) holds left). We compute left - right by
   comparing the stacked left against D: do it by reversing - load left, or
   simpler, use the stack value as the source of a reverse compare. To keep
   the same boolean sense we instead CMP D against (SP) which is right-left,
   so invert the branch sense by swapping the operand roles in cmp_branch. */
static unsigned cmp_stack(struct node *n)
{
	struct node *r = n->right;
	unsigned s = get_size(r->type);
	const char *bcc;
	/* (SP) holds the left operand, D holds the right operand.
	   CMP D,(SP) computes right - left. The truth of "left OP right" is
	   "right OP' left" where OP' is the swapped comparison. */
	unsigned swop = n->op;
	switch (n->op) {
	case T_LT:	swop = T_GT;	break;
	case T_GT:	swop = T_LT;	break;
	case T_LTEQ:	swop = T_GTEQ;	break;
	case T_GTEQ:	swop = T_LTEQ;	break;
	/* == and != are symmetric */
	}
	bcc = cmp_branch(swop, r->type);
	if (s > 2 || bcc == NULL)
		return 0;
	if (s == 1)
		printf("\tCMP B,(SP)\n");
	else
		printf("\tCMP D,(SP+0)\n");
	printf("\tLEA SP,SP+%u\n", get_stack_size(r->type));
	make_bool_from_cc(bcc);
	n->flags |= ISBOOL;
	return 1;
}

/*
 *	gen_direct: the "easy expression" path. The left operand has already
 *	been evaluated into D/B. If the right operand is simple we emit the op
 *	directly against it with NO push (this both inlines and sidesteps the
 *	mid-expression stack-depth bug). Returns 1 if handled.
 */
unsigned gen_direct(struct node *n)
{
	struct node *r = n->right;
	unsigned s = get_size(n->type);

	switch(n->op) {
	/* Cleanup is special and must be handled here. Its node type is the
	   function return type, so the byte count is in n->right->value. */
	case T_CLEANUP:
		if (n->right->value)
			printf("\tLEA SP,SP+%u\n", (unsigned) n->right->value);
		sp -= n->right->value;
		return 1;
	}

	if (r == NULL)
		return 0;
	if (s > 2)
		return 0;	/* long/float go via helpers */

	switch(n->op) {
	case T_PLUS:
		if (s == 1)
			return alu8_b(r, "ADD");
		return alu16_d(r, "ADD");
	case T_MINUS:
		if (s == 1)
			return alu8_b(r, "SUB");
		return alu16_d(r, "SUB");
	case T_AND:
		return alu_bitwise(r, "AND", s);
	case T_OR:
		return alu_bitwise(r, "OR", s);
	case T_HAT:
		return alu_bitwise(r, "EOR", s);
	case T_EQEQ:
	case T_BANGEQ:
	case T_LT:
	case T_GT:
	case T_LTEQ:
	case T_GTEQ:
		return cmp_simple(n);
	case T_LTLT:
		/* Constant shifts operate on the value already in D/B (the left
		   operand). They MUST be done here, before any push of the left
		   operand, or we would shift the count instead of the value. */
		return shift_const(n, "ASL", "ASL");
	case T_GTGT:
		if (n->type & UNSIGNED)
			return shift_const(n, "LSR", "LSR");
		return shift_const(n, "ASR", "ASR");
	case T_SHLEQ:
	case T_SHREQ:
		/* Constant-count shift-assign: D holds &lval, the count is the (still
		   unevaluated) constant rhs. Variable counts fall through to the
		   helper, like a plain variable shift. */
		return shifteq_direct(n);
	case T_STAR:
		/* Multiply by a power-of-two constant becomes a shift; this is
		   how array/struct index scaling stays native. Other multiplies
		   fall back to the helper. */
		if (r->op == T_CONSTANT) {
			unsigned long m = r->value;
			unsigned k = 0;
			if (m == 0) {
				if (s == 1)
					printf("\tLD B,$00\n");
				else
					printf("\tLD D,$0000\n");
				return 1;
			}
			if (m == 1)
				return 1;	/* x * 1 */
			while (!(m & 1)) { m >>= 1; k++; }
			if (m == 1) {	/* pure power of two */
				if (s == 1) {
					if (k >= 8) {
						printf("\tLD B,$00\n");
						return 1;
					}
					while (k--)
						printf("\tASL B\n");
					return 1;
				}
				if (k >= 16) {
					printf("\tLD D,$0000\n");
					return 1;
				}
				printf("\tASL D,%u\n", k);	/* decimal count, as shift_const */
				return 1;
			}
		}
		return 0;
	}
	return 0;
}

unsigned gen_uni_direct(struct node *n)
{
	return 0;
}

/*
 *	++ / -- on a simple lvalue (local/argument/global) by a constant. We do
 *	this natively to keep the common pointer/array idiom (*p++ etc.) free of
 *	helper calls. sign is +1 for ++, -1 for --.
 */
static unsigned inc_dec_node(struct node *n, int sign)
{
	struct node *l = n->left;
	struct node *r = n->right;
	unsigned s = get_size(n->type);
	unsigned nr = n->flags & NORETURN;
	unsigned delta;

	if (s > 2 || r->op != T_CONSTANT)
		return 0;
	delta = (unsigned)(r->value & 0xFFFF);

	/* Load the slot, compute the new value, store it back, and (if the old
	   value is wanted) undo the delta so D holds the pre-op result. */
	if (l->op == T_NAME) {
		if (s == 1) {
			printf("\tLD B,(%s+%u)\n", namestr(l->snum), (unsigned)l->value);
			printf("\t%s B,$%02X\n", sign > 0 ? "ADD" : "SUB", delta & 0xFF);
			printf("\tST B,(%s+%u)\n", namestr(l->snum), (unsigned)l->value);
			if (!nr)
				printf("\t%s B,$%02X\n", sign > 0 ? "SUB" : "ADD", delta & 0xFF);
		} else {
			printf("\tLD D,(%s+%u)\n", namestr(l->snum), (unsigned)l->value);
			printf("\t%s D,$%04X\n", sign > 0 ? "ADD" : "SUB", delta);
			printf("\tST D,(%s+%u)\n", namestr(l->snum), (unsigned)l->value);
			if (!nr)
				printf("\t%s D,$%04X\n", sign > 0 ? "SUB" : "ADD", delta);
		}
		return 1;
	}
	if (l->op == T_LOCAL || l->op == T_ARGUMENT) {
		unsigned off = (unsigned)l->value + sp;
		if (s == 1) {
			printf("\tLD B,(SP+%u)\n", off);
			printf("\t%s B,$%02X\n", sign > 0 ? "ADD" : "SUB", delta & 0xFF);
			printf("\tST B,(SP+%u)\n", off);
			if (!nr)
				printf("\t%s B,$%02X\n", sign > 0 ? "SUB" : "ADD", delta & 0xFF);
		} else {
			printf("\tLD D,(SP+%u)\n", off);
			printf("\t%s D,$%04X\n", sign > 0 ? "ADD" : "SUB", delta);
			printf("\tST D,(SP+%u)\n", off);
			if (!nr)
				printf("\t%s D,$%04X\n", sign > 0 ? "SUB" : "ADD", delta);
		}
		return 1;
	}
	return 0;
}

unsigned gen_shortcut(struct node *n)
{
	switch (n->op) {
	case T_PLUSPLUS:
		return inc_dec_node(n, +1);
	case T_MINUSMINUS:
		return inc_dec_node(n, -1);
	}
	return 0;
}

/*
 *	Move the 16-bit working value (a pointer) into X so we can dereference
 *	or store through it.
 */
static void d_to_x(void)
{
	printf("\tLD X,D\n");
}

/* Constant left shift of the working value by v positions. */
static unsigned shift_const(struct node *n, const char *op16, const char *op8)
{
	struct node *r = n->right;
	unsigned s = get_size(n->type);
	unsigned v;

	if (s > 2 || r->op != T_CONSTANT)
		return 0;
	v = r->value & 0xFF;
	if (s == 1) {
		if (v >= 8) {
			printf("\tLD B,$00\n");
			return 1;
		}
		/* The 8-bit shifts take no count; repeat. */
		while (v--)
			printf("\t%s B\n", op8);
		/* A single byte shift sets N,Z; if v was 0 the value is
		   unchanged and N,Z may be stale, but a 0-count shift only
		   arises from x<<0 which the front end folds. */
		return 1;
	}
	/* 16-bit constant shift */
	if (v == 0)
		return 1;
	if (v >= 16) {
		printf("\tLD D,$0000\n");
		return 1;
	}
	/* The shift count is a small decimal literal, not a $-prefixed hex
	   value (ASL D,3). */
	printf("\t%s D,%u\n", op16, v);
	return 1;
}

/*
 *	Compound assignment (lval OP= rhs), lowered natively. The contract is the
 *	same as T_EQ: the front end evaluates the LVAL-flagged left as a pointer and
 *	pushes it, so on entry the lvalue ADDRESS is on the stack at (SP) and the rhs
 *	VALUE is in the working register (D for int/pointer, B for char). We load
 *	*addr, combine it with rhs, store the result back, and leave it in D/B (the
 *	value of the assignment expression). Only the address is on the stack, so
 *	every lvalue shape - global, local, *p, arr[i] - is handled identically.
 *	long/float (s > 2) return 0 and fall back to the helper, like the rest of
 *	this backend.
 *
 *	  + - & | ^   fold against the slot via X (no call).
 *	  * / %       call the runtime helper, keeping &lval on the stack across the
 *	              call (see below) so no callee-saved register is needed. Char
 *	              operands are widened to 16-bit first.
 */
static unsigned op_eq_node(struct node *n)
{
	unsigned s = get_size(n->type);
	unsigned uns = n->type & UNSIGNED;
	const char *h;

	if (s > 2)
		return 0;

	switch (n->op) {
	case T_PLUSEQ:
	case T_MINUSEQ:
	case T_ANDEQ:
	case T_OREQ:
	case T_HATEQ:
		/* X = &lval; rhs is already in D/B. Fold the slot in, store back. */
		printf("\tLD X,(SP)\n");
		printf("\tLEA SP,SP+2\n");
		if (s == 1) {
			switch (n->op) {
			case T_PLUSEQ:  printf("\tADD B,(X)\n"); break;
			case T_MINUSEQ: printf("\tNEG B\n\tADD B,(X)\n"); break;
			case T_ANDEQ:   printf("\tAND B,(X)\n"); break;
			case T_OREQ:    printf("\tOR B,(X)\n"); break;
			case T_HATEQ:   printf("\tEOR B,(X)\n"); break;
			}
			printf("\tST B,(X)\n");
		} else {
			switch (n->op) {
			case T_PLUSEQ:  printf("\tADD D,(X)\n"); break;
			/* -(rhs) + *lval == *lval - rhs (no memory-minus-D form). */
			case T_MINUSEQ: printf("\tCOM A\n\tCOM B\n\tADD D,$0001\n\tADD D,(X)\n"); break;
			/* No 16-bit bitwise op; do it a byte at a time. */
			case T_ANDEQ:   printf("\tAND B,(X)\n\tAND A,(X+1)\n"); break;
			case T_OREQ:    printf("\tOR B,(X)\n\tOR A,(X+1)\n"); break;
			case T_HATEQ:   printf("\tEOR B,(X)\n\tEOR A,(X+1)\n"); break;
			}
			printf("\tST D,(X)\n");
		}
		return 1;

	case T_STAREQ:
	case T_SLASHEQ:
	case T_PERCENTEQ:
		if (n->op == T_STAREQ)       h = "__mul";
		else if (n->op == T_SLASHEQ) h = uns ? "__divu" : "__div";
		else                         h = uns ? "__remu" : "__rem";
		/* The runtime helper takes LHS (*lval) on the stack at (SP+2) and RHS
		   (rhs) in D, then pops ret+LHS and returns the result in D. We keep
		   &lval on the stack throughout - below what the helper pops - and
		   reload it afterwards, so nothing here depends on a callee-saved
		   register (safe even once Y is handed out as a register variable).
		   Char operands are widened to 16-bit: zero-extend for the multiply
		   (its low byte is the char product), sign- or zero-extend per
		   signedness for divide/modulo. */
		if (s == 1) {				/* widen rhs (B) -> D = RHS */
			if (n->op == T_STAREQ || uns)
				printf("\tLD A,$00\n");
			else
				printf("\tSEX\n");
		}
		printf("\tPSHS $06\n");			/* push RHS; &lval stays below it */
		printf("\tLD X,(SP+2)\n");		/* X = &lval */
		if (s == 1) {
			printf("\tLD B,(X)\n");		/* B = *lval */
			if (n->op == T_STAREQ || uns)	/* widen *lval (B) -> D = LHS */
				printf("\tLD A,$00\n");
			else
				printf("\tSEX\n");
		} else {
			printf("\tLD D,(X)\n");		/* D = *lval = LHS */
		}
		printf("\tPSHS $06\n");			/* push LHS -> (SP+2) after the JSR */
		printf("\tLD D,(SP+2)\n");		/* D = RHS */
		printf("\tJSR %s\n", h);		/* pops ret+LHS, result in D */
		printf("\tLD X,(SP+2)\n");		/* reload &lval (helper clobbered X) */
		if (s == 1)
			printf("\tST B,(X)\n");		/* store low byte = char result */
		else
			printf("\tST D,(X)\n");
		printf("\tLEA SP,SP+4\n");		/* drop RHS + &lval */
		return 1;
	}
	return 0;
}

/*
 *	Post-increment / post-decrement on a *complex* lvalue (arr[i]++, (*p)--).
 *	Simple lvalues (a global/local/argument) are handled earlier by inc_dec_node;
 *	these reach gen_node with the lvalue ADDRESS on the stack and the (constant,
 *	pointer-scaled) delta in D - the same contract as compound assignment, since
 *	the front end lowers ++/-- this way. We load *lval, apply the delta, store
 *	the new value, and - for the value form (not NORETURN) - undo the delta so
 *	the pre-op value is left in D/B (the inc_dec_node trick). Pre-increment is
 *	already lowered to += by the front end, so it never reaches here.
 */
static unsigned post_incdec_node(struct node *n)
{
	unsigned s = get_size(n->type);
	unsigned nr = n->flags & NORETURN;
	int inc = (n->op == T_PLUSPLUS);
	unsigned delta;

	if (s > 2 || n->right == NULL || n->right->op != T_CONSTANT)
		return 0;
	delta = (unsigned)(n->right->value & 0xFFFF);
	printf("\tLD X,(SP)\n");		/* X = &lval (delta is also in D/B) */
	printf("\tLEA SP,SP+2\n");
	if (s == 1) {
		printf("\tLD B,(X)\n");				/* old */
		printf("\t%s B,$%02X\n", inc ? "ADD" : "SUB", delta & 0xFF);
		printf("\tST B,(X)\n");				/* new */
		if (!nr)
			printf("\t%s B,$%02X\n", inc ? "SUB" : "ADD", delta & 0xFF);
	} else {
		printf("\tLD D,(X)\n");
		printf("\t%s D,$%04X\n", inc ? "ADD" : "SUB", delta);
		printf("\tST D,(X)\n");
		if (!nr)
			printf("\t%s D,$%04X\n", inc ? "SUB" : "ADD", delta);
	}
	return 1;
}

/*
 *	Constant-count <<= / >>= on an lvalue, done natively. At gen_direct the left
 *	(the LVAL-flagged lvalue) has already been evaluated as a pointer into D and
 *	the rhs count node has NOT yet been evaluated, so a constant count is still
 *	visible. A runtime-variable count has no hardware form (isa.md S8.8) and
 *	falls through to the shift helper, exactly like a plain variable <<.
 */
static unsigned shifteq_direct(struct node *n)
{
	struct node *r = n->right;
	unsigned s = get_size(n->type);

	if (s > 2 || r->op != T_CONSTANT)
		return 0;
	printf("\tLD X,D\n");			/* D holds &lval */
	if (s == 1)
		printf("\tLD B,(X)\n");
	else
		printf("\tLD D,(X)\n");
	if (n->op == T_SHLEQ)
		shift_const(n, "ASL", "ASL");
	else if (n->type & UNSIGNED)
		shift_const(n, "LSR", "LSR");
	else
		shift_const(n, "ASR", "ASR");
	if (s == 1)
		printf("\tST B,(X)\n");
	else
		printf("\tST D,(X)\n");
	return 1;
}

/*
 *	gen_node: emit a node whose operands are already in place. For binary
 *	ops that reach here the left operand is on the stack (the driver pushed
 *	it) and the right operand is in D/B; we operate against (SP) and pop.
 */
unsigned gen_node(struct node *n)
{
	unsigned s = get_size(n->type);
	unsigned nr = n->flags & NORETURN;
	unsigned v = n->value;

	/* Account for the left operand the driver evaluated and pushed. Call
	   arguments are special - removed by the call/return and reported via
	   T_CLEANUP, not here. T_CALLNAME has no pushed left of its own. */
	if (n->left && n->op != T_ARGCOMMA && n->op != T_FUNCCALL &&
		n->op != T_CALLNAME)
		sp -= get_stack_size(n->left->type);

	switch (n->op) {
	/* ---- leaves -------------------------------------------------- */
	case T_CONSTANT:
		if (s == 1) {
			printf("\tLD B,$%02X\n", (unsigned)(n->value & 0xFF));
			return 1;
		}
		if (s == 2) {
			printf("\tLD D,$%04X\n", (unsigned)(n->value & 0xFFFF));
			return 1;
		}
		return 0;	/* 32-bit constants -> helper */
	case T_NREF:	/* Load a global value */
		if (s == 1) {
			printf("\tLD B,(%s+%u)\n", namestr(n->snum), v);
			return 1;
		}
		if (s == 2) {
			printf("\tLD D,(%s+%u)\n", namestr(n->snum), v);
			return 1;
		}
		return 0;
	case T_LREF:	/* Load a local/argument value */
		if (s == 1) {
			printf("\tLD B,(SP+%u)\n", v + sp);
			return 1;
		}
		if (s == 2) {
			printf("\tLD D,(SP+%u)\n", v + sp);
			return 1;
		}
		return 0;
	case T_NAME:	/* Address of a global as a value */
		if (s == 2) {
			printf("\tLD D,%s+%u\n", namestr(n->snum), v);
			return 1;
		}
		return 0;
	case T_LOCAL:	/* Address of a local */
	case T_ARGUMENT:
		printf("\tLEA X,SP+%u\n", v + sp);
		/* X now holds the address; move it into D as the value. */
		printf("\tLD D,X\n");
		return 1;
	case T_NSTORE:	/* Store working value to a global */
		if (s == 1) {
			printf("\tST B,(%s+%u)\n", namestr(n->snum), v);
			return 1;
		}
		if (s == 2) {
			printf("\tST D,(%s+%u)\n", namestr(n->snum), v);
			return 1;
		}
		return 0;
	case T_LSTORE:	/* Store working value to a local/argument */
		if (s == 1) {
			printf("\tST B,(SP+%u)\n", v + sp);
			return 1;
		}
		if (s == 2) {
			printf("\tST D,(SP+%u)\n", v + sp);
			return 1;
		}
		return 0;

	/* ---- dereference / assign through a pointer ------------------ */
	case T_DEREF:
		/* D holds the pointer. */
		d_to_x();
		if (s == 1) {
			printf("\tLD B,(X)\n");
			return 1;
		}
		if (s == 2) {
			printf("\tLD D,(X)\n");
			return 1;
		}
		return 0;
	case T_EQ:	/* *(left) = right ; left address on stack, value in D */
		if (s > 2)
			return 0;
		/* Pop the address into X without disturbing D. */
		printf("\tLD X,(SP)\n");
		printf("\tLEA SP,SP+2\n");
		if (s == 1)
			printf("\tST B,(X)\n");
		else
			printf("\tST D,(X)\n");
		return 1;

	/* ---- compound assignment (lval OP= rhs) ---------------------- */
	case T_PLUSEQ:
	case T_MINUSEQ:
	case T_ANDEQ:
	case T_OREQ:
	case T_HATEQ:
	case T_STAREQ:
	case T_SLASHEQ:
	case T_PERCENTEQ:
		return op_eq_node(n);

	/* post ++/-- on a complex lvalue (simple ones go via inc_dec_node) */
	case T_PLUSPLUS:
	case T_MINUSMINUS:
		return post_incdec_node(n);

	/* ---- calls --------------------------------------------------- */
	case T_CALLNAME:
		printf("\tJSR %s+%u\n", namestr(n->snum), v);
		/* Result returns in X (16-bit) / B (8-bit). Bring it into the
		   working register D unless the value is unused. */
		if (!nr)
			printf("\tLD D,X\n");
		return 1;
	case T_FUNCCALL:
		/* Indirect call: the function pointer is in D. */
		d_to_x();
		printf("\tJSR (X)\n");
		if (!nr)
			printf("\tLD D,X\n");
		return 1;

	/* ---- binary ops against the stacked left operand ------------- */
	case T_PLUS:
		if (s == 1) {
			printf("\tADD B,(SP)\n");
			printf("\tLEA SP,SP+2\n");
			return 1;
		}
		if (s == 2) {
			printf("\tADD D,(SP+0)\n");
			printf("\tLEA SP,SP+2\n");
			return 1;
		}
		return 0;
	case T_MINUS:
		/* D holds right, (SP) holds left; we need left - right. Negate
		   D then add the stacked left: -(right) + left. */
		if (s == 1) {
			printf("\tNEG B\n");
			printf("\tADD B,(SP)\n");
			printf("\tLEA SP,SP+2\n");
			return 1;
		}
		if (s == 2) {
			printf("\tCOM A\n\tCOM B\n\tADD D,$0001\n");
			printf("\tADD D,(SP+0)\n");
			printf("\tLEA SP,SP+2\n");
			return 1;
		}
		return 0;
	case T_AND:
	case T_OR:
	case T_HAT: {
		const char *op = (n->op == T_AND) ? "AND" :
				 (n->op == T_OR)  ? "OR"  : "EOR";
		/* The stacked left operand is at (SP). Point X at it so we can
		   use the (X)/(X+1) byte forms (AND/OR/EOR have no SP forms). */
		printf("\tLEA X,SP+0\n");
		printf("\t%s B,(X)\n", op);
		if (s == 2)
			printf("\t%s A,(X+1)\n", op);
		printf("\tLEA SP,SP+2\n");
		return 1;
	}
	case T_EQEQ:
	case T_BANGEQ:
	case T_LT:
	case T_GT:
	case T_LTEQ:
	case T_GTEQ:
		return cmp_stack(n);

	/* ---- unary ops ----------------------------------------------- */
	case T_NEGATE:
		if (s == 1) {
			printf("\tNEG B\n");
			return 1;
		}
		if (s == 2) {
			printf("\tCOM A\n\tCOM B\n\tADD D,$0001\n");
			return 1;
		}
		return 0;
	case T_TILDE:
		if (s == 1) {
			printf("\tCOM B\n");
			return 1;
		}
		if (s == 2) {
			printf("\tCOM A\n\tCOM B\n");
			return 1;
		}
		return 0;
	case T_BANG: {
		/* Logical not: result 1 if value == 0 else 0. The TEST width is
		   the operand's size (a char is in B with A stale), not the int
		   result size. */
		unsigned os = n->right ? get_size(n->right->type) : 2;
		n->flags |= ISBOOL;
		if (os > 2)
			return 0;	/* long: fall back to the __not helper */
		if (os == 1)
			printf("\tCMP B,$00\n");
		else
			printf("\tCMP D,$0000\n");
		make_bool_from_cc("LBEQ");
		return 1;
	}
	case T_BOOL: {
		/* Normalise to 0/1. If already known boolean, nothing to do.
		   Test width is the operand's size (see T_BANG). */
		unsigned os = n->right ? get_size(n->right->type) : 2;
		n->flags |= ISBOOL;
		if (n->right && (n->right->flags & ISBOOL))
			return 1;
		if (os > 2)
			return 0;
		if (os == 1)
			printf("\tCMP B,$00\n");
		else
			printf("\tCMP D,$0000\n");
		make_bool_from_cc("LBNE");
		return 1;
	}

	/* Constant shifts are handled in gen_direct (the value is in D/B
	   before any push). A non-constant shift count reaches make_node and
	   falls back to the shift helper. */

	/* ---- casts (integer size changes) ---------------------------- */
	case T_CAST: {
		unsigned rt = n->right->type;
		unsigned rs;
		if (PTR(rt))
			rt = USHORT;
		if (!IS_INTARITH(n->type) || !IS_INTARITH(rt))
			return 0;
		rs = get_size(rt);
		/* Shrinking or same size: nothing to emit (value already in the
		   low half). */
		if (s <= rs)
			return 1;
		/* Widening 1 -> 2 bytes. */
		if (rs == 1 && s == 2) {
			if (rt & UNSIGNED)
				printf("\tLD A,$00\n");	/* zero-extend */
			else
				printf("\tSEX\n");	/* sign-extend B into A */
			return 1;
		}
		return 0;
	}
	}
	return 0;
}
