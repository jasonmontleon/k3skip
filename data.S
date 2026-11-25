/* The data pages the window uses.  Everything in them is zero.
 *
 * F1 (window.S) is handed a pointer to OBJECT.  It loads 8 bytes from it and makes fourteen stores into it; what the object
 * contains does not matter.  Addresses are the ones these things had in the original process. */

	.section .data2_object, "aw"		/* page 0x3feb849000 */
	.org 0x9c0
OBJECT:						/* 0x3feb8499c0 */
	.quad	0

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
