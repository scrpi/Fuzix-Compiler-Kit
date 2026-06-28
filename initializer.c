#include "compiler.h"

/* Forward declaration: the offset-threaded internal entry (the recursion target). */
static void init_at(struct symbol *sym, unsigned type, unsigned storage, unsigned off);

/*
 *	An automatic (stack) aggregate is initialized IN PLACE: each scalar
 *	element becomes an assignment statement to the element at its byte
 *	offset, *(type *)((char *)&sym + off) = value. make_symbol() gives the
 *	object lvalue and target_struct_ref() re-bases it to the element, exactly
 *	as a struct member reference does. C requires a partial aggregate
 *	initializer to zero the rest of the object, so unwritten bytes are filled
 *	with the same store mechanism. Static/global objects still go out as a
 *	typed data stream (the `off` is then unused).
 */
static void auto_store(struct symbol *sym, unsigned type, unsigned off, struct node *val)
{
    register struct node *n = target_struct_ref(make_symbol(sym), type, off);
    n = tree(T_EQ, n, val);
    /* We don't re-use the result of the assign so shortcuts are ok */
    n->flags |= NORETURN | SIDEEFFECT;
    write_tree(n);
}

/* Fill `bytes` bytes at `off`: static -> padding data; auto -> zero stores. */
static void ini_pad(struct symbol *sym, unsigned storage, unsigned off, unsigned bytes)
{
    if (storage == S_AUTO || storage == S_REGISTER) {
        while (bytes--)
            auto_store(sym, CCHAR, off++, make_constant(0, CCHAR));
    } else
        put_padding_data(bytes);
}

/*
 *	Write a single initialization element. For auto variables we generate the
 *	assignment tree (to the element at byte offset `off`); for static/globals
 *	we generate a stream of typed data for the backend.
 */
static void ini_single(struct symbol *sym, unsigned type, unsigned storage, unsigned off)
{
    register struct node *n = expression_tree(0);
    n = typeconv(n, type, 1);
    if (storage == S_AUTO || storage == S_REGISTER)
        auto_store(sym, type, off, n);
    else {
        put_typed_data(n);
        free_tree(n);
    }
}

/* C99 permits trailing comma and ellipsis */
/* Strictly {} is not permitted - there must be at least one value */

static unsigned ini_string(struct symbol *sym, unsigned n, unsigned storage, unsigned off)
{
    if (storage == S_AUTO || storage == S_REGISTER) {
        /* char x[N] = "..." on the stack: stash the bytes as a hidden static
           string (which keeps the 0xFF-quoted encoding correct and consumes the
           token) and copy them into the array element by element. `cnt` is the
           whole array for a sized one, else the string + its NUL. */
        unsigned lbl = ++label_tag;
        unsigned len = copy_string(lbl, n ? n : TARGET_MAX_PTR, n ? 1 : 0, 0);
        unsigned cnt = n ? n : len + 1;
        unsigned i;
        for (i = 0; i < cnt; i++) {
            register struct node *s = target_struct_ref(make_label(lbl), CCHAR, i);
            s->flags |= LVAL;
            auto_store(sym, CCHAR, off + i, make_rval(s));
        }
        return n ? n : len;
    }
    /* This one is weird because the string is not literal */
    if (n)
        n = copy_string(0, n, 1, 0);
    else
        n = copy_string(0, TARGET_MAX_PTR, 0, 0);
    return n;
}

/*
 *	Array bottom level initializer: repeated runs of the same type
 *
 *	TODO: In theory we could have a platform that needs padding
 *	and we don't deal with that aspect of alignment yet
 */
static unsigned ini_group(struct symbol *sym, unsigned type, register unsigned n, unsigned storage, unsigned off)
{
    unsigned sized = n;
    unsigned string = 0;
    register unsigned count = 0;
    unsigned esize = type_sizeof(type);
    /* C has a funky special case rule that you can write
       char x[16] = "foo"; which creates a copy of the string in that
       array not a literal reference. It's also got a second funky special case
       rule that you can write { "string" }. */

    if ((type_canonical(type) & ~UNSIGNED) == CCHAR)
        string = 1;

    if (token == T_STRING) {
        if (!string)
            typemismatch();
        return ini_string(sym, n, storage, off);
    }
    require(T_LCURLY);
    if (!sized)
        n = TARGET_MAX_PTR;
    while(n && token != T_RCURLY) {
        /* Deal with the second string special case, gotta love C some days */
        if (token == T_STRING && string) {
            n = ini_string(sym, sized, storage, off);
            require(T_RCURLY);
            return n;
        }
        string = 0;	/* Only valid first */
        if (token == T_ELLIPSIS)
            break;
        n--;
        init_at(sym, type, storage, off + count * esize);
        count++;
        if (!match(T_COMMA))
            break;
    }
    if (n && sized)
        ini_pad(sym, storage, off + count * esize, esize * n);
    /* Catches any excess elements */
    require(T_RCURLY);
    return count;
}

