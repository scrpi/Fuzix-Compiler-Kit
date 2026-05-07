/*
 *	6502 backend for the Fuzix C Compiler
 *
 *	The big challenge here is that the C stack is a software
 *	construct and so quite slow to adjust. As the compiler thinks
 *	mostly in terms of call frames we can avoid a chunk of the cost
 *	but not all of it.
 *
 *	We try and reduce the cost by
 *	1. Generating direct references whenever we can
 *	2. When we need a helper and we can directly access we stuff the
 *	   one side of the operation into @tmp
 *	3. For certain operations we generate the left/right ourselves and
 *	   go via the CPU stack. This is a win in some common cases like
 *	   assignment, particularly on the 65C02
 *
 *	For the rest we have to go via the C stack which whilst painfulf in
 *	places is helped by the relatively low clocks per instruction.
 *
 *	Elements of this design like the separate stack with ZP pointer are
 *	heavily influenced by CC65 and one goal is to use many of the same
 *	support functions. Our approach to code generation is however quite
 *	different and constrained by wanting to run on an 8bit micro.
 *
 *	Register usage
 *	A: lower half of working value or pointer
 *	X: upper half of working value or pointer
 *	Y: used for indexing locals off @sp and various parameters
 *	   to helpers on XA
 *	@sp: stack pointer base word in ZP
 *	@tmp: scratch value used extensively
 *	@tmp2: temporary word following @tmp
 *	@hireg: upper 16bits of 32bit workinf values
 *
 *	CPU specifics
 *	6502		classic CPU. We don't use undoc stuff
 *	65C02		6502 + base CMOS instructions
 *	M740		6502 + some of base CMOS (not STZ) and some other
 *			differences (TST, LDM)
 *	TODO:
 *	W65C02		Has bit ops (bbr/bbs/seb/clb) which we can use for
 *			some logic ops.
 *	HUC6820		Has CLA/CLX/CLY (clear reg), and W65C02 bitops
 *			SAX/SAY/SXY (swap A and X/Y),
 *
 *	2A03 is a 6502 with no decimal mode. We don't use it so for us
 *	it's just another 6502.
 *
 *	Next to fix comparisons are reverse side due to **tmp effect
 *	need gttmp lteqtmp and flip side flipper
 *
 *	TODO: should we be working on the basis of helpers clear Y or set
 *	1 as we do for pri8 etc at the moment. Need to audit helpers but
 *	probably worth it
 *
 *	For -Os we should defintiely have "get local and stuff it in @tmp
 *	as a helper", and probably also clear Y. That would optimize a lot of
 *	pointer use cases.
 *
 *	LDEREF helper for tight use of *local and *arg.
 *
 *	Track what is in @tmp.
 *
 *	Remove incsp/incsp2 in favour of general addnsp form
 *
 *	Untangle the pri ops so they are always passed the node for the op
 *	and the node for evaluation explicitly and logically so we can
 *	avoid the squashing mess
 *
 *	Look at doing some kind of two step LDSTORE for struct referencing
 *
 *	Turn n = n + 1 into n += 1 as for 6502 that's going to help a lot
 *
 *	Register variables (aka bits of zero page). This will speed up pointers
 *	a lot (at a stack save/restore cost). We can keep the code density
 *	good by using a helper to stack "n" registers not doing the inline
 *	stuff cc65 does.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "compiler.h"
#include "backend.h"
#include "backend-byte.h"

#define NMOS_6502	0
#define CMOS_6502	1
#define CMOS_M740	2
#define CMOS_65C816	3		/* 65802/816 in 8bit mode */

#define BYTE(x)		(((unsigned)(x)) & 0xFF)
#define WORD(x)		(((unsigned)(x)) & 0xFFFF)

/*
 *	State for the current function
 */
static unsigned frame_len;	/* Number of bytes of stack frame */
static unsigned sp;		/* Stack pointer offset tracking */
static unsigned unreachable;	/* Code following an unconditional jump */
static unsigned xlabel;		/* Internal backend generated branches */
static unsigned argbase;	/* Track shift between arguments and stack */

/*
 *	Node types we create in rewriting rules
 */
#define T_NREF		(T_USER)		/* Load of C global/static */
#define T_CALLNAME	(T_USER+1)		/* Function call by name */
#define T_NSTORE	(T_USER+2)		/* Store to a C global/static */
#define T_LREF		(T_USER+3)		/* Ditto for local */
#define T_LSTORE	(T_USER+4)
#define T_LBREF		(T_USER+5)		/* Ditto for labelled strings or local static */
#define T_LBSTORE	(T_USER+6)
#define T_RREF		(T_USER+7)
#define T_RSTORE	(T_USER+8)
#define T_RDEREF	(T_USER+9)		/* *regptr */
#define T_REQ		(T_USER+10)		/* *regptr */
#define T_DEREFPLUS	(T_USER+11)
#define T_LDEREF	(T_USER+12)

/*
 *	6502 specifics. We need to track some register values to produce
 *	bearable code
 */

static void output(const char *p, ...)
{
	va_list v;
	va_start(v, p);
	putchar('\t');
	vprintf(p, v);
	putchar('\n');
	va_end(v);
}

static void label(const char *p, ...)
{
	va_list v;
	va_start(v, p);
	vprintf(p, v);
	putchar(':');
	putchar('\n');
	va_end(v);
}


#define R_A	0
#define R_X	1
#define R_Y	2
#define R_TMPL	3
#define R_TMPH	4

#define INVALID	0

struct regtrack {
	unsigned state;
	uint8_t value;
	unsigned snum;
	unsigned offset;
};

static struct regtrack reg[5];
static struct regtrack rsaved;

static void invalidate_regs(void)
{
	reg[R_A].state = INVALID;
	reg[R_X].state = INVALID;
	reg[R_Y].state = INVALID;
	reg[R_TMPL].state = INVALID;
	reg[R_TMPH].state = INVALID;
	printf(";invalidate regs\n");
}


static void invalidate_a(void)
{
	reg[R_A].state = INVALID;
}

static void invalidate_x(void)
{
	reg[R_X].state = INVALID;
}

static void invalidate_y(void)
{
	reg[R_Y].state = INVALID;
}

static void invalidate_tmp(void)
{
	reg[R_TMPL].state = INVALID;
	reg[R_TMPH].state = INVALID;
}

static void invalidate_tmpl(void)
{
	reg[R_TMPL].state = INVALID;
}

static void const_a_set(unsigned val)
{
	if (reg[R_A].state == T_CONSTANT)
		reg[R_A].value = val;
	else
		reg[R_A].state = INVALID;
}

static void const_x_set(unsigned val)
{
	if (reg[R_X].state == T_CONSTANT)
		reg[R_X].value = val;
	else
		reg[R_X].state = INVALID;
}

static void const_y_set(unsigned val)
{
	if (reg[R_Y].state == T_CONSTANT)
		reg[R_Y].value = val;
	else
		reg[R_Y].state = INVALID;
}

/* Get a value into A, adjust and track */
static void load_a(uint8_t n)
{
	uint8_t curr_a;
	if (reg[R_A].state == T_CONSTANT) {
		curr_a = reg[R_A].value;
		if (curr_a == n)
			return;
		/* Left shift can be used for cases like 1->2, 2->4, 3->6
		   and is only one byte. It's no faster than LDA #n but shorter.
		 */
		if ((curr_a << 1) == n) {
			output(";A contains %u, left shift", curr_a);
			output("asl a");
			reg[R_A].value = n;
			return;
		}
		/* Right shift can be used for cases like 1->0, 2->1, 3->1
		   and is only one byte. No faster than LDA #n, but shorter.
		   Note that lsr a always puts 0 in the most significant bit.
		 */
		if (((curr_a >> 1) & 0x7F) == n) {
			output(";A contains %u, right shift", curr_a);
			output("lsr a");
			reg[R_A].value = n;
			return;
		}
		/* If processor supports inc a and dec a */
		if (curr_a == n - 1 && cpu != NMOS_6502) {
			output("inc a");
			reg[R_A].value = n;
			return;
		}
		if (curr_a == n + 1 && cpu != NMOS_6502) {
			output("dec a");
			reg[R_A].value = n;
			return;
		}
	}
	if (reg[R_X].state == T_CONSTANT && reg[R_X].value == n) {
		output(";X contains %u", reg[R_X].value);
		output("txa");
	}
	else if (reg[R_Y].state == T_CONSTANT && reg[R_Y].value == n) {
		output(";Y contains %u", reg[R_Y].value);
		output("tya");
	} else
		output("lda #%u", n);
	reg[R_A].state = T_CONSTANT;
	reg[R_A].value = n;
}

/* Get a value into X, adjust and track */
static void load_x(uint8_t n)
{
	if (reg[R_X].state == T_CONSTANT) {
		if (reg[R_X].value == n)
			return;
		if (reg[R_X].value == n - 1) {
			output("inx");
			reg[R_X].value++;
			return;
		}
		if (reg[R_X].value == n + 1) {
			output("dex");
			reg[R_X].value--;
			return;
		}
	}
	if (cpu == CMOS_65C816 && reg[R_Y].state == T_CONSTANT && reg[R_Y].value == n)
		output("tyx");
	else if (reg[R_A].state == T_CONSTANT && reg[R_A].value == n)
		output("tax");
	else
		output("ldx #%u", n);
	reg[R_X].state = T_CONSTANT;
	reg[R_X].value = n;
}

/* Get a value into Y, adjust and track */
static void load_y(uint8_t n)
{
	if (reg[R_Y].state == T_CONSTANT) {
		if (reg[R_Y].value == n)
			return;
		if (reg[R_Y].value == n - 1) {
			output("iny");
			reg[R_Y].value++;
			return;
		}
		if (reg[R_Y].value == n + 1) {
			output("dey");
			reg[R_Y].value--;
			return;
		}
	}
	if (cpu == CMOS_65C816 && reg[R_X].state == T_CONSTANT && reg[R_X].value == n)
		output("txy");
	else if (reg[R_A].state == T_CONSTANT && reg[R_A].value == n)
		output("tay");
	else
		output("ldy #%u", n);
	reg[R_Y].state = T_CONSTANT;
	reg[R_Y].value = n;
}

/*
 *	Map store ops to load forms so we can compare them sensibly
 */

static unsigned map_op(unsigned op)
{
	if (op == T_NSTORE)
		return T_NREF;
	if (op == T_LBSTORE)
		return  T_LBREF;
	if (op == T_LSTORE)
		return T_LREF;
	return op;
}

/*
 *	For now just try and eliminate the reloads. We shuld be able to
 *	eliminate some surplus stores with thought if we are careful
 *	how we defer them.
 *
 *	We should try and track @tmp as well the same way but that is
 *	trickier
 */
static void set_xa_node(struct node *n)
{
	unsigned op = map_op(n->op);
	unsigned value = n->value;

	switch(op) {
	case T_NAME:
	case T_CONSTANT:
	case T_NREF:
	case T_LBREF:
	case T_LREF:
	case T_LOCAL:
	case T_ARGUMENT:
		break;
	default:
		invalidate_a();
		invalidate_x();
		return;
	}
	reg[R_X].state = op;
	reg[R_A].state = op;
	reg[R_A].value = value;
	reg[R_X].value = value >> 8;
	reg[R_A].snum = n->snum;
	reg[R_X].snum = n->snum;
	return;
}

static unsigned xa_contains(struct node *n)
{
	if (n->op == T_NREF && (n->flags & SIDEEFFECT))		/* Volatiles */
		return 0;
	if (reg[R_A].state != n->op || reg[R_X].state != n->op)
		return 0;
	if (reg[R_A].value != (n->value & 0xFF) || reg[R_X].value != (n->value >> 8))
		return 0;
	if (reg[R_A].snum != n->snum || reg[R_X].snum != n->snum)
		return 0;
	/* Looks good */
	return 1;
}

