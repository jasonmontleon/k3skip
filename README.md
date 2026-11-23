# k3skip

A small program that gives wrong results on the SpacemiT K3 (X100 cores): now and then one instruction of a
straight-line sequence does not take effect.

The program contains only rv64gc instructions plus one cache-flush instruction (`cbo.flush`, Zicbom extension), so it
can be run unchanged on other RISC-V boards for comparison.

The fault was first met as hart lock-ups while building Rust with an RVA23 toolchain
(see [k3bump2](https://github.com/jasonmontleon/k3bump2)). The code here is cut down from the same place in `rustc`.
RVA23 instructions turned out not to be needed.

## Run

```
./k3skip -t 600            six workers, pinned to harts 0,1,3,4,5,6, for 600 seconds
./k3skip -c 3 -t 600       one worker, pinned to hart 3
./k3skip -t 600 mapped     control: the same, with one more page mapped
```

`-t` defaults to 60. `-c` takes a comma-separated list of harts.

Each worker prints a progress line every second, the first twelve wrong results in full, and one summary line at the end:

```
k3skip: cpu 3: WRONG RESULT in pass 81530241: eight instructions each set one bit, expected 0xff, got 0xfe (missing bits 0x1)
k3skip: cpu 3 SUMMARY: 498002304 passes, 0 traps, 7 wrong results
```

A working system prints `0 traps, 0 wrong results` for every worker.

If the system does not allow user programs to execute `cbo.flush`, the program says so and exits with status 3.

**Warning:** on a K3 the same fault can also lock a hart completely (see "One fault, several forms"). This build has not
done so in our runs, but do not run it on a K3 you cannot power-cycle.

## Results

Six workers unless noted. "Vendor" is the SpacemiT 6.18 kernel; "mainline" is a 7.3 kernel with board patches.

| Board | Kernel | Run | Passes | Wrong results |
|---|---|---|---|---|
| K3 CoM260 | vendor 6.18 | 30 s | 226 million | 905 |
| K3 CoM260 | vendor 6.18 | 30 s | 244 million | 1,175 |
| K3 CoM260 | vendor 6.18 | 30 s, one worker | 50 million | 90 |
| K3 CoM260 | vendor 6.18 | 30 s, `mapped` | 243 million | 0 |
| K3 CoM260 | mainline 7.3 | 120 s | 964 million | 46 |
| K3 CoM260 | mainline 7.3 | 120 s | 1,007 million | 12 |
| K3 CoM260 | mainline 7.3 | 120 s, one worker | 203 million | 15 |
| K3 CoM260 | mainline 7.3 | 120 s, `mapped` | 979 million | 0 |
| K3 Pico-ITX | mainline 7.3 | 600 s | 4,532 million | 149 |
| Milk-V Titan (not a K3) | mainline 7.3 | 600 s | 865 million | 0 |

No run produced a trap. On the K3 the missing bit is nearly always the 1st, 4th, 5th or 8th.

The rate varies a lot between runs, between harts (on the Pico-ITX run: 123, 3, 14, 1, 1 and 7 on harts 0, 1, 3, 4, 5
and 6) and between kernels, so a short clean run on a K3 proves nothing; run for several minutes.

## What the program does

`k3skip.c` maps a few pages of code and data at fixed addresses and then repeats one "pass" as fast as it can. The pass
is in `window.S`. It is a path of about 150 instructions, cut out of `rustc` and kept at its original addresses:

1. `part1`: call an empty function, call `F1`, call a second empty function.
2. `part2`: a few branches, some taken and some never taken.
3. `part3`: flush one cache line of the stack, call the empty function, call `F1` a second time, six 2-byte no-ops,
   then a far call (`auipc` + `jalr`) to `far_target`, which jumps to `exit_stub`.
4. `exit_stub`: the check.

```
exit_stub:
	ori t4, t4, 0x1
	ori t4, t4, 0x2
	ori t4, t4, 0x4
	ori t4, t4, 0x8
	ori t4, t4, 0x10
	ori t4, t4, 0x20
	ori t4, t4, 0x40
	ori t4, t4, 0x80
	sd  t4, 0x118(gp)
	ld  t0, 0x110(gp)
	jalr zero, 0x0(t0)
```

`t4` is zero when the pass starts. Eight instructions in a row each set one bit. There is no branch among them, so the
value stored must be `0xff`. The driver checks that after every pass.

`F1` is a real function from `rustc` (about 95 instructions: it saves registers, copies some fields of an object, and
returns). `data.S` holds the object it works on.

One more page matters although it is never executed: the page at `0x3ff5a1f000` is filled with no-ops and ends in the
first half of a 4-byte conditional branch. The page after it, `0x3ff5a20000`, is not mapped. The second call of `part1`
goes through a stub at `0x3ff301ffe0`, and the core's first guess for that stub's indirect jump lands in this page (our
reading of the addresses; the guess itself cannot be observed).

With the argument `mapped`, the page `0x3ff5a20000` is mapped as well (all zeros). Nothing else changes, and the wrong
results disappear.

## What goes wrong

On a K3 the stored value occasionally has one bit missing: one of the eight `ori` instructions did not take effect.

We recorded five such events with the K3's on-chip instruction trace (earlier variants of this program, vendor kernel
6.18). In all five:

- a timer interrupt was taken within a few instructions after the last far call of the pass;
- the return address the core gave the kernel (`sepc`) was wrong. In four cases it was the address of the interrupted
  instruction plus 4; in one it was 8 bytes behind a jump that had already been taken;
- the kernel returned to that address, so the program went on one instruction too late.

The kernel does nothing unusual in these traces. The skipped instruction is the one at the point of interruption.

## One fault, several forms

The number of 2-byte no-ops in front of the last far call (`NOPS2 6` in `part3`) selects what is seen:

| No-ops | Seen |
|---|---|
| 2 or 4 | the hart locks: it stops executing, takes no interrupts, and does not respond to a debugger halt request |
| 3 or 6 | wrong results (a skipped instruction) |
| 0, 1, 5 or 8 | traps at addresses just behind the far call, and wrong results |

These counts were measured with the RVA23 form of `F1` (the original, which copies with vector instructions). In this
repository each of those five vector instructions is replaced by one floating-point load or store, and six no-ops give
wrong results.

## What the pass needs

Each of these was removed or changed on its own, and the fault went away (six workers, both the lock-up and the
wrong-result form):

- the unmapped page behind the half branch;
- the taken branch at `start`;
- both calls of the empty function `helper1`, and the never-taken `c.bnez` behind each;
- both calls of `F1`, through the same stub, and the call of `stub_helper2` after the first;
- the never-taken `bne` in `part2`, and the taken `c.beqz` in `part3`;
- the `cbo.flush` of the stack line before the second call of `F1`.

Not needed: the thirteen no-ops in `part1`; any particular data values.

The addresses matter. The same instructions packed close together do not fail.

## Vendor registers

Two machine-mode registers change the behaviour. Their fields are not documented apart from one bit, so we cannot say
what these bits switch.

| Register | Firmware value | Change | Effect |
|---|---|---|---|
| `CSR_MVMD1` (0xBF9) | 0x2000000000 | set bit 3 (0x2000000008) | no events in about 950 million passes in three layouts; in the two layouts that otherwise lock, no lock-up, but 14 wrong results in 1.9 billion passes. About 4 % slower in this loop |
| `CSR_MSETUP` (0x7C0) | 0x10073 | clear bit 4 (0x10063) | no events seen; about 20 % slower in this loop |

Bit 37 of `CSR_MVMD1` (`IFU_FUSION_TYPE5_DIS`, the documented one) makes no difference either way.

## Build

Needs clang, lld, python3 and make on any machine:

```
make
```

`build-assets/mkpages.py` assembles `window.S` and `data.S` for their run addresses (`build-assets/layout.ld`) and packs
them as pages; the driver is compiled with those pages inside. Everything is assembled with `-march=rv64gc`; the flush
is written as `.4byte 0x0022200f`.

The result is one static binary with no dependencies.