/*
 *	Struct and union initializer
 *
 *	This is similar to an array but each element has its own expected
 *	type, and some elements may themselves be structures or arrays. It's
 *	mostly recursion.
 *
 *	Remaining space in the object is padded.
 *
 *	We don't deal with auto here as with arrays because we don't support
 *	the C extensions of auto array and struct with initializers.
 */
static void ini_struct(struct symbol *psym, unsigned type, unsigned storage, unsigned off)
{
    struct symbol *sym = symbol_ref(type);
    register unsigned *p = sym->data.idx;
    register unsigned n = *p;
    unsigned s = p[1];	/* Size of object (needed for union) */
    unsigned pos = 0;

    p += 2;
    /* We only initialize the first object */
    if (S_STORAGE(sym->infonext) == S_UNION)
        n = 1;
    require(T_LCURLY);
    while(n-- && token != T_RCURLY) {
        /* Name, type, offset tuples */
        type = p[1];

        /* Align */
        if (pos != p[2]) {
            ini_pad(psym, storage, off + pos, p[2] - pos);
            pos = p[2];
        }
        /* Write out field at its byte offset within the object */
        init_at(psym, type, storage, off + pos);
        pos += type_sizeof(type);

        /* Next field */
        p += 3;

        if (!match(T_COMMA))
            break;
    }
    if (n == -1 && token != T_RCURLY)
        error("too many initializers");
    require(T_RCURLY);
    /* For a union zerofill the slack if other elements are bigger */
    /* For a struct fill from the offset of the next field to the size of
       the base object */
    if (pos != s)
        ini_pad(psym, storage, off + pos, s - pos);	/* Fill remaining space */
}

/*
 *	Array initializer.
 *
 *	We recursively call down through the layers until we hit the bottom
 *	layer of the array which should be a series of values in the type
 *	of the array. The base value may be a structure.
 */
static void ini_array(struct symbol *sym, unsigned type, unsigned depth, unsigned storage, unsigned off)
{
    unsigned n = array_dimension(type, depth);
    unsigned count = 0;

    if (depth < array_num_dimensions(type)) {
        unsigned esize;
        type = type_deref(type);
        esize = type_sizeof(type);	/* size of one sub-array */
        require(T_LCURLY);
        if (n == 0)
            n = TARGET_MAX_PTR;
        while(n--) {
            ini_array(sym, type, depth + 1, storage, off + count * esize);
            count++;
            /* Trailing comma is allowed so eat it before checking n */
            if (match(T_COMMA) && n)
                continue;
            break;
        }
        if (array_dimension(type, 1) == 0)
            sym->type = array_with_size(type, count);
        /* Pad the remaining pieces */
        while(n--) {
            ini_pad(sym, storage, off + count * esize, esize);
            count++;
        }
        require(T_RCURLY);
    } else {
        n = ini_group(sym, type_deref(type), n, storage, off);
        if (array_dimension(type, 1) == 0)
            sym->type = array_with_size(type, n);
    }
}

/*
 *	Initialize an object at byte offset `off` within it. Automatic (stack)
 *	aggregates now lower to per-element assignment statements (auto_store) with
 *	the unwritten remainder zero-filled, instead of being rejected.
 */
static void init_at(struct symbol *sym, register unsigned type, register unsigned storage, unsigned off)
{
    if (PTR(type) && !IS_ARRAY(type)) {
        ini_single(sym, type, storage, off);
        return;
    }
    if (IS_ARITH(type)) {
        ini_single(sym, type, storage, off);
        return;
    }
    if (storage == S_EXTERN) {
        error("cannot initialize external");
        return;
    }
    if (IS_FUNCTION(type))
        error("init function");	/* Shouldn't get here, we don't use "=" for
                                   function forms even if it would be more
                                   logical than the C syntax */
    else if (IS_ARRAY(type)) {
        /* A size-from-initializer array can't be an automatic: its storage is
           assigned before the initializer is seen, so the frame slot would be
           mis-sized. Reject it rather than silently corrupt the stack. */
        if ((storage == S_AUTO || storage == S_REGISTER)
            && array_dimension(type, 1) == 0) {
            error("automatic array of unknown size - give an explicit dimension");
            return;
        }
        ini_array(sym, type, 1, storage, off);
    }
    else if (IS_STRUCT(type))
        ini_struct(sym, type, storage, off);
    else
        error("cannot initialize this type");
}

/*
 *	Initialize an object. Static/global objects emit a typed data stream;
 *	automatic objects emit assignment statements (see init_at / auto_store).
 */
void initializers(struct symbol *sym, unsigned type, unsigned storage)
{
    init_at(sym, type, storage, 0);
}
