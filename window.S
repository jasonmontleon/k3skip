/* k3skip: the code one pass executes, at the addresses it had in the original process (a rustc build).
 * Instructions are rv64gc plus one cbo.flush (Zicbom).  LIB = 0x3ff3000000; `lib+X` in the comments means LIB + X.
 * The pass: start -> part1 -> part2 -> part3 -> far_target -> exit_stub -> back to the driver. */
	.option norelax
	.macro W ops:vararg
	.option push
	.option norvc
	\ops
	.option pop
	.endm
	.macro NOPS4 n
	.rept \n
	.4byte 0x00000013
	.endr
	.endm
	.macro NOPS2 n
	.rept \n
	.2byte 0x0001
	.endr
	.endm
	.macro FARCALL reg, target
	.option push
	.option norvc
1:	auipc \reg, %pcrel_hi(\target)
	jalr \reg, %pcrel_lo(1b)(\reg)
	.option pop
	.endm
	.macro LOADGOT reg, slot
	.option push
	.option norvc
1:	auipc \reg, %pcrel_hi(\slot)
	ld \reg, %pcrel_lo(1b)(\reg)
	.option pop
	.endm


	.section .r_3ff2ee276e, "ax"
	c.jr ra				/* the driver jumps here with ra = start */

	.section .r_199b0, "ax"
stub_F1:				/* both calls of F1 go through this one stub */
	LOADGOT t3, GOT_4ea9718
	W jalr t1, 0x0(t3)

	.section .r_1ffe0, "ax"
stub_helper2:
	LOADGOT t3, GOT_4eaca30
	W jalr t1, 0x0(t3)

	.section .r_2a735b6, "ax"
helper2:
	c.jr ra

	.section .r_2a897b8, "ax"
far_target:
	W jal zero, exit_stub
	.org 0x1848		/* lib+0x2a8b000 */
exit_stub:				/* THE CHECK: eight instructions each set one bit of t4 (0 at the start of the pass) */
	W ori t4, t4, 0x1
	W ori t4, t4, 0x2
	W ori t4, t4, 0x4
	W ori t4, t4, 0x8
	W ori t4, t4, 0x10
	W ori t4, t4, 0x20
	W ori t4, t4, 0x40
	W ori t4, t4, 0x80

	.org 0x1868		/* lib+0x2a8b020 */
L_2a8b020:				/* store the result (must be 0xff) and go back to the driver */
	W sd t4, 0x118(gp)
	W ld t0, 0x110(gp)
	W jalr zero, 0x0(t0)


	.org 0x1b48		/* lib+0x2a8b300 */
part2:
	W addi s1, zero, 0x1
	W jal zero, part2a

	.org 0x1c24		/* lib+0x2a8b3dc */
part3:
	W addi s4, s2, 0x0
	W jal zero, part3b

	.section .r_2a940dc, "ax"
	.org 0x1a		/* lib+0x2a940f6 */
part3b:
	c.beqz s0, part3c		/* taken */
	.org 0x6a		/* lib+0x2a94146 */
part3c:
	.4byte 0x0022200f		/* cbo.flush (tp): push one line of F1's stack frame out of the cache */
	FARCALL ra, helper1		/* lib+0x2a9414a */
	c.bnez s0, .+46			/* never taken */
	c.mv a0, s4
	FARCALL ra, stub_F1		/* lib+0x2a94156: second call of F1 */
	NOPS2 9				/* the number of instructions here decides the form of the failure, see README */
	FARCALL ra, far_target		/* lib+0x2a94170: the last call; the skipped instruction is one of the next few executed */

	.section .r_2a9894c, "ax"
	.org 0x20		/* lib+0x2a9896c */
start:
	W beq zero, zero, part1		/* taken */
	.org 0x8e		/* lib+0x2a989da */
part1:
	FARCALL ra, helper1
	c.bnez s0, .+14			/* never taken */
	c.mv a0, s2
	FARCALL ra, stub_F1		/* lib+0x2a989e6: first call of F1 */
	NOPS2 8
	NOPS4 2
	NOPS2 1
	FARCALL ra, stub_helper2	/* lib+0x2a98a08: its wrong target guess is the page that ends in half a branch */
	W jal zero, part2

	.section .r_2aae580, "ax"
