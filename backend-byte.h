/*
 *	Options for byte mode. Uses the first five of the user flag bits
 */

#define BYTEABLE	0x0100		/* Candidate for size reduction */
#define BYTEOP		0x0200		/* Do size reduced */
#define BYTEROOT	0x0400		/* Start of a reduced section */
#define BYTETAIL	0x0800		/* End of a reduced section */
#define BYTECAST	0x1000		/* Operation was done as word and implicitly assumed byte */

extern void byte_label_tree(struct node *n, unsigned flags);

#define BTF_RELABEL	0x0001		/* Relabel sizes where possible */

