/*
 *	Compiler front-end (cc1) support for the BLIP target.
 *
 *	BLIP's C model matches the kit defaults: char 8, int/short 16, long 32,
 *	pointer 16, little-endian (isa.md §3); no alignment requirement (byte
 *	machine, isa.md §4). Byte arguments are passed as bytes.
 *
 *	Register variables are disabled for now (target_register returns 0). The
 *	§7 ABI reserves Y as the one callee-saved 16-bit register; handing it out
 *	as a register variable is a follow-up.
 */

#include "compiler.h"

unsigned target_ptr = UINT;

unsigned target_alignof(unsigned t, unsigned storage)
{
	return 1;
}

/* Size of primitive types for this target */
static unsigned sizetab[16] = {
	1, 2, 4, 8,		/* char, short, long, longlong */
	1, 2, 4, 8,		/* unsigned forms */
	4, 8, 0, 0,		/* float, double, void, unused.. */
	0, 0, 0, 0		/* unused */
};

unsigned target_sizeof(unsigned t)
{
	unsigned s;

	if (PTR(t))
		return 2;

	s = sizetab[(t >> 4) & 0x0F];
	if (s == 0) {
		error("cannot size type");
		s = 1;
	}
	return s;
}

/* BLIP can pass byte arguments as bytes (it has byte stack access) */
unsigned target_argsize(unsigned t)
{
	return target_sizeof(t);
}

unsigned target_ptr_arith(unsigned t)
{
	return CINT;
}

unsigned target_scale_ptr(unsigned t, unsigned scale)
{
	return scale;
}

/* Scale a pointer offset to byte size (byte-addressed machine) */
unsigned target_ptroff_to_byte(unsigned t)
{
	return 1;
}

struct node *target_struct_ref(struct node *n, unsigned type, unsigned off)
{
	n->type = PTRTO + type;
	n = tree(T_PLUS, n, make_constant(off, UINT));
	n->type = type;
	return n;
}

/* Can we remove pointer/int casts for fixed objects */
unsigned target_remove_cast(struct node *l, struct node *r)
{
	return 1;
}

/* Remap any base types for simplicity on the platform */
unsigned target_type_remap(unsigned type)
{
	/* Our double is float */
	if (type == DOUBLE)
		return FLOAT;
	return type;
}

/* Register variables are not yet handed out (see file header). */
unsigned target_register(unsigned type, unsigned storage)
{
	return 0;
}

void target_reginit(void)
{
}