static void set_a_node(struct node *n)
{
	unsigned op = map_op(n->op);
	unsigned value = n->value;

	switch(op) {
	case T_NAME:
	case T_CONSTANT:
	case T_NREF:
	case T_LBREF:
	case T_LREF:
	case T_LOCAL:
	case T_ARGUMENT:
		break;
	default:
		invalidate_a();
		return;
	}
	reg[R_A].state = op;
	reg[R_A].value = value;
	reg[R_A].snum = n->snum;
}

static unsigned a_contains(struct node *n)
{
	if (reg[R_A].state != n->op)
		return 0;
	if (reg[R_A].value != n->value)
		return 0;
	if (reg[R_A].snum != n->snum)
		return 0;
	/* Looks good */
	return 1;
}

static void set_tmp_node(struct node *n)
{
	unsigned op = map_op(n->op);
	unsigned value = n->value;

	switch(op) {
	case T_NAME:
	case T_CONSTANT:
	case T_NREF:
	case T_LBREF:
	case T_LREF:
	case T_LOCAL:
	case T_ARGUMENT:
		break;
	default:
		invalidate_tmp();
		return;
	}
	reg[R_TMPL].state = op;
	reg[R_TMPL].value = value;
	reg[R_TMPL].snum = n->snum;
	reg[R_TMPH].state = op;
	reg[R_TMPH].value = value >> 8;
	reg[R_TMPH].snum = n->snum;
}

/*
 *	TODO
 *
 *	Eventually we need to be smart about this. If @tmp contains the
 *	right object but a different offset that is lower then we can adjust
 *	y to access (@tmp),y correctly within a 255 byte range.
 *
 *	It might also make a lot of sense for structs to have a
 *	"struct deref" folded op for deref(plus(thing, constant)) where we
 *	keep @tmp pointing at the object base and use Y when possible to
 *	do offsetting.
 */

static unsigned tmp_contains(struct node *n)
{
	if (n->op == T_NREF && (n->flags & SIDEEFFECT))		/* Volatiles */
		return 0;
	if (reg[R_TMPL].state != n->op || reg[R_TMPH].state != n->op)
		return 0;
	if (reg[R_TMPL].value != (n->value & 0xFF) || reg[R_TMPH].value != (n->value >> 8))
		return 0;
	if (reg[R_TMPL].snum != n->snum || reg[R_TMPL].snum != n->snum)
		return 0;
	/* Looks good */
	return 1;
}

static unsigned reg_match(unsigned r1, unsigned r2)
{
	register struct regtrack *reg1 = reg + r1;
	register struct regtrack *reg2 = reg + r2;
	if (reg1->state == INVALID || reg2->state == INVALID)
		return 0;
	if (reg1->state != reg2->state ||
		reg1->value != reg2->value ||
		reg1->snum != reg2->snum)
		return 0;
	return 1;
}

static unsigned tmp_contains_xa(void)
{
	if (reg_match(R_A, R_TMPL) == 0 ||
		reg_match(R_X, R_TMPH) == 0)
		return 0;
	return 1;
}

/* Memory writes occured, invalidate according to what we know. Passing
   NULL indicates unknown memory changes */

static void invalidate_node(struct node *n)
{
/*	printf(";invalidate node\n"); */
	/* For now don't deal with the complex cases of whether we might
	   invalidate another object */
	if (reg[R_A].state != T_CONSTANT)
		reg[R_A].state = INVALID;
	if (reg[R_X].state != T_CONSTANT)
		reg[R_X].state = INVALID;
	if (reg[R_TMPL].state != T_CONSTANT)
		reg[R_TMPL].state = INVALID;
	if (reg[R_TMPH].state != T_CONSTANT)
		reg[R_TMPH].state = INVALID;
}

static void invalidate_mem(void)
{
	if (reg[R_A].state != T_CONSTANT)
		reg[R_A].state = INVALID;
	if (reg[R_X].state != T_CONSTANT)
		reg[R_X].state = INVALID;
	if (reg[R_TMPL].state != T_CONSTANT)
		reg[R_TMPL].state = INVALID;
	if (reg[R_TMPH].state != T_CONSTANT)
		reg[R_TMPH].state = INVALID;
}

static void set_reg(unsigned r, unsigned v)
{
	reg[r].state = T_CONSTANT;
	reg[r].value = (uint8_t)v;
}

/* TODO: worth checking these for cases they already are the same ? */
static void tax(void)
{
	invalidate_node(NULL);
	memcpy(reg + R_X, reg + R_A, sizeof(struct regtrack));
	output("tax");
}

static void txa(void)
{
	invalidate_node(NULL);
	memcpy(reg + R_A, reg + R_X, sizeof(struct regtrack));
	output("txa");
}

static void tay(void)
{
	memcpy(reg + R_Y, reg + R_A, sizeof(struct regtrack));
	output("tay");
}

static void store_xa_tmp(void)
{
	if (tmp_contains_xa()) {
		printf("; avoided reload of @tmp\n"); 
		return;
	}
	memcpy(reg + R_TMPL, reg + R_A, sizeof(struct regtrack));
	memcpy(reg + R_TMPH, reg + R_X, sizeof(struct regtrack));
	output("sta @tmp");
	output("stx @tmp+1");
}

static void store_a_tmp(void)
{
	memcpy(reg + R_TMPL, reg + R_A, sizeof(struct regtrack));
	output("sta @tmp");
}

/* Used as helpers when doing a single depth push op of A as happens. Not
   stack tracking so not safe if can recurse */
static void saved_a(void)
{
	memcpy(&rsaved, reg + R_A, sizeof(struct regtrack));
}

static void restored_a(void)
{
	memcpy(reg + R_A, &rsaved, sizeof(struct regtrack));
}

/*
 *	Example size handling. In this case for a system that always
 *	pushes words.
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

/*
 *	For 6502 we keep byte objects byte size
 */
static unsigned get_stack_size(unsigned t)
{
	return get_size(t);
}


/* Generate a call to an internal helper */
static void gen_internal(const char *p)
{
	invalidate_regs();
	output("jsr __%s", p);
}

static void repeated_op(unsigned n, const char *o)
{
	while(n--)
		output(o);
}

/* At some point instead pass flags into the helpers */
static unsigned direct_za(const char *op)
{
	if (cpu == NMOS_6502)
		return 0;
	return 1;
}

static unsigned direct_z(const char *op)
{
	if (cpu == NMOS_6502)
		return 0;
	if (op[2] == 'x' || op[2] == 'y')
		return 0;
	return 1;
}

/* operations we can cover with pri8/pri16 that have side effects so must
   not be folded into things */
static unsigned has_sideeffect(struct node *n)
{
	/* We can generate these as pri16 ops but they are not load based
	   so we must not fast cast them as they have side effects */
	if (n->op == T_LSTORE || n->op == T_LBSTORE || n->op == T_NSTORE)
		return 1;
	return 0;
}


static unsigned can_bytecast(register struct node *n)
{
	register struct node *r = n->right;
	/* Can we eliminate the cast because we are only working in
	   byte sized objects anyway ? */
	if (n->type != T_CAST)
		return 0;
	/* Can't reliably play games if it might have a whole subtree */
	/* TODO: we can restrict this a fair bit more if we know
	   whether we are coming from gen_node or not */
	if (has_sideeffect(n))
		return 0;
	if ((!PTR(n->type) && n->type != CINT && n->type != UINT) || r->type != UCHAR)
		return 0;
	return 1;
}

/* Construct a direct operation if possible for the primary op */
/* Must not corrupt X unless explcitly asked to load X. Our byte operators
   rely on this as a tiny optimization as the expect the pointer on stuff
   like x++ to be in X and the low half of @tmp

   r is the right hand side of the main node n usually, but may change when
   we call this recursively when elimninating casts or other nodes we
   can throw away */
static int do_pri8(struct node *n, struct node *r, const char *op, void (*pre)(struct node *__n))
{
	unsigned v = n->value;
	const char *name;

	/* We can fold in some simple casting */
	if (can_bytecast(n))
		return do_pri8(n, r->right, op, pre);

	switch(n->op) {
	case T_LABEL:
		pre(n);
		output("%s #<T%u+%u", op,  n->val2, v);
		return 1;
	case T_NAME:
		pre(n);
		name = namestr(n->snum);
		output("%s #<_%s+%u", op,  name, v);
		return 1;
	case T_CONSTANT:
		/* These had the right squashed into them */
	case T_LREF:
	case T_NREF:
	case T_LBREF:
	case T_LSTORE:
	case T_NSTORE:
	case T_LBSTORE:
		/* These had the right squashed into them */
		r = n;
		break;
	}

	v = r->value;

	/* If the tree is        op
	 *                         \
	 *                         cast
	 *                           \
	 *                           fetchop
	 *
	 * and we are fetching byte or word and casting cleanly to byte
	 * then the cast can be ignored as it's implicit in the byte op
	 */
	if (can_bytecast(r)) {
		r = r->right;
		v = r->value;
	}

	switch(r->op) {
	case T_CONSTANT:
		pre(n);
		if (strcmp(op, "lda") == 0)
			load_a(v);
		else if (strcmp(op, "ldx") == 0)
			load_x(v);
		else
			output("%s #%u", op, r->value & 0xFF);
		return 1;
	case T_LREF:
	case T_LSTORE:
		v += sp;
		if (v == 0 && direct_z(op)) {
			pre(n);
			output("%s (@sp)", op);
			return 1;
		}
		if (v <= 255) {
			pre(n);
			load_y(v);
			output("%s (@sp),y", op);
			return 1;
		}
		/* We rarely hit this case but we have to deal with it */
		/* A is needed if storing */
		if (r->op == T_LSTORE)
			tax();
		output("lda @sp");
		output("clc");
		output("adc #%u", BYTE(v));
		output("sta @tmp2");
		output("lda @sp+1");
		output("adc #%u", BYTE(v >> 8));
		output("sta @tmp2+1");
		if (r->op == T_LSTORE)
			txa();
		/* (@tmp2) is now our target */
		if (cpu > NMOS_6502)
			output("%s (@tmp2)", op);
		else {
			load_y(0);
			output("%s (@tmp2),y", op);
		}
		return 1;
	case T_NREF:
	case T_NSTORE:
		pre(n);
		name = namestr(r->snum);
		output("%s _%s+%u", op,  name, (unsigned)r->value);
		return 1;
	case T_LBSTORE:
	case T_LBREF:
		pre(n);
		output("%s T%u+%u", op,  r->val2, (unsigned)r->value);
		return 1;
	/* If we add registers
	case T_RREF:
		output("%s __reg%u", op, r->val2);
		return 1;*/
	}
	return 0;
}

/* Construct a direct operation if possible for the primary op */
static int do_pri8hi(struct node *n, const char *op, void (*pre)(struct node *__n))
{
	struct node *r = n->right;
	const char *name;
	unsigned v = n->value;

	/* We can fold in some simple casting */
	if (n->type == T_CAST) {
		if ((!PTR(n->type) && n->type != CINT && n->type != UINT) || r->type != UCHAR)
			return 0;
		/* We need to do it on 0 */
		load_a(0);
		n = n->right;
		v = n->value;
		r = n->right;
	}
	switch(n->op) {
	case T_LABEL:
		pre(n);
		output("%s #>T%u+%", op,  n->val2, v);
		return 1;
	case T_NAME:
		pre(n);
		name = namestr(n->snum);
		output("%s #_%s+%u", op,  name, v);
		return 1;
	case T_CONSTANT:
		/* These had the right squashed into them */
	case T_LREF:
	case T_NREF:
	case T_LBREF:
	case T_LSTORE:
	case T_NSTORE:
	case T_LBSTORE:
		/* These had the right squashed into them */
		r = n;
		break;
	}

	v = r->value;

	switch(r->op) {
	case T_CONSTANT:
		pre(n);
		v >>= 8;
		if (strcmp(op, "lda") == 0)
			load_a(v);
		else if (strcmp(op, "ldx") == 0)
			load_x(v);
		else
			output("%s #%u", op, v);
		return 1;
	case T_LREF:
	case T_LSTORE:
		v += sp;
		if (v < 254) {
			pre(n);
			load_y(v + 1) ;
			output("%s (@sp),y", op);
			return 1;
		}
		/* For now punt */
		return 0;
	case T_NREF:
	case T_NSTORE:
		pre(n);
		name = namestr(r->snum);
		output("%s _%s+%u", op,  name, v + 1);
		return 1;
	case T_LBSTORE:
	case T_LBREF:
		pre(n);
		output("%s T%u+%u", op,  r->val2, v + 1);
		return 1;
	/* If we add registers
	case T_RREF:
		output("%s __reg%u+1", op, r->val2);
		return 1;*/
	}
	return 0;
}