F1:					/* a0 = OBJECT.  Written by hand: what is left of a compiled function after everything that could
					   be removed was removed.  The no-ops keep each block at its original address. */
	c.addi16sp sp, -0xb0		/* 13 register saves */
	c.sdsp ra, 0xa8(sp)
	c.sdsp s0, 0xa0(sp)
	c.sdsp s1, 0x98(sp)
	c.sdsp s2, 0x90(sp)
	c.sdsp s3, 0x88(sp)
	c.sdsp s4, 0x80(sp)
	c.sdsp s5, 0x78(sp)		/* this one and the six below it go into the stack line that part 3 flushes */
	c.sdsp s6, 0x70(sp)
	c.sdsp s7, 0x68(sp)
	c.sdsp s8, 0x60(sp)
	c.sdsp s9, 0x58(sp)
	c.sdsp s10, 0x50(sp)
	c.sdsp s11, 0x48(sp)
	c.mv s0, a0
	NOPS2 1
	NOPS4 1
	NOPS2 5
	W bne zero, zero, .+134		/* never taken */
	NOPS2 1
	NOPS4 1
	NOPS2 1
	NOPS4 1
	W beq zero, zero, L_2aae6d6	/* taken */

	.org 0x156		/* lib+0x2aae6d6 */
L_2aae6d6:
	NOPS2 1
	NOPS4 1
	NOPS2 1
	NOPS4 1
	NOPS2 1
	NOPS4 1
	NOPS2 1
	NOPS4 4
	c.sdsp a2, 0x28(sp)		/* five stores: two to the stack, three into the object (what they store does not matter) */
	c.swsp a4, 0x30(sp)
	NOPS2 2
	NOPS4 1
	c.sd a1, 0xa0(s0)
	NOPS4 2
	NOPS2 4
	W sw a0, 0x108(s0)
	W sw zero, 0x10c(s0)
	W jal zero, L_2aae770

	.org 0x1f0		/* lib+0x2aae770 */
L_2aae770:
	NOPS4 2
	NOPS2 2
	c.j L_2aae794

	.org 0x214		/* lib+0x2aae794 */
L_2aae794:
	W addi a0, s0, 0xa8
	NOPS4 1
	W ld t5, 0x0(a0)		/* two loads: 8 bytes of the object ... */
	NOPS2 1
	c.addi4spn a1, sp, 0x2c
	W ld t6, 0x0(a1)		/* ... and 8 bytes of the stack, across the two stack stores above (misaligned) */
	NOPS2 1
	W sb s2, 0xa8(s0)		/* eleven stores into the object */
	W sb s6, 0xa9(s0)
	W sh s5, 0xaa(s0)
	W sw a0, 0xac(s0)
	W addi a0, s0, 0xb0
	W sd t6, 0x0(a0)
	W addi a0, s0, 0xc0
	c.sd s1, 0xb8(s0)
	c.sd a1, 0xd0(s0)
	W sb s4, 0x119(s0)
	W sd zero, 0x60(s0)
	W sd zero, 0x68(s0)
	W sd t5, 0x0(a0)
	c.ldsp ra, 0xa8(sp)		/* 13 register restores */
	c.ldsp s0, 0xa0(sp)
	c.ldsp s1, 0x98(sp)
	c.ldsp s2, 0x90(sp)
	c.ldsp s3, 0x88(sp)
	c.ldsp s4, 0x80(sp)
	c.ldsp s5, 0x78(sp)
	c.ldsp s6, 0x70(sp)
	c.ldsp s7, 0x68(sp)
	c.ldsp s8, 0x60(sp)
	c.ldsp s9, 0x58(sp)
	c.ldsp s10, 0x50(sp)
	c.ldsp s11, 0x48(sp)
	c.addi16sp sp, 0xb0
	c.jr ra

	.section .r_2adff46, "ax"
	.org 0x4		/* lib+0x2adff4a */
part2b:
	W addi a5, s1, 0x0
	NOPS4 1
	c.andi a5, 0x1
	c.srli s1, 0x1
	W bne a5, zero, part2c		/* taken, on the value just computed */
	.org 0x3c		/* lib+0x2adff82 */
part2c:
	W bne zero, zero, .+50		/* never taken */
	NOPS2 1
	W jal zero, part3
	.org 0xd8		/* lib+0x2ae001e */
part2a:
	W beq zero, zero, part2b		/* taken */

	.section .r_2aec63a, "ax"
helper1:
	c.jr ra

	.section .g_4ea9718, "a"
GOT_4ea9718:	.quad F1
	.section .g_4eaca30, "a"
GOT_4eaca30:	.quad helper2
