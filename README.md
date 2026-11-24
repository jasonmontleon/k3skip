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

Six workers for 120 s unless noted. "Vendor" is the SpacemiT 6.18 kernel under Fedora, "Bianbu" is SpacemiT's own
distribution with its kernel; the others are mainline kernels with board patches under Fedora. All on a K3 CoM260.

| Kernel | Run | Passes | Wrong results | Traps |
|---|---|---|---|---|
| 7.3.6 | six workers | 904 million | 558 | 0 |
| 7.3.6 | six workers | 905 million | 496 | 0 |
| 7.3.6 | one worker | 203 million | 1,254 | 0 |
| 7.3.6 | `mapped` | 1,005 million | 0 | 0 |
| 7.3.5 | six workers | 906 million | 574 | 10 |
| 7.3.5 | six workers | 906 million | 553 | 4 |
| 7.3.5 | one worker | 202 million | 257 | 12 |
| 7.3.5 | `mapped` | 1,029 million | 0 | 0 |
| 7.3.0 | six workers | 1,025 million | 582 | 589 |
| 7.3.0 | six workers | 1,006 million | 448 | 660 |
| 7.3.0 | one worker | 203 million | 415 | 1,002 |
| 7.3.0 | `mapped` | 979 million | 0 | 0 |
| vendor 6.18 | six workers, 60 s | 451 million | 229 | 224 |
| vendor 6.18 | six workers, 60 s | 453 million | 289 | 173 |
| vendor 6.18 | one worker, 60 s | 101 million | 207 | 471 |
| vendor 6.18 | `mapped`, 60 s | 496 million | 0 | 0 |
| Bianbu 6.18.3 | six workers, 60 s | 488 million | 67 | 2 |
| Bianbu 6.18.3 | six workers, 60 s | 491 million | 118 | 3 |
| Bianbu 6.18.3 | one worker, 60 s | 102 million | 124 | 1 |
| Bianbu 6.18.3 | `mapped`, 60 s | 490 million | 0 | 0 |

The missing bit is nearly always the 1st, 4th, 5th or 8th.

A "trap" is the same fault with a worse outcome: the skipped instruction was one whose absence makes the program jump
to a wrong place. The program catches the signal, reports it and goes on with the next pass.

**The rate depends on the kernel build.** An earlier version of this program (6 instead of 9 no-ops in front of the last
far call, see "One fault, several forms") gave about 2,000 wrong results a minute on the vendor kernel, 900 on 7.3.0, 6 on
7.3.5 and 0.1 on 7.3.6, on the same board. That version was also run on a K3 Pico-ITX (7.3.5, 600 s: 149 wrong results in
4,532 million passes) and on a Milk-V Titan, which is not a K3 (600 s: 0 in 865 million passes). So a clean run on a K3
proves little, and a kernel update that makes the wrong results disappear has not fixed anything.

## What the program does

`k3skip.c` maps a few pages of code and data at fixed addresses and then repeats one "pass" as fast as it can. The pass
is in `window.S`. It is a path of about 150 instructions, cut out of `rustc` and kept at its original addresses:

1. `part1`: call an empty function, call `F1`, call a second empty function.
2. `part2`: a few branches, some taken and some never taken.
3. `part3`: flush one cache line of the stack, call the empty function, call `F1` a second time, nine 2-byte no-ops,
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

The number of 2-byte no-ops in front of the last far call (`NOPS2 9` in `part3`) selects what is seen. With this program
on kernel 7.3.6, six workers, two runs of 60 s per count:

| No-ops | Seen |
|---|---|
| 4 | the hart locks: it stops executing, takes no interrupts, and does not respond to a debugger halt request. This is [k3bump2](https://github.com/jasonmontleon/k3bump2) |
| 2 | the hart locks, less often (1 of 3 runs, kernel 7.3.5) |
| 9 | wrong results, about 280 a minute |
| 5 or 8 | wrong results, 0 to 5 a minute, and an occasional trap |
| 0, 1, 3, 6, 7, 10, 11, 12, 14, 16 | nothing in two minutes |

Which counts show something, and how often, changes with the kernel build: 6 no-ops give hundreds of wrong results a
minute on the vendor kernel and on 7.3.0, and 3 no-ops lock the hart on the vendor kernel but not on 7.3.5.

## Interrupts

Both forms need interrupts, or are at least made far more frequent by them. One hart was set aside so that it takes
about 3 interrupts a second instead of 1,000 (`nohz_full`, kernel 7.3.5), and compared with an ordinary hart:

| Program | Ordinary hart | Hart with about 3 interrupts a second |
|---|---|---|
| wrong results (6 no-ops), 3 runs of 300 s | 30, 26, 60 | 0, 5, 5 |
| lock-up (4 no-ops), one worker | locked within 2 s, 5 of 5 runs | 3 of 7 runs locked (within 1 s, 8 s, 27 s); 4 ran to the end (60 s, 60 s, 300 s, 300 s) |

The relation is not a simple proportion: 20 times more timer interrupts on a hart (21,000 a second) did not give more
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