/* 16bit/ We are rather limited here because we only have a few ops with x */
/* As with do_pri8 r is usually the right node of n but will be shifted
   recursively if we have casts */
static int do_pri16(struct node *n, struct node *r, const char *op, void (*pre)(struct node *__n))
{
	const char *name;
	unsigned v = n->value;

	/* We can fold in some simple casting */
#if 0
	if (n->type == T_CAST) {
		if ((!PTR(n->type) && n->type != CINT && n->type != UINT) || r->type != UCHAR)
			return 0;
		load_x(0);
		/* Just do the right hand side */
		/* Should this be pri8 ?? */
		return do_pri16(n, r->right, op, pre);
	}
#endif
	switch(n->op) {
	case T_LABEL:
		pre(n);
		output("%sa #<T%u+%u", op,  n->val2, v);
		output("%sx #>T%u+%u", op,  n->val2, v);
		return 1;
	case T_NAME:
		pre(n);
		name = namestr(n->snum);
		output("%sa #<_%s+%u", op,  name, v);
		output("%sx #>_%s+%u", op,  name, v);
		return 1;
	case T_LOCAL:
	case T_LREF:
	case T_NREF:
	case T_LBREF:
	case T_LSTORE:
	case T_NSTORE:
	case T_LBSTORE:
	case T_CONSTANT:
		/* These had the right squashed into them */
		r = n;
	}

	v = r->value;

	if (get_size(r->type) != 2)
		error("pri16bt");
	switch(r->op) {
	case T_CONSTANT:
		pre(n);
		if (strcmp(op, "ld") == 0) {
			load_a(v);
			load_x(v >> 8);
		} else {
			output("%sa #%u", op, v & 0xFF);
			output("%sx #%u", op, v >> 8);
		}
		return 1;
	case T_LREF:
		v += sp;
		if (optsize && v < 255 && strcmp(op, "ld") == 0) {
			pre(n);
			if (v) {
				load_y(v + 1);
				output("jsr __gloy");
			} else {
				output("jsr __gloy0");
			}
			const_y_set(v);
			return 1;
		}
		if (v < 255) {
			pre(n);
			load_y(v + 1);
			invalidate_a();
			output("%sa (@sp),y", op);
			tax();
			if (v == 0 && direct_za(op))
				output("%sa (@sp)", op);
			else {
				load_y(v);
				output("%sa (@sp),y", op);
			}
			return 1;
		}
		/* We rarely hit this case but we have to deal with it */
		/* XA can be destroyed thankfully */
		output("lda @sp");
		output("clc");
		output("adc #%u", BYTE(v));
		output("sta @tmp2");
		output("lda @sp+1");
		output("adc #%u", BYTE(v >> 8));
		output("sta @tmp2+1");
		/* (@tmp2) is now our target */
		load_y(1);
		output("lda (@tmp2),y");
		tax();
		output("dey");
		output("lda (@tmp2),y");
		return 1;
	case T_LSTORE:
		if (v < 255) {
			pre(n);
			if (v == 0 && direct_za(op))
				output("%sa (@sp)", op);
			else {
				load_y(v);
				output("%sa (@sp),y", op);
			}
			txa();
			load_y(v + 1);
			output("%sa (@sp),y", op);
			return 1;
		}
		/* We rarely hit this case but we have to deal with it */
		/* @tmp is free */
		output("sta @tmp");
		output("lda @sp");
		output("clc");
		output("adc #%u", BYTE(v));
		output("sta @tmp2");
		output("lda @sp+1");
		output("adc #%u", BYTE(v >> 8));
		output("sta @tmp2+1");
		/* (@tmp2) is now our target */
		load_y(1);
		txa();
		output("sta (@tmp2),y");
		output("dey");
		output("lda @tmp");
		output("sta (@tmp2),y");
		return 1;
	case T_NSTORE:
	case T_NREF:
		name = namestr(r->snum);
		pre(n);
		output("%sa _%s+%u", op,  name, (unsigned)r->value);
		output("%sx _%s+%u", op,  name, ((unsigned)r->value) + 1);
		return 1;
	case T_LBSTORE:
	case T_LBREF:
		pre(n);
		output("%sa T%u+%u", op,  r->val2, (unsigned)r->value);
		output("%sx T%u+%u", op,  r->val2, ((unsigned)r->value) + 1);
		return 1;
	/* If we add registers
	case T_RREF:
		pre(n);
		output("%sa __reg%u", op, r->val2);
		output("%sx __reg%u + 1", op,  r->val2);
		return 1;*/
	}
	return 0;
}

static void pre_none(struct node *n)
{
}

static void pre_store8(struct node *n)
{
	store_a_tmp();
}

static void pre_store16(struct node *n)
{
	store_xa_tmp();
}

static void pre_store16clx(struct node *n)
{
	store_xa_tmp();
	load_x(0);
}

static void pre_pha(struct node *n)
{
	output("pha");
}

static int pri8(struct node *n, const char *op)
{
	return do_pri8(n, n->right, op, pre_none);
}

static int pri16(struct node *n, const char *op)
{
	return do_pri16(n, n->right, op, pre_none);
}

static unsigned fast_castable(struct node *n)
{
	/* Is this a case we can just flow into the code. Usually that's
	   a uchar to int */
	if (n->op != T_CAST || n->right->type != UCHAR || get_size(n->type) != 2)
		return 0;
	return 1;
}

/*
 *	Handle byteable helpers so we correctly force them to do byte
 *	sized help
 */
static void helper_sb(struct node *n, char *helper)
{
	unsigned t;
	if (n->flags & BYTEOP) {
		t = CCHAR;
		if (n->right->type & UNSIGNED)
			t = UCHAR;
		do_helper(n, helper, t, 1);
		/* Q: Do we need to cast in some cases then. We are ok
		   for conditionals but others ? */
		if (n->flags & BYTEROOT)
			printf(";cast required.\n");
	} else
		helper_s(n, helper);
}

static int pri8_help(struct node *n, char *helper)
{
	struct node *r = n->right;
        /* Don't try and fold stores with side effects */
	if (has_sideeffect(r))
		return 0;
	/* Special case for cast first */
	if (fast_castable(r)) {
		if (do_pri8(n, r->right, "lda", pre_store8)) {
			helper_sb(n, helper);
			return 1;
		}
	}
	/* If we can't guarantee do_pri8 protects X then in future we'd
	    need to check r size for 2 and if so pre_store16 here */
	if (do_pri8(n, r, "lda", pre_store8)) {
		/* Helper invalidates A itself */
		helper_sb(n, helper);
		return 1;
	}
	return 0;
}

static void pre_fastcast(struct node *n)
{
	store_a_tmp();
	/* The M740 is a fairly complete subset of the 65C02 but lacks STZ */
	if (cpu == CMOS_M740)
		output("stm #0");
	else if (cpu > NMOS_6502)
		output("stz @tmp+1");
	else {
		load_x(0);
		output("stx @tmp+1");
	}
}

/* We've got thje left in XA, the right is byte sized so store the working
   value in @tmp, then clear X and do a byte sized evaluation */
static void pre_fastcastx0(struct node *n)
{
	store_xa_tmp();
	load_x(0);
}

static int pri16_help(struct node *n, char *helper)
{
	struct node *r = n->right;
	unsigned v = r->value;
	unsigned s = get_size(r->type);

	/* Don't try and fold stores as they need to actually do the
	   store */
	if (has_sideeffect(r))
		return 0;
	/* Special case for cast first */
	if (fast_castable(r)) {
		if (get_size(r->right->type) == 2) {
			if (do_pri16(n, r->right, "ld", pre_fastcast)) {
				helper_s(n, helper);
				return 1;
			}
		} else {
			if (do_pri8(n, r->right, "lda", pre_fastcastx0)) {
				helper_s(n, helper);
				return 1;
			}
		}
	}


	if (s == 1) {
		if (do_pri8(n, r, "lda", pre_store16clx)) {
			helper_s(n, helper);
			return 1;
		}
	} else if (s == 2) {
		if (do_pri16(n, r, "ld", pre_store16)) {
			/* Helper invalidates XA itself */
			helper_s(n, helper);
			return 1;
		}
	}
	/* As we are saving via @tmp we can do these as well */
	switch(r->op) {
	case T_ARGUMENT:
		v += frame_len + argbase;
	case T_LOCAL:
		v += sp;
		if (v < 255) {
			pre_store16(n);
			if (v) {
				load_a(v);
				output("jsr __asp\n");
			} else {
				output("lda @sp\n");
				output("ldx @sp+1\n");
			}
			set_xa_node(r);
			helper_s(n, helper);
			return 1;
		}
		break;
	}
	return 0;
}

/*
 *	Try and construct a short form helper for the expression
 *	to avoid the expensive stack operations.
 */
static int pri_help(struct node *n, char *helper)
{
	unsigned s = get_size(n->type);

	if (s == 1 && pri8_help(n, helper))
		return 1;
	else if (s == 2 && pri16_help(n, helper))
		return 1;
	return 0;
}

/*
 *	Shunt some things via a shorter form when right arg is a local
 */

unsigned can_yop(struct node *n)
{
	unsigned v;
	struct node *r = n->right;

	if (opt > 1)
		return 0;
	if (r == NULL || r->op != T_LREF)
		return 0;
	/* Point Y at top byte versus @sp */
	v = r->value + sp + get_size(r->type) - 1;
	if (v > 255)
		return 0;
	/* Don't get clever with float for the moment : TODO */
	if (r->type == FLOAT)
		return 0;
	return 1;
}

unsigned local_yop(struct node *n, const char *name)
{
	struct node *r = n->right;
	unsigned v;

	if (r == NULL || r->op != T_LREF)
		return  0;
	/* Point Y at top byte versus @sp */
	v = r->value + sp + get_size(r->type) - 1;
	if (v > 255)
		return 0;
	/* Don't get clever with float for the moment : TODO */
	if (r->type == FLOAT)
		return 0;
	load_y(v);
	helper(n, name);
	return 1;
}

unsigned local_yop_s(struct node *n, const char *name)
{
	struct node *r = n->right;
	unsigned v;
	if (r == NULL || r->op != T_LREF)
		return  0;
	/* Point Y at top byte versus @sp */
	v = r->value + sp + get_size(r->type) - 1;
	if (v > 255)
		return 0;
	/* Don't get clever with float for the moment : TODO */
	if (r->type == FLOAT)
		return 0;
	load_y(v);
	helper_s(n, name);
	return 1;
}

static int pri_cchelp(register struct node *n, char *helper)
{
	register struct node *r = n->right;
	unsigned v = r->value;
	/* Sizing for comparisons is from the children */
	unsigned s = get_size(r->type);
	unsigned is_byte = (n->flags & (BYTETAIL | BYTEOP)) == (BYTETAIL | BYTEOP);
	char buf[32];

	if (is_byte)
		s = 1;

	n->flags |= ISBOOL;

	if (can_yop(n)) {
		strcpy(buf, "l_");
		strcat(buf, helper);
		local_yop_s(n, buf);
		return 1;
	}

#if 0
	/* Can't do this as we've already pushed the other half as a word */
	/* In the case where we know the upper half of the value. Need to sort
	   the signed version out eventually */
	if (r->op == T_CONSTANT && s == 2 && (n->type & UNSIGNED)) {
		if (reg[R_X].state == T_CONSTANT && reg[R_X].value == (v >> 8)) {
			/* We take the size of a comparison from the right not
			   the node itself as the output type is always 0/1 */
			r->type &= UNSIGNED;
			r->type |= CCHAR;
			return pri8_help(n, helper);
		}
	}
	/* DEBUG ME TODO */
	/* Byte sized result operations are handled via pri8_help after
	   we fudge the type info a bit */
	if (n->flags & BYTEOP) {
		n->type &= UNSIGNED | PTRMASK;
		n->type |= CCHAR;
		return pri8_help(n, helper);
	}
#endif
	if (s == 1 && pri8_help(n, helper))
		return 1;
	else if (s == 2 && pri16_help(n, helper))
		return 1;
	return 0;
}

