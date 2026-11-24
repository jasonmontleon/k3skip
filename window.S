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
F1:
	c.addi16sp sp, -0xb0
	c.sdsp ra, 0xa8(sp)
	c.sdsp s0, 0xa0(sp)
	c.sdsp s1, 0x98(sp)
	c.sdsp s2, 0x90(sp)
	c.sdsp s3, 0x88(sp)
	c.sdsp s4, 0x80(sp)
	c.sdsp s5, 0x78(sp)
	c.sdsp s6, 0x70(sp)
	c.sdsp s7, 0x68(sp)
	c.sdsp s8, 0x60(sp)
	c.sdsp s9, 0x58(sp)
	c.sdsp s10, 0x50(sp)
	c.sdsp s11, 0x48(sp)
	c.mv s0, a0
	c.li s7, 0x1
	W addi s3, a0, 0x98
	c.li s8, 0x3
	c.li s9, -0x1
	c.ld a0, 0x98(s0)
	c.ld a1, 0xa0(s0)
	c.ld a2, 0x20(a0)
	W bgeu a1, a2, .+134
	c.ld a0, 0x18(a0)
	W slli a2, a1, 0x5
	c.add a0, a2
	W lbu a2, 0x0(a0)
	W beq a2, zero, L_2aae6d6

	.org 0x156		/* lib+0x2aae6d6 */
L_2aae6d6:
	c.lw a2, 0xc(a0)
	W lwu a3, 0x8(a0)
	c.lw a4, 0x10(a0)
	W lwu a5, 0x14(a0)
	c.slli a2, 0x20
	W lw a6, 0x18(a0)
	c.or a2, a3
	W lbu s4, 0x1(a0)
	W lbu s2, 0x4(a0)
	W lbu s6, 0x5(a0)
	W lhu s5, 0x6(a0)
	c.sdsp a2, 0x28(sp)
	c.swsp a4, 0x30(sp)
	c.slli a6, 0x20
	NOPS2 1
	W or s1, a6, a5
	c.sd a1, 0xa0(s0)
	W lw a0, 0x108(s0)
	W slli a1, s1, 0x10
	c.lui a2, 0x10
	NOPS2 1
	c.srli a1, 0x30
	c.addi a2, -0x1
	W sw a0, 0x108(s0)
	W sw zero, 0x10c(s0)
	W bne a1, a2, L_2aae770

	.org 0x1f0		/* lib+0x2aae770 */
L_2aae770:
	W slli a0, a1, 0x31
	W addiw a2, s1, 0x0
	c.srli a0, 0x31
	c.or a0, a2
	c.bnez a0, L_2aae794

	.org 0x214		/* lib+0x2aae794 */
L_2aae794:
	W addi a0, s0, 0xa8
	NOPS4 1
	W fld fa4, 0x0(a0)
	c.lwsp a0, 0x28(sp)
	c.addi4spn a1, sp, 0x2c
	W fld fa3, 0x0(a1)
	c.ld a1, 0xb8(s0)
	W sb s2, 0xa8(s0)
	W sb s6, 0xa9(s0)
	W sh s5, 0xaa(s0)
	W sw a0, 0xac(s0)
	W addi a0, s0, 0xb0
	W fsd fa3, 0x0(a0)
	W addi a0, s0, 0xc0
	c.sd s1, 0xb8(s0)
	c.sd a1, 0xd0(s0)
	W sb s4, 0x119(s0)
	W sd zero, 0x60(s0)
	W sd zero, 0x68(s0)
	W fsd fa4, 0x0(a0)
	c.ldsp ra, 0xa8(sp)
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
