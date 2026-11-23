/* The data the window reads.  Everything else in these pages is zero.
 *
 * The window's one real function (F1 in window.S) is called twice per pass.  It is handed a pointer to OBJECT.  It reads a cursor from the object, looks up
 * the 32-byte array element the cursor selects, copies fields of that element and of the object around, and returns.
 * Addresses are the ones these things had in the original process. */

	.section .data2_object, "aw"		/* page 0x3feb849000 */
	.org 0x9c0
OBJECT:						/* 0x3feb8499c0 */
	.org 0x9c0 + 0x98
	.quad	TABLE				/* +0x98: pointer to the table header */
	.quad	16				/* +0xa0: cursor = index of the array element to use */
	.quad	0x00000bb400000000, 0, 0x0000000100026d8b	/* +0xa8 .. +0xb8: three words the function copies */
	.org 0x9c0 + 0x108
	.quad	0x29d9				/* +0x108: a counter */

	.section .data2_table, "aw"		/* page 0x3fdc2ee000 */
	.org 0xd90
TABLE:						/* 0x3fdc2eed90 */
	.org 0xd90 + 0x18
	.quad	ARRAY				/* +0x18: pointer to the array */
	.quad	0x69				/* +0x20: number of elements */

	.section .data2_array, "aw"		/* page 0x3fdc2ed000 */
	.org 0x500
ARRAY:						/* 0x3fdc2ed500; elements are 32 bytes */
	.org 0x500 + 16 * 32
	.quad	0x0000003800250100, 0x000000000000000b, 0x00026d8d00000000, 0x0000000000000005	/* element 16: the one both calls read */

	.section .data2_stack, "aw"		/* page 0x3feb846000: the stack; the window starts with sp = 0x3feb8465b0 */
	.org 0x5b0
STACK_TOP:
	.quad	0

/* The page in front of the unmapped page (0x3ff5a1f000).  It is never executed.  The core only fetches from it when it guesses
 * the target of one of the window's far calls wrong (see window.S), runs through the no-ops, and at the very end of the page
 * meets the first half of a 4-byte conditional branch whose second half would lie in the next page, which has no mapping. */
	.section .front, "ax"
	.rept	2047
	.2byte	0x0001			/* c.nop */
	.endr
	.2byte	0x4963			/* first half of `blt a2, s6, ...` (63 49 | xx xx); any conditional branch does it */