static void pre_clc(struct node *n)
{
	output("clc");
}

static void pre_sec(struct node *n)
{
	output("sec");
}

static void pre_stash(struct node *n)
{
	store_xa_tmp();
}

/*
 *	inc and dec are complicated but worth some effort as they
 *	are so commonly used for small constants. We could o with
 *	spotting and folding some stuff like *x++ perhaps to get a
 *	bit better codegen.
 */

/* Try to write inline inc and dec for simple forms */
static int leftop_memc(struct node *n, const char *op)
{
	struct node *l = n->left;
	struct node *r = n->right;
	unsigned v;
	unsigned sz = get_size(n->type);
	char *name;
	unsigned count;
	unsigned nr = n->flags & NORETURN;
	char *cc = "ne";

	if (sz > 2)
		return 0;
	if (r->op != T_CONSTANT || r->value > 2)
		return 0;
	else
		count = r->value;

	/* Being super clever doesn't help if we need the value anyway */
	if (!nr && (n->op == T_PLUSPLUS || n->op == T_MINUSMINUS))
		return 0;

	v = l->value;

	/* DEC is hard as it doesn't affect carry for wrap detection so
	   only do byte sized the fast way */
	if (*op == 'd' && sz > 1)
		return 0;

	switch(l->op) {
	case T_NAME:
		name = namestr(l->snum);
		while(count--) {
			output("%s _%s+%u", op, name, v);
			if (sz == 2) {
				output("b%s X%u", cc, ++xlabel);
				output("%s _%s+%u", op, name, v + 1);
				label("X%u", xlabel);
			}
		}
		if (!nr) {
			output("lda _%s+%u", name, v);
			if (sz == 2)
				output("ldx _%s+%u", name, v + 1);
		}
		return 1;
	case T_LABEL:
		while(count--) {
			output("%s T%u+%u", op, (unsigned)l->val2, v);
			if (sz == 2) {
				output("b%s X%u", cc, ++xlabel);
				output("%s T%u+%u", op, (unsigned)l->val2, v + 1);
				label("X%u", xlabel);
			}
		}
		if (!nr) {
			output("lda T%u+%u", (unsigned)l->val2, v);
			if (sz == 2)
				output("ldx T%u+%u", (unsigned)l->val2, v + 1);
		}
		return 1;
	case T_ARGUMENT:
		v += argbase + frame_len;
	case T_LOCAL:
		v += sp;
		return 0;
		/* Don't seem to have a suitable addressing mode */
	}
	return 0;
}


/* Do a 16bit operation upper half by switching X into A */
static unsigned try_via_x(struct node *n, const char *op, void (*pre)(struct node *))
{
	struct node *r = n->right;
	if (optsize)  {
		unsigned rop = r->op;
		unsigned v = r->value;
		if (rop == T_LREF) {
			v += sp;
#if 0
			/* This turns out not worth doing */
			if (v == 0) {
				output("jsr __%ssp0", op);
				set_reg(R_Y, 1);
				invalidate_x();
				invalidate_a();
				return 1;
			} else
#endif
			if (v < 255) {
				load_y(v);
				output("jsr __%sspy", op);
				const_y_set(reg[R_Y].value + 1);
				invalidate_x();
				invalidate_a();
				return 1;
			}
		}
		if (rop == T_CONSTANT && v < 256) {
			load_y(v);
			output("jsr __%s8y", op);
			invalidate_x();
			invalidate_a();
			return 1;
		}
	}
	/* FIXME: need to untangle all the pri8 stuff so we can do
	   NAME and LABEL here */
	if (do_pri8(n, r, op, pre) == 0)
		return 0;
	output("pha");
	txa();
	do_pri8hi(n, op, pre_none);
	tax();
	output("pla");

	invalidate_a();
	invalidate_x();
	return 1;
}

static void squash_node(struct node *n, struct node *o)
{
	n->value = o->value;
	n->val2 = o->val2;
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

static void swap_op(struct node *n, unsigned op)
{
	struct node *l = n->left;
	n->left = n->right;
	n->right = l;
	n->op = op;
}

static unsigned is_simple(struct node *n)
{
	unsigned op = n->op;

	/* Multi-word objects are never simple */
	if (!PTR(n->type) && (n->type & ~UNSIGNED) > CSHORT)
		return 0;

	/* We can use these directly with primary operators on A */
	if (op == T_CONSTANT || op == T_LABEL || op == T_NAME || (op == T_LREF && n->value < 255))
		return 10;
	/* Can go via @tmp */
	if (op == T_NREF || op == T_LBREF)
		return 1;
	/* Hard */
	return 0;
}

/* Integer Log 2 of a given value.
 * If x is exact positive power of two, return log2(x).
 * If x is zero, negative, or not a power of two, return -1.
 */
static int intlog2(long x)
{
	int lg2;
	/* x must be positive and have only one bit set */
	if (x <= 0)
		return -1;
	if ((x & (x-1)) != 0)
		return -1;
	/* There's only one bit set. Shift it right until gone */
	for(lg2 = 0; x >>= 1;)
		lg2++;
	return lg2;
}

/*
 * Shift A left by n bits in as few instructions as possible
 * n 0..5 n bytes
 * 6 5 bytes
 * 7 4 bytes
 * (worst case 5 bytes)
 */
static void asl_a(unsigned n)
{
	if (n == 0)
		return;

	if (n >= 8) {
		load_a(0);
		return;
	}

	if (n <= 5)
		repeated_op(n, "asl a"); /* Shift left up to 5 times */
	else if (n==6) {
		repeated_op(3, "ror a"); /* Rotate right 3 times */
		output("and #0xc0");     /* and clear unwanted bits */
	} else { /* (n==7) */
		repeated_op(2, "ror a"); /* Rotate right 2 times */
		output("and #0x80");     /* And clear unwanted bits */
	}

	invalidate_a();
}

/*
 * Shift A right by n bits in as few instructions as possible
 * (worst case 5 bytes)
 * Left bits filled with *zero*
 */
static void lsr_a(unsigned n)
{
	if (n == 0)
		return;
	if (n >= 8) {
		load_a(0);
		return;
	}
	if (n <= 5) {
		repeated_op(n, "lsr a");
	} else if (n == 6) {
		output("asl a");
		repeated_op(2, "rol a");
		output("and #0x03");
	} else { /* n==7 */
		output("asl a");  // Bit 7 to C
		output("lda #0"); // Clear the other bits
		output("rol a");  // C to bit 0
	}
	invalidate_a();
}

/*
 * Shift A right by n bits in as few instructions as possible
 * (worst case 5 bytes)
 * Left bits filled with *zero*
 */
static void asr_a(unsigned n)
{
	if (n == 0)
		return;
	if (n >= 8) {
		load_a(0);
		return;
	}
	if (n >= 3 && optsize)
		output("jsr __asra%u", n);
	else while(n--) {
		output("cmp #0x80");
		output("ror a");
	}
	invalidate_a();
}

/* Chance to rewrite the tree from the top rather than none by node
   upwards. We will use this for 8bit ops at some point and for cconly
   propagation */
struct node *gen_rewrite(struct node *n)
{
	byte_label_tree(n, BTF_RELABEL);
	return n;
}

/*
 *	We need to look at rewriting deref and assign with plus offset
 *	as if we've stuffed the ptr into tmp we can use ,y for deref
 */
struct node *gen_rewrite_node(struct node *n)
{
	struct node *l = n->left;
	struct node *r = n->right;
	unsigned op = n->op;
	unsigned nt = n->type;
	int log2const;
	unsigned s = get_size(n->type);
	unsigned off;

	/* TODO
		- rewrite some reg ops
	*/

	if (s <= 2 && (op == T_DEREF || op == T_DEREFPLUS)) {
		if (op == T_DEREF)
			n->value = 0;
		if (r->op == T_PLUS) {
			off = n->value + r->right->value;
			if (r->right->op == T_CONSTANT && off < 253) {
				n->op = T_DEREFPLUS;
				free_node(r->right);
				n->right = r->left;
				n->value = off;
				free_node(r);
				return gen_rewrite_node(n);
			}
		}
	}
	/* Squash typical indirect struct references within our reach */
	if (s <=2 && op == T_DEREFPLUS && r->op == T_LREF && n->value < 255) {
		/* At this point r->value is the offset for the local */
		/* n->value is the offset for the ptr load */
		r->val2 = n->value;		/* Save the offset so it is squashed in */
		squash_right(n, T_LDEREF);	/* n->value becomes the local ref */
		return n;
	}
	/* *regptr */
	if (op == T_DEREF && r->op == T_RREF) {
		n->op = T_RDEREF;
		n->right = NULL;
		free_node(r);
		return n;
	}
	/* *regptr = */
	if (op == T_EQ && l->op == T_RREF) {
		n->op = T_REQ;
		n->left = NULL;
		free_node(l);
		return n;
	}
	/* Rewrite references into a load operation */
	if (nt == CCHAR || nt == UCHAR || nt == CSHORT || nt == USHORT || PTR(nt)) {
		if (op == T_DEREF) {
			if (r->op == T_LOCAL || r->op == T_ARGUMENT) {
				if (r->op == T_ARGUMENT)
					r->value += argbase + frame_len;
				squash_right(n, T_LREF);
				return n;
			}
			if (r->op == T_REG) {
				squash_right(n, T_RREF);
				return n;
			}
			if (r->op == T_NAME) {
				squash_right(n, T_NREF);
				return n;
			}
			if (r->op == T_LABEL) {
				squash_right(n, T_LBREF);
				return n;
			}
		}
		if (op == T_EQ) {
			if (l->op == T_NAME) {
				squash_left(n, T_NSTORE);
				return n;
			}
			if (l->op == T_LABEL) {
				squash_left(n, T_LBSTORE);
				return n;
			}
			if (l->op == T_LOCAL || l->op == T_ARGUMENT) {
				if (l->op == T_ARGUMENT)
					l->value += argbase + frame_len;
				squash_left(n, T_LSTORE);
				return n;
			}
			if (l->op == T_REG) {
				squash_left(n, T_RSTORE);
				return n;
			}
		}
	}
	/* Eliminate casts for sign, pointer conversion or same */
	if (op == T_CAST && cast_fold_safe(r->op)) {
		if (nt == r->type || (nt ^ r->type) == UNSIGNED ||
		 (PTR(nt) && PTR(r->type))) {
			free_node(n);
			r->type = nt;
			return r;
		}
	}
	/* Rewrite function call of a name into a new node so we can
	   turn it easily into call xyz */
	if (op == T_FUNCCALL && r->op == T_NAME && PTR(r->type) == 1) {
		n->op = T_CALLNAME;
		n->snum = r->snum;
		n->value = r->value;
		n->val2 = r->val2;
		free_node(r);
		n->right = NULL;
	}
	/* Commutive operations. We can swap the sides over on these */
	if (op == T_AND || op == T_OR || op == T_HAT || op == T_STAR || op == T_PLUS) {
/*		printf(";left %d right %d\n", is_simple(n->left), is_simple(n->right)); */
		if (is_simple(n->left) > is_simple(n->right)) {
			n->right = l;
			n->left = r;
		}
	}
	/* Reverse the order of comparisons to make them easier. C sequence points says this
	   is fine. Arguably we should implement T_LT and T_GTEQ and only do this if at that
	   point on code gen XA is holding the value we want for the left TODO */
	if (op == T_LT)
		swap_op(n, T_GT);
	if (op == T_GTEQ)
		swap_op(n, T_LTEQ);

	/* Some arithmetic optimisations (multiply, divide, remainder)
	 * where right op is a constant power of two can be re-written
	 * using bit operations.
	 *
	 * These rewrites are "almost" processor independent, in that
	 * for most microprocessors with 2's complement arithmetic, the same
	 * rewrites might apply. However, converting signed division and
	 * remainder isn't a good match for 6502's LSR instuctions so signed
	 * division and remainder isn't changed here. At least for now.
	 * (in particular we have to watch rounding)
	 *
	 * We always rewrite. We will then pick up the rewritten shift and
	 * figure out whether to inline it by optimisation level. The shift
	 * will always be the better option
	 */
	if (r != NULL && IS_INTARITH(nt) && r->op == T_CONSTANT) {
		switch(op) {
		/* Multiplication ( * and *= ) of integral types
		   by constant powers of two can be re-written
		   as left shifts. */
		case T_STAR:
		case T_STAREQ:
			/* TODO: Does not (yet) consider signed operations where the constant
			   is a negative power of two. For example,
			   "x * -8" could become "(-x) << 3" if x is signed
			   That's not yet done because it it's not a direct replacement
			   of one node with another.
			*/
			log2const = intlog2(r->value);
			if (log2const != -1) {
				n->op = op = (op == T_STAR ? T_LTLT : T_SHLEQ);
				r->value = log2const;
			}
			break;
		/* Division ( / and /= ) of integral types
		   by constant powers of two can be re-written as right shifts,
		   But cautions with respect to 6502 and signed right shifts.
		*/
		case T_SLASH:
		case T_SLASHEQ:
			/*	Only apply this optimisation to UNSIGNED types at the moment.
			  TODO for signed implementation
			  1.  Signed right shifts must maintain the sign bit which is a
			      PITA in 6502
			  2.  Signed operations where the constant is negative
			      i.e. "x / -8" could become "(-x) >> 3"
			  3.  For signed operations, direction of rounding towards
			      zero must be preserved.
			  */
				if (nt & UNSIGNED) {
					log2const = intlog2(r->value);
					if (log2const != -1) {
						n->op = op = (op==T_SLASH ? T_GTGT : T_SHREQ);
						n->op = op;
						r->value = log2const;
					}
				}
				break;

		/*
			Remainder operator T_PERCENT and T_PERCENTEQ can be reduced to bit
			operations when the right operatand is a power of two constant.
			As with T_SLASH and T_SLASHEQ, be aware that signed remainders are tricky
			on 6502 and therefore ignored for the moment. Maybe another time.
		*/
		case T_PERCENT:
		case T_PERCENTEQ:
			if (nt & UNSIGNED) {
				log2const = intlog2(r->value);
				if (log2const != -1) {
					/*
						"% (2^n)" becomes "& (2^n-1)""
					*/
					n->op = op = (op==T_PERCENT ? T_AND : T_ANDEQ);
					r->value = r->value-1;
				}
			}
			break;

		default:
			break;
		}
	}
	return n;
}

/* Export the C symbol */
void gen_export(const char *name)
{
	output(".export _%s\n", name);
}

void gen_segment(unsigned s)
{
	switch(s) {
	case A_CODE:
		output(".code");
		break;
	case A_DATA:
		output(".data");
		break;
	case A_LITERAL:
		output(".literal");
		break;
	case A_BSS:
		output(".bss");
		break;
	default:
		error("gseg");
	}
}

void gen_prologue(const char *name)
{
	printf("_%s:\n", name);
	unreachable = 0;
	invalidate_regs();
}

/* Generate the stack frame */
void gen_frame(unsigned size, unsigned aframe)
{
	frame_len = size;
	if (size == 0)
		return;

	sp = 0;
	/* Maybe shortcut some common values ? */

	if (size <= 4)
		output("jsr __sub%usp", size);
	else if (size < 256) {
		load_y(size);
		output("jsr __subysp");
	} else {
		size = -size;
		load_a(size & 0xFF);
		load_y(size >> 8);
		output("jsr __addyasp");
		invalidate_y();
	}
}

void gen_epilogue(unsigned size, unsigned argsize)
{
	if (sp)
		error("sp");

	if (unreachable)
		return;

	if (!(func_flags & F_VARARG))
		size += argsize;

	if (size > 256) {
		/* Ugly as we need to preserve AX */
		if (!(func_flags & F_VOIDRET)) {
			saved_a();
			output("pha");
		}
		load_a(size & 0xFF);
		load_y(size >> 8);
		output("jsr __addyasp");
		if (!(func_flags & F_VOIDRET)) {
			restored_a();
			output("pla");
		}
		output("rts");
	} else if (size > 4) {
		load_y(size);
		output("jmp __addysp");
	} else if (size)
		output("jmp __add%usp", size);
	else
		output("rts");
	unreachable = 1;
}

void gen_label(const char *tail, unsigned n)
{
	unreachable = 0;
	label("L%u%s", n, tail);
	invalidate_regs();
}

unsigned gen_exit(const char *tail, unsigned n)
{
	/* FIXME */
#if 0
	/* For now. We can only do this if argsize is zero or vararg
	   so needs more tracking and checking work */
	if (frame_len == 0) {
		output("rts");
		unreachable = 1;
		return 1;
	} else {
#endif
		output("jmp L%u%s", n, tail);
		unreachable = 1;
		return 0;
/*	} */
}

void gen_jump(const char *tail, unsigned n)
{
	if (unreachable)
		return;
	/* Want to use BRA if we have the option */
	if (cpu != NMOS_6502)
		output("bra L%u%s", n, tail);
	else
		output("jmp L%u%s", n, tail);
	unreachable = 1;
}

void gen_jfalse(const char *tail, unsigned n)
{
	if (unreachable)
		return;
	output("jeq L%u%s", n, tail);
}

void gen_jtrue(const char *tail, unsigned n)
{
	if (unreachable)
		return;
	output("jne L%u%s", n, tail);
}

void gen_switch(unsigned n, unsigned type)
{
	output("ldy #<Sw%u", n);
	output("sty @tmp");
	output("ldy #>Sw%u", n);
	output("sty @tmp+1");
	invalidate_regs();
	printf("\tjmp __switch");
	helper_type(type, 0);
	printf("\n");
}

void gen_switchdata(unsigned n, unsigned size)
{
	label("Sw%u", n);
	if (size > 255)
		error("sw");
	output("\t.byte %u", size);
}

void gen_case_label(unsigned tag, unsigned entry)
{
	unreachable = 0;
	label("Sw%u_%u", tag, entry);
	invalidate_regs();
}

void gen_case_data(unsigned tag, unsigned entry)
{
	/* Subtract one because of the way rts works */
	printf("\t.word Sw%u_%u - 1\n", tag, entry);
}

/*
 *	Our floats for now are in C so we need to call them as
 *	C functions not asm helpers
 */

/* True if the helper is to be called C style */
static unsigned c_style(struct node *np)
{
	register struct node *n = np;
	/* Assignment is done asm style */
	if (n->op == T_EQ || n->op == T_DEREF)
		return 0;
	/* Float ops otherwise are C style */
	if (n->type == FLOAT)
		return 1;
	n = n->right;
	if (n && n->type == FLOAT)
		return 1;
	return 0;
}

void gen_helpcall(struct node *n)
{
	invalidate_regs();
	/* Check both N and right because we handle casts to/from float in
	   C call format */
	if (c_style(n)) {
		gen_push(n->right);
		/* Compensate for the fact the called function will remove
		   this */
		sp -= get_stack_size(n->right->type);
	}
	printf("\tjsr __");
}

void gen_helptail(struct node *n)
{
}

void gen_helpclean(struct node *n)
{
	/* 6502 C functions pop their own stack so the C v asm helper
	   doesn't matter as it does on other processors but we must still
	   correct sp */
	if (c_style(n)) {
		/* C style ops that are ISBOOL didn't set the bool flags */
		if (n->flags & ISBOOL)
			tay();
	}
	/* Bool return is 0 or 1 therefore X is 0 */
	if (n->flags & ISBOOL)
		const_x_set(0);
}

void gen_data_label(const char *name, unsigned align)
{
	label("_%s", name);
}

void gen_space(unsigned value)
{
	output(".ds %u", value);
}

void gen_text_data(struct node *n)
{
	output(".word T%u", n->val2);
}

void gen_literal(unsigned n)
{
	if (n)
		label("T%u", n);
}

void gen_name(struct node *n)
{
	output(".word _%s+%u", namestr(n->snum), WORD(n->value));
}

void gen_value(unsigned type, unsigned long value)
{
	if (PTR(type)) {
		output(".word %u", (unsigned) value);
		return;
	}
	switch (type) {
	case CCHAR:
	case UCHAR:
		output(".byte %u", (unsigned) value & 0xFF);
		break;
	case CSHORT:
	case USHORT:
		output(".word %u", (unsigned) value & 0xFFFF);
		break;
	case CLONG:
	case ULONG:
	case FLOAT:
		/* We are little endian */
		output(".word %u", (unsigned) (value & 0xFFFF));
		output(".word %u", (unsigned) ((value >> 16) & 0xFFFF));
		break;
	default:
		error("unsuported type");
	}
}

void gen_start(void)
{
	switch(cpu) {
	case CMOS_6502:
		puts("\t.65c02\n");
		break;
	case CMOS_65C816:
		puts("\t.65c816\n");
		break;
	}
	output(".code");
}

void gen_end(void)
{
}

void gen_tree(struct node *n)
{
	codegen_lr(n);
	label(";");
}


/*
 *	The million dollar question - where do working temporaries go
 *	- user stack
 *		- plenty of room
 *		- can access indirectly
 *	- system stack
 *		- less room
 *		- faster
 *		- must pull via A to access (or via X/Y on C02)
 *
 *	The system stack case is alas hard to generalize so we don't. We
 *	can however use the system stack via gen_shortcut if we find a
 *	must have case.
 *
 *	TODO; optimize push constant low, push constant 8bit value as 16bit
 *	in func args
 */
unsigned gen_push(struct node *n)
{
	unsigned s = get_stack_size(n->type);
	sp += s;
	/* These don't invalidate registers and set Y to 0, so handle them
	   directly */
	switch(s) {
		case 1:
			output("jsr __pushc");
			set_reg(R_Y, 0);
			return 1;
		case 2:
			output("jsr __push");
			set_reg(R_Y, 0);
			return 1;
		case 4:
			output("jsr __pushl");
			set_reg(R_Y, 0);
			return 1;
	}
	return 0;
}

static unsigned gen_const_lshift(unsigned v, unsigned s)
{
	/* Do nothing if shift is zero or undefined */
	if (v == 0 || v >= 8 * s)
		return 1;
	switch(s) {
	case 1: /* Byte shift A */
		/* Always 5 bytes or fewer */
		asl_a(v);
		return 1;
	case 2:
		if (!optsize && 1 <= v && v <=7 ) {
			/* 4+3v bytes
			   v==1 is faster and same size
			   v>=2 is faster but bigger */
			output("stx @tmp+1");
			repeated_op(v, "asl a\n\trol @tmp+1");
			output("ldx @tmp+1");
			invalidate_tmp();
			return 1;
		}
		if (v >= 8) {
			if (optsize && v >= 11)
				break;
			/* We get 8 bits of shift by moving A->X */
			asl_a(v & 7); /* Max 5 bytes */
			tax();
			load_a(0);
			return 1;
		}
		break;
	case 4:
		/* Long shift */
		/* 1, bit shifts are assumed fairly common */
		/* 8, 16, 24 bit shifts are 1,2,3 byte shifts */
		/* Anything else bloats pretty quickly */
		switch (v) {
			case 1:
				if (optsize)
					break;
				/* 11 bytes */
				invalidate_tmp();
				output("stx @tmp+1");
				output("asl a");
				output("rol @tmp+1");
				output("rol @hireg");
				output("rol @hireg+1");
				output("ldx @tmp+1");
				invalidate_a();
				invalidate_x();
				return 1;
			case 8:
				/* @hireg -> @hireg+1 */
				/* x-> @hireg */
				/* a-> x */
				/* 0-> a */
				if (optsize)
					break;
				/* 9 bytes */
				output("ldy @hireg");
				output("sty @hireg+1");
				output("stx @hireg");
				tax();
				load_a(0);
				return 1;
			case 16:
				/* x-> @hireg+1 */
				/* a-> @hireg */
				/* 0-> x */
				/* 0-> a */
				if(optsize)
					break;
				/* 7 bytes */
				output("stx @hireg+1");
				output("sta @hireg");
				load_x(0);
				load_a(0);
				return 1;
			case 24:
				/* a-> @hireg+1 */
				/* 0-> @hireg */
				/* 0-> x */
				/* 0-> a */
				if (optsize)
					break;
				/* 7 bytes */
				output("sta @hireg+1");
				load_x(0);
				load_a(0);
				output("sta @hireg");
				return 1;
			default:
				break;
		}
		default:
			break;
	}
	/* Helpers for the very common case are worth it */
	if (s == 2) {
		/* These intentionally don't touch @tmp */
		if (v & 4)
			output("jsr __lshift4");
		if (v & 3)
			output("jsr __lshift%u", v & 3);
		if (v & 8) {
			txa();
			load_a(0);
		}
		return 1;
	}
	return 0;
}

static unsigned gen_const_rshift(unsigned v, unsigned s, unsigned u)
{
	/* Do nothing if shift is zero or undefined */
	if (v == 0 || v >= 8 * s)
		return 1;

	/* Unsigned */
	switch(s) {
	case 1:
		/* TODO This code isn't currently reachable because / and >> operations
		   are never analysed as being "byteable" */
		if (u)
			lsr_a(v);
		else
			asr_a(v);
		return 1;
	case 2:
		if (v == 1) {
			/* lsr XA 6 bytes is always worth doing inline */
			output("pha");
			output("txa");
			if (u)
				output("lsr a");
			else {
				output("cmp #0x80");
				output("ror a");
			}
			output("tax");
			output("pla");
			output("ror a");
			invalidate_x();
			invalidate_a();
			return 1;
		}
		if (v >= 8) {
			/* X->A, X=0 or sign always worth doing*/
			txa();
			if (u) {
				lsr_a(v & 7);
				load_x(0);
			} else {
				asr_a(v & 7);
				output("jsr __castc_");
			}
			invalidate_a();
			return 1;
		}
		break;
	case 4:
		if (v == 1 && !optsize && u) {
			/* 10 bytes */
			output("lsr @hireg+1");
			output("ror @hireg");
			output("pha");
			output("txa");
			output("ror a");
			output("tax");
			output("pla");
			output("ror a");
			invalidate_a();
			invalidate_x();
			return 1;
		}
		if (v == 8 && u && !optsize) {
			/* X -> A */
			/* hireg -> x */
			/* hireg+1 -> hireg */
			/* 0 -> hireg+1 */
			/* Avoid using Y register */
			/* 14 bytes */
			output("stx @tmp"); // Save for A later
			output("ldx @hireg");
			output("lda @hireg+1");
			output("sta @hireg");
			invalidate_a();
			load_a(0);
			output("sta @hireg+1");
			output("lda @tmp"); // Old X, Neww A
			invalidate_x();
			invalidate_a();
			invalidate_tmpl();
			return 1;
		}
		if (v == 16 && !optsize) {
			/* 9-10 bytes */
			output("lda @hireg");
			output("ldx @hireg+1");
			invalidate_a();
			invalidate_x();
			if (u) {
				if (cpu != NMOS_6502) {
					output("stz @hireg");
					output("stz @hireg+1");
				} else {
					load_y(0);
					output("sty @hireg");
					output("sty @hireg+1");
				}
			} else {
				output("jsr __cast_l");
				invalidate_y();
			}
			return 1;
		}
		if (v >= 24 && !optsize) {
			/* 7-8 bytes */
			output("lda @hireg+1");
			if (u)
				lsr_a(v & 7);
			else
				asr_a(v & 7);
			if (u) {
				load_x(0);
				output("stx @hireg");
				output("stx @hireg+1");
			} else {
				output("jsr __castc_l");
				invalidate_y();
			}
			invalidate_a();
			invalidate_x();
			return 1;
		}
	}
	return 0;
}

static unsigned gen_const_mul(unsigned v, unsigned s)
{
	switch(s) {
	case 1:	/* Byte */
		switch(v) {
		/* Multiply by 2^n+1. Save original, shift (n) and add original */
		case 9:  /* 2^3+1, 8 bytes */
		case 5:  /* 2^2+1, 7 bytes */
			if (optsize || opt < 3)
				break;
			/* Fall through if -O3  */
			case 3:  /* 2^1+1, 6 bytes, always smaller and faster*/
				store_a_tmp();
				asl_a(intlog2(v-1));
				output("clc");
				output("adc @tmp");
				invalidate_tmpl();
				invalidate_a();
				return 1;
			default:
				break;
		}
		break;
	case 2:
		switch(v) {
		case 3:
			if (optsize || opt < 3)
				break;
			/* This is faster than calling the support routine
			   but at 17 bytes it's a bit of a bloat, so only
			   generate this version if we're agressively optimising
			   for speed and "*3" is especially important to you. If
			   maintainers want to get rid of this in future, that
			   is fair enough. I would not object. */

			/* XA->@tmp */
			store_xa_tmp();
			/* @tmp <<= 1 */
			output("asl @tmp");
			output("rol @tmp+1");
			invalidate_tmp();
			/* XA += @tmp */
			output("clc");
			output("adc @tmp");
			output("pha");
			output("txa");
			output("adc @tmp+1");
			output("tax");
			output("pla");
			invalidate_a();
			invalidate_x();
			invalidate_tmp();
			return 1;
		default:
			break;
		}
		break;
	default:
		/* For longs and floats there are no obvious multiply
		 * optimisations other than powers of two, dealt with
		 * in T_LTLT
		 */
		break;
	}
	return 0;
}

/*
 *	If possible turn this node into a direct access. We've already checked
 *	that the right hand side is suitable. If this returns 0 it will instead
 *	fall back to doing it stack based.
 *
 *	At this point in time n is the operation node, any left hand side
 *	operation has been done and the result is in hireg:XA as appropriate.
 *	The right hand node (or subtree) has not been evaluated so we must
 *	be careful not to shortcut anything
 */
unsigned gen_direct(struct node *n)
{
	unsigned s = get_size(n->type);
	struct node *r = n->right;
	unsigned nr = n->flags & NORETURN;
	unsigned is_byte = (n->flags & (BYTETAIL | BYTEOP)) == (BYTETAIL | BYTEOP);
	unsigned v;

	if (r)
		v = r->value;

	switch(n->op) {
	/* Clean up is special and must be handled directly. It also has the
	   type of the function return so don't use that for the cleanup value
	   in n->right */
	case T_CLEANUP:
		if (n->val2) {
			/* Only clean up vararg. stdarg is cleaned up by
			   the called function */
			if (v <= 4)
				output("jsr __add%usp", v);
			else if (v < 256) {
				load_y(v);
				output("jsr __addysp");
			} else {
				/* TODO: void varargs ? */
				saved_a();
				output("pha");
				load_y(v >> 8);
				load_a(v);
				output("jsr __addyasp");
				output("pla");
				restored_a();
			}
		}
		sp -= v;
		return 1;
	case T_EQ:	/* address in XA, can we build right ? */
		/* We already rewrite simple left hand sides into LSTORE
		   NSTORE etc. Here we try and handle the other common
		   case of  complexexpression = simple. This is often the
		   case with things like  *x++ = 0; */
		/* This might be BYTEROOT but it doesn't matter if so as the
		   type handling was done for us */
		if (s > 2)
			return 0;
		if (r->op == T_CONSTANT) {
			store_xa_tmp();
			load_a(BYTE(v));
			if (s == 1 && cpu != NMOS_6502) {
				output("sta (@tmp)");
				return 1;
			}
			load_y(0);
			output("sta (@tmp), y");
			if (s == 2) {
				load_a(v >> 8);
				load_y(1);
				output("sta (@tmp), y");
			}
			return 1;
		}

		/* We can't squash LSTORE etc but must evaluate the subtree */
		if (has_sideeffect(r))
			return 0;

		if (local_yop(n, "l_eq" ))
			return 1;
		if (s == 1 && do_pri8(n, r, "lda", pre_stash)) {
			invalidate_a();
			if (cpu != NMOS_6502)
				output("sta (@tmp)");
			else {
				load_y(0);
				output("sta (@tmp),y");
			}
			return 1;
		} else if (s == 2 && do_pri16(n, r, "ld", pre_stash)) {
			invalidate_x();
			invalidate_a();
			if (cpu != NMOS_6502)
				output("sta (@tmp)");
			else {
				load_y(0);
				output("sta (@tmp),y");
			}
			load_y(1);
			if (nr) {
				output("pha");
				saved_a();
			}
			txa();
			output("sta (@tmp),y");
			if (nr) {
				output("pla");
				restored_a();
			}
			return 1;
		}
		/* Complex on both sides. Do these the hard way. Not as bad
		   as it seems as these are not common */
		return 0;
	case T_AND:
		/* There are some cases we can deal with */
		if (s > 2)
			return 0;
		if (r->op == T_CONSTANT) {
			if (s == 2) {
				if ((v & 0xFF) == 0) {
					txa();
					do_pri8hi(n, "and", pre_none);
					tax();
					load_a(0);
					return 1;
				}
				if ((v & 0xFF00) == 0x0000)
					load_x(0);
				else if ((v & 0xFF00) != 0xFF00)
					return try_via_x(n, "and", pre_none);
			}
			if ((v & 0xFF) == 0x00)
				load_a(0);
			else if ((v & 0xFF) != 0xFF) {
				output("and #%u", v & 0xFF);
				const_a_set(reg[R_A].value & v);
			}
			return 1;
		}
		if (has_sideeffect(r))
			return 0;
		if (s == 1 && pri8(n, "and"))
			return 1;
		if (s == 2 && try_via_x(n, "and", pre_none))
			return 1;
		return pri_help(n, "andtmp");
	case T_OR:
		if (s > 2)
			return 0;
		if (r->op == T_CONSTANT) {
			if (s == 2) {
				if ((v & 0xFF) == 0xFF) {
					txa();
					do_pri8hi(n, "and", pre_none);
					tax();
					load_a(0xFF);
					return 1;
				}
				if ((v & 0xFF00) == 0xFF00)
					load_x(0xFF);
				else if ((v & 0xFF00) != 0x0000)
					return try_via_x(n, "ora", pre_none);
			}
			if ((v & 0xFF) == 0xFF)
				load_a(0xFF);
			else if ((v & 0xFF) != 0x00) {
				output("ora #%u", v & 0xFF);
				const_a_set(reg[R_A].value | v);
			}
			return 1;
		}
		if (has_sideeffect(r))
			return 0;
		if (s == 1 && pri8(n, "ora"))
			return 1;
		if (s == 2 && try_via_x(n, "ora", pre_none))
			return 1;
		return pri_help(n, "oratmp");
	case T_HAT:
		if (s > 2)
			return 0;
		if (r->op == T_CONSTANT) {
			if (s == 2) {
				if ((v & 0xFF00) != 0x0000)
					return try_via_x(n, "eor", pre_none);
			}
			if ((v & 0xFF) != 0x00) {
				output("eor #%u", ((unsigned)r->value) & 0xFF);
				const_a_set(reg[R_A].value ^ r->value);
			}
			return 1;
		}
		if (has_sideeffect(r))
			return 0;
		if (s == 1 && pri8(n, "eor"))
			return 1;
		if (s == 2 && try_via_x(n, "eor", pre_none))
			return 1;
		return pri_help(n, "eortmp");
	case T_PLUS:
		if (s > 2)
			return 0;
		if (cpu != NMOS_6502 && s == 1 && r->op == T_CONSTANT && v == 1) {
			output("inc a");
			const_a_set(reg[R_A].value + 1);
			return 1;
		}
		if (cpu != NMOS_6502 && s == 1 && r->op == T_CONSTANT && v == 0xFFFF) {
			output("dec a");
			const_a_set(reg[R_A].value - 1);
			return 1;
		}

		printf(";Right is %04X\n", r->op);
		if (has_sideeffect(r))
			return 0;

		if (s == 1 && do_pri8(n, r, "adc", pre_clc)) {
			if (r->op == T_CONSTANT)
				const_a_set(reg[R_A].value + r->value);
			else
				invalidate_a();
			return 1;
		}
		if (s == 2 && r->op == T_CONSTANT) {
			if (r->value <= 0xFF) {
				output("clc");
				output("adc #%u",v & 0xFF);
				output("bcc X%u", ++xlabel);
				output("inx");
				label("X%u", xlabel);
				const_a_set(reg[R_A].value + (v & 0xFF));
				/* TODO: set up X properly if known */
				invalidate_x();
				return 1;
			}
			if (r->value == 256) {
				output("inx");
				const_x_set(reg[R_X].value + 1);
				return 1;
			}
			if (r->value == 512) {
				output("inx");
				output("inx");
				const_x_set(reg[R_X].value + 2);
				return 1;
			}
		}
		printf(";Right via X S %u is %04X\n", s, r->op);
		if (s == 2 && try_via_x(n, "adc", pre_clc))
			return 1;
		return pri_help(n, "adctmp");
	case T_MINUS:
		if (s > 2)
			return 0;
		if (cpu != NMOS_6502 && s == 1 && r->op == T_CONSTANT && v == 1) {
			output("dec a");
			const_a_set(reg[R_A].value - 1);
			return 1;
		}
		if (cpu != NMOS_6502 && s == 1 && r->op == T_CONSTANT && v == 0xFFFF) {
			output("inc a");
			const_a_set(reg[R_A].value + 1);
			return 1;
		}

		if (has_sideeffect(r))
			return 0;
		if (s == 1 && do_pri8(n, n->right, "sbc", pre_sec)) {
			if (r->op == T_CONSTANT)
				const_a_set(reg[R_A].value - r->value);
			else
				invalidate_a();
			return 1;
		}
		if (s == 2 && r->op == T_CONSTANT) {
			if (r->value <= 0xFF) {
				output("sec");
				output("sbc #%u", v & 0xFF);
				output("bcs X%u", ++xlabel);
				output("dex");
				label("X%u", xlabel);
				const_a_set(reg[R_A].value - (v & 0xFF));
				/* TODO: we should probably set this up */
				invalidate_x();
				return 1;
			}
			if (r->value == 256) {
				output("dex");
				const_x_set(reg[R_X].value - 1);
				return 1;
			}
			if (r->value == 512) {
				output("dex");
				output("dex");
				const_x_set(reg[R_X].value - 2);
				return 1;
			}
		}
		if (s == 2 && try_via_x(n, "sbc", pre_sec))
			return 1;
		return pri_help(n, "sbctmp");
	case T_STAR:
		if (local_yop(n, "l_mul" ))
			return 1;
		/* Multiplication by integer powers of two have already been re-written
		   and inline code is generated as part of T_LTLT processing
		   Special case for a few constant multiplies that are not powers of two
		   Debatable if these are really worth doing. They are
		   faster but sometimes quite a lot bigger.
		*/

 		if (r->op == T_CONSTANT) {
 			if (gen_const_mul(v, s))
 				return 1;
		}
		return pri_help(n, "multmp");
	case T_SLASH:
		if (local_yop_s(n, "l_div"))
			return 1;
		return pri_help(n, "divtmp");
	case T_PERCENT:
		if (local_yop_s(n, "l_rem"))
			return 1;
		return pri_help(n, "remtmp");
	/*
	 *	There are various < 0, 0, !0, > 0 optimizations to do here
	 *	TODO - optimizations especially for bool/byteable cases
	 *	Need CCONLY to make this work really
	 */
	case T_EQEQ:
		if (r->op == T_CONSTANT && v == 0) {
			if (is_byte) {
				output("tax");	/* For now TODO */
				/* And fall through until we have CCONLY support */
			}
			/* TODO: not via helper */
			n->flags |= ISBOOL;
			helper(n, "not");
			return 1;
		}
		return pri_cchelp(n, "eqeqtmp");
	case T_GTEQ:
		return pri_cchelp(n, "lteqtmp");
	case T_GT:
		return pri_cchelp(n, "lttmp");
	case T_LTEQ:
		return pri_cchelp(n, "gteqtmp");
	case T_LT:
		return pri_cchelp(n, "gttmp");
	case T_BANGEQ:
		if (r->op == T_CONSTANT && v == 0) {
			if (is_byte) {
				output("tax");	/* For now TODO */
				/* And fall through until we have CCONLY support */
			}
			/* TODO: not via helper */
			n->flags |= ISBOOL;
			helper(n, "bool");
			return 1;
		}
		return pri_cchelp(n, "netmp");
	/* TODO: qq optimisations for >= fieldwidth ? */
	case T_LTLT:
		/* Optimise constant left shifts */
		if (r->op == T_CONSTANT)
			return gen_const_lshift(v, s);
		/* TODO long logic for more l_ yop helpers */
		if (s < 4 && local_yop(n, "l_ltlt"))
			return 1;
		return pri_help(n, "lstmp");
	case T_GTGT:
		/* Optimize constant right shifts */
		if (r->op == T_CONSTANT)
			return gen_const_rshift(v, s, n->type & UNSIGNED);
		if (s < 4 && local_yop_s(n, "l_gtgt"))
			return 1;
		return pri_help(n, "rstmp");

	/* TODO: special case by 1,2,4, maybe inline byte cases ? */
	/* We want to spot trees where the object on the left is directly
	   addressible and fold them so we can generate inc _reg, bcc, inc _reg+1 etc */
	/* TODO: look at push/pop for nr in leftop_tmp as option when need result - esp on C02 */
	case T_PLUSPLUS:
		/* The right side here is always constant */
		if (s == 2) {
			if (v == 1) {
				gen_internal("plusplus1");
				return 1;
			}
			if (v == 2) {
				gen_internal("plusplus2");
				return 2;
			}
			if (v == 4) {
				gen_internal("plusplus4");
				return 4;
			}
		}
		if (s <= 2 && !optsize) {
			/* XA is the pointer */
			/* Might want a tighter helper for -Os TODO */
			store_xa_tmp();
			load_y(0);
			output("clc");
			output("lda (@tmp),y");
			invalidate_a();
			if (nr)
				output("pha");
			output("adc #%u", v & 0xFF);
			output("sta (@tmp),y");
			if (s == 2) {
				load_y(1);
				output("lda (@tmp),y");
				if (nr)
					tax();
				output("adc #%u", (v >> 8) & 0xFF);
			}
			if (nr)
				output("pla");
			return 1;
		}
		return pri_help(n, "plusplustmp");
	case T_MINUSMINUS:
		/* The right side here is always constant */
#if 0
		if (s == 2) {
			if (v == 1) {
				gen_internal("minusminus1");
				return 1;
			}
			if (v == 2) {
				gen_internal("minusminus2");
				return 1;
			}
			if (v == 4) {
				gen_internal("minusminus4");
				return 1;
			}
		}
#endif
		/* TODO: make at least byte handling smarter */
		return pri_help(n, "minusmtmp");
	case T_PLUSEQ:
		if (s == 2 && r->op == T_CONSTANT) {
			if (v == 1) {
				gen_internal("pluseq1");
				return 1;
			}
			if (v == 2) {
				gen_internal("pluseq2");
				return 1;
			}
			if (v == 4) {
				gen_internal("pluseq4");
				return 1;
			}
			if (v < 256) {
				load_y(v);
				gen_internal("pluseqy");
				return 1;
			}
		}
		return pri_help(n, "pluseqtmp");
	case T_MINUSEQ:
		return pri_help(n, "minuseqtmp");
	case T_ANDEQ:
		return pri_help(n, "andeqtmp");
	case T_OREQ:
		return pri_help(n, "oraeqtmp");
	case T_HATEQ:
		return pri_help(n, "eoreqtmp");
#if 0
	/* still to do - more complex see 65C816 */
	case T_ARGCOMMA:
		/* We generate these directly when we can to optimize the
		   call return overhead a bit but it has to be done by
		   the peepholer */
		if (s == 1)
			output("jsr __pushc");
		else if (s == 2)
			output("jsr __push");
		else
			output("jsr __pushl");
		set_reg(R_Y, 0);
		sp += s;
		return 1;
#endif
	}
	/* TODO: yop other common ops */
	return 0;
}

/*
 *	Allow the code generator to shortcut the generation of the argument
 *	of a single argument operator (for example to shortcut constant cases
 *	or simple name loads that can be done better directly)
 */
unsigned gen_uni_direct(struct node *n)
{
	return 0;
}

/*
 *	Allow the code generator to shortcut trees it knows
 */
unsigned gen_shortcut(struct node *n)
{
	struct node *l = n->left;
	struct node *r = n->right;
	unsigned nr = n->flags & NORETURN;
	unsigned v;

	/* Unreachable code we can shortcut into nothing whee.bye.. */
	if (unreachable)
		return 1;

	/* The comma operator discards the result of the left side, then
	   evaluates the right. Avoid pushing/popping and generating stuff
	   that is surplus */
	if (n->op == T_COMMA) {
		l->flags |= NORETURN;
		codegen_lr(l);
		/* Parent determines child node requirements */
		r->flags |= nr;
		codegen_lr(r);
		return 1;
	}
	switch(n->op) {
	case T_PLUSPLUS:
		/* The left nay be a complex expression but also may be soemthing
		   we can directly reference. The right is the amount */
		if (leftop_memc(n, "inc"))
			return 1;
		break;
	case T_MINUSMINUS:
		if (leftop_memc(n, "dec"))
			return 1;
		break;
	case T_PLUSEQ:
		if (leftop_memc(n, "inc"))
			return 1;
		break;
	case T_MINUSEQ:
		if (leftop_memc(n, "dec"))
			return 1;
		break;
	/* TODO: look at rewriting LSTORE (CONSTANT 0) here as a pair of byte ops ? */
	case T_LSTORE:
		v = r->value;
		/* TODO works for any pair of identical bytes */
		if (nr && r->op == T_CONSTANT && get_size(n->type) == 2 && v == 0 && n->value < 256) {
			v &= 0xFF;
			load_a(v);
			if (reg[R_Y].state == T_CONSTANT) {
				if (reg[R_Y].value == n->value || reg[R_Y].value == v) {
					load_y(n->value);
					output("sta (@sp),y");
					load_y(n->value + 1);
				} else {
					load_y(n->value + 1);
					output("sta (@sp),y");
					load_y(n->value);
				}
				output("sta (@sp),y");
				return 1;
			}
		}
		break;
	}
	return 0;
}

static void char_to_int(void)
{
	load_x(0);
	output("ora #0");
	output("bpl X%u", ++xlabel);
	output("dex");
	label("X%u", xlabel);
	invalidate_x();
}

static unsigned gen_cast(struct node *n)
{
	unsigned lt = n->type;
	unsigned rt = n->right->type;
	unsigned ls;
	unsigned rs;

	if (PTR(rt))
		rt = USHORT;
	if (PTR(lt))
		lt = USHORT;

	/* Floats and stuff handled by helper */
	if (!IS_INTARITH(lt) || !IS_INTARITH(rt))
		return 0;

	/* No type casting needed as computing byte sized */
	if (n->flags & BYTEOP)
		return 1;

	ls = get_size(lt);

	/* Size shrink is free */
	if ((lt & ~UNSIGNED) <= (rt & ~UNSIGNED))
		return 1;
	if (!(rt & UNSIGNED)) {
		/* Signed */
		if (ls == 2) {
			char_to_int();
			return 1;
		}
		return 0;
	}
	if (ls == 4) {
		rs = get_size(rt);
		if (rs == 1) {
			load_x(0);
			output("stx @hireg");
			output("stx @hireg+1");
			return 1;
		} else {
			if (cpu == NMOS_6502) {
				load_y(0);
				output("sty @hireg");
				output("sty @hireg+1");
			} else {
				output("stz @hireg");
				output("stz @hireg+1");
			}
			return 1;
		}
	}
	if (ls == 2) {
		load_x(0);
		return 1;
	}
	return 0;
}

static unsigned bop_help_c(struct node *n, const char *op, const char *preop)
{
	unsigned size = get_size(n->type);
	unsigned nr = n->flags & NORETURN;
	unsigned is_byte = (n->flags & (BYTETAIL | BYTEOP)) == (BYTETAIL | BYTEOP);

	/* Result unused, don't bother */
	if (nr)
		return 1;
	/* We should look at inlining size 2 on -O2 TODO */
	if (!is_byte && size > 1)
		return 0;
	output("jsr __poptmpc");
	invalidate_tmp();
	set_reg(R_Y, 0);
	if (preop)
		output(preop);
	output("%s @tmp", op);
	invalidate_a();
	return 1;
}

/* (TOS) op A for 1 byte cases - again short and inlined. Could make -Os
   uninline this but marginal */
static unsigned bop_help_eq_c(struct node *n, const char *op, const char *preop)
{
	unsigned size = get_size(n->type);
	unsigned is_byte = (n->flags & (BYTETAIL | BYTEOP)) == (BYTETAIL | BYTEOP);

	/* We should look at inlining size 2 on -O2 TODO */
	if (!is_byte && size > 1)
		return 0;
	output("jsr __poptmp");	/* A preserved Y 0 @tmp is ptr */
	invalidate_tmp();
	set_reg(R_Y, 0);
	if (preop)
		output(preop);
	output("%s (@tmp),y", op);
	output("sta (@tmp),y");
	invalidate_a();
	return 1;
}

static unsigned bop_help(struct node *n, const char *op)
{
	return bop_help_c(n, op, NULL);
}

static unsigned bop_help_eq(struct node *n, const char *op)
{
	return bop_help_eq_c(n, op, NULL);
}

unsigned gen_node(struct node *n)
{
	struct node *r = n->right;
	unsigned size = get_size(n->type);
	unsigned v;
	unsigned nr = n->flags & NORETURN;
	unsigned se = n->flags & SIDEEFFECT;
	unsigned is_byte = (n->flags & (BYTETAIL | BYTEOP)) == (BYTETAIL | BYTEOP);

	v = n->value;

	/* Function call arguments are special - they are removed by the
	   act of call/return and reported via T_CLEANUP */
	if (n->left && n->op != T_ARGCOMMA && n->op != T_FUNCCALL && n->op != T_CALLNAME)
		sp -= get_stack_size(n->left->type);
	switch(n->op) {
	/* FIXME: need to do 4 byte forms */
	case T_LREF:
		if (nr && !se)
			return 1;
		if (is_byte && !se)
			size = 1;
		if (size == 1 && v + sp == 0) {
			if (a_contains(n))
				return 1;
			/* Same length as simple load via Y but
			   sets X to 0 so avoids the casting cost */
			if (cpu != NMOS_6502)
				output("lda (@sp)");
			else {
				load_x(0);
				output("lda (@sp,x)");
			}
			return 1;
		}
		if (optsize) {
			if (size == 2 && v + sp < 255) {
				if (n == 0)
					output("jsr __gloy0");
				else {
					load_y(v + sp + 1);
					output("jsr __gloy");
				}
				const_y_set(v + sp);
				invalidate_a();
				invalidate_x();
				return 1;
			}
			if (size == 4 && v + sp < 253) {
				if (n == 0)
					output("jsr __gloy0l");
				else {
					load_y(v + sp + 3);
					output("jsr __gloyl");
				}
				const_y_set(v + sp);
				invalidate_a();
				invalidate_x();
				return 1;
			}
		}
		/* Fall through */
	case T_NREF:
	case T_LBREF:
		if (nr && !se)
			return 1;
		if (is_byte && !se)
			size = 1;
		if (size == 1) {
			if (a_contains(n))
				return 1;
			if (pri8(n, "lda")) {
				set_a_node(n);
				return 1;
			}
		} else if (size == 2) {
			if (xa_contains(n))
				return 1;
			if (pri16(n, "ld")) {
				set_xa_node(n);
				return 1;
			}
		}
		/* FIXME: need to do 4 byte forms ?? */
		return 0;
	case T_LSTORE:
		v += sp;
		if (optsize && size == 2 && v < 254) {
			if (v <= 4)
				output("jsr __lstxa%u", v);
			else {
				load_y(v);
				output("jsr __lstxay");
			}
			set_xa_node(n);
			/* Y is incremented in the helper */
			set_reg(R_Y, v + 1);
			return 1;
		}
	case T_NSTORE:
	case T_LBSTORE:
		if (size == 1 && pri8(n, "sta")) {
			set_a_node(n);
			return 1;
		} else if (size == 2) {
			/* Only LSTORE destroys A */
			/* It seems marginal whether using this path for
			   LSTORE nr = 1 is worth it */
			if (n->op != T_LSTORE) {
				if (pri16(n, "st"))
					return 1;
			} else {
				/* Stack and restore A */
				if (do_pri16(n, r, "st", pre_pha)) {
					output("pla");
					set_xa_node(n);
					return 1;
				}
			}
		}
		/* FIXME: need to do 4byte forms **/
		return 0;
	case T_CALLNAME:
		invalidate_regs();
		output("jsr _%s+%u", namestr(n->snum), n->value);
		return 1;
	case T_EQ:
		/* store XA in top of stack addr  .. ugly */
		if (size > 2)
			return 0;
		if (size == 2 && optsize) {
			gen_internal("poptmpstxa");
			const_y_set(1);
			invalidate_mem();
			return 1;
		}
		/* Maybe make this whole lot a pair of helpers ? */
		gen_internal("poptmp");
		const_y_set(0);	/* Will always be set to 0 by helper */
		output("sta (@tmp),y");
		if (size == 2) {
			load_y(1);
			if (!nr) {
				saved_a();
				output("pha");
			}
			txa();
			output("sta (@tmp),y");
			if (!nr) {
				restored_a();
				output("pla");
			}
		}
		invalidate_mem();
		return 1;
	case T_FUNCCALL:
		/* For now just helper it */
		return 0;
	case T_DEREF:
		if (size == 4)
			return 0;
	case T_DEREFPLUS:
		if (nr && !se)
			return 1;
		/* If BYTEOP is set then non volatiles can be done
		   byte sized */
		if (!se && is_byte)
			size = 1;
		/* We could optimize the tracing a bit here. A deref
		   of memory where we know XA is a name, local etc is
		   one where we can update the contents info TODO */
		if (size > 2)
			error("drl");
		/* TODO: once xa tracking is more useful we should
		   spot the xa good case and shortcut it even in optsize */
		if (optsize) {
			if (size == 1) {
				if (v == 0) {
					output("jsr __derefc");
					set_reg(R_Y, 0);
				} else {
					load_y(v);
					output("jsr __derefcy");
				}
				invalidate_tmp();
				set_reg(R_X, 0);
				invalidate_a();
				return 1;
			}
			if (v == 0)
				return 0;
			load_y(v + 1);
			output("jsr __derefy");
			set_reg(R_Y, v);
			invalidate_x();
			invalidate_a();
			invalidate_tmp();
			return 1;
		}
		store_xa_tmp();
		if (size == 1 && v == 0) {
			if (cpu != NMOS_6502)
				output("lda (@tmp)");
			else {
				load_x(0);
				output ("lda (@tmp,x)");
			}
			invalidate_a();
		} else {
			load_y(v + 1);
			invalidate_a();
			output("lda (@tmp),y");
			tax();
			load_y(v);
			output("lda (@tmp),y");
			invalidate_a();
		}
		return 1;
	case T_LDEREF:
		v += sp;
		/* Hairy if the offset of the local is > 254 but this
		   is rare */
		if (v > 254) {
			/* This one is safe */
			load_x(n->val2 + 1);
			load_a(v);
			load_y(v >> 8);
			if (size == 1) {
				output("jsr __lderefcya");
				set_reg(R_X, 0);
			} else {
				output("jsr __lderefya");
				invalidate_x();
			}
			invalidate_a();
			invalidate_y();
		}
		/* offset of local */
		if (size == 2) {
			load_x(n->val2 + 1);
			if (v) {
				load_y(v);
				output("jsr __lderef");
			} else
				output("jsr __lderef0");
			invalidate_x();
		} else {
			load_x(n->val2);
			if (v) {
				load_y(v);
				output("jsr __lderefc");
			} else
				output("jsr __lderefc0");
			set_reg(R_X, 0);
		}
		invalidate_a();
		invalidate_y();
		invalidate_tmp();
		return 1;
	case T_CONSTANT:
		/* Only load the bits needed if we are constant */
		if (is_byte)
			size = 1;
		if (size > 2) {
			load_a(n->value >> 24);
			output("sta @hireg+1");
			load_a(n->value >> 16);
			output("sta @hireg");
		}
		/* We have to special case this to get the value setting right */
		if (size > 1)
			load_x(v >> 8);
		load_a(v & 0xFF);
		return 1;
	case T_NAME:
	case T_LABEL:
		if (is_byte)
			size = 1;
		if (size == 1 && pri8(n, "lda")) {
			invalidate_a();
			return 1;
		}
		if (size == 2 && pri16(n, "ld")) {
			invalidate_x();
			invalidate_a();
			return 1;
		}
		return 0;
	case T_ARGUMENT:
		v += argbase + frame_len;
	case T_LOCAL:
		v += sp;
		if (v < 256) {
			if (v == 0) {
				output("lda @sp");
				output("ldx @sp+1");
			} else {
				load_a(v);
				output("jsr __asp");
			}
		} else {
			load_y(v >> 8);
			load_a(v);
			output("jsr __yasp");
		}
		set_xa_node(n);
		return 1;
	/* Local and argument are more complex so helper them */
	case T_CAST:
		return gen_cast(n);
	/* TODO: CCONLY */
	case T_BANG:
		n->flags |= ISBOOL;
		/* For bool ops we need to add flag tracking and flipping */
		if (r->flags & ISBOOL) {
			output("eor #1");
			invalidate_a();
		} else
			helper(n, "not");
		return 1;
	case T_BOOL:
		if (r->flags & ISBOOL)
			return 1;
		n->flags |= ISBOOL;
		if (size == 1 || (n->flags & BYTEABLE)) {
			tax();	/* Set the Z flag */
			output("beq X%u", ++xlabel);
			load_a(1);
			label("X%u", xlabel);
		} else {
			helper(n, "bool");
		}
		return 1;
	case T_AND:
		return bop_help(n, "and");
	case T_OR:
		return bop_help(n, "ora");
	case T_HAT:
		return bop_help(n, "eor");
	case T_PLUS:
		return bop_help_c(n, "adc", "clc");
	case T_ANDEQ:
		return bop_help_eq(n, "and");
	case T_OREQ:
		return bop_help_eq(n, "ora");
	case T_HATEQ:
		return bop_help_eq(n, "eor");
	case T_PLUSEQ:
		return bop_help_eq_c(n, "adc", "clc");
	/* These may have been turned byte sized so we need to handle that
	   aspect ourself */
	case T_BANGEQ:
		helper_sb(n, "ccne");
		return 1;
	case T_EQEQ:
		helper_sb(n, "cceq");
		return 1;
	}
	return 0;
}
