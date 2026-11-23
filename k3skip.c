/* k3skip: driver for the SpacemiT X100 skipped-instruction reproducer.
 *
 * Maps the pages of the "window" (window.S: the code one pass executes, at the addresses it had in the original process, plus
 * the few data pages it uses; data.S), then loops:  load the starting registers, jump into the window, come back, check.
 * The last thing a pass executes is eight instructions that each set one bit of a register that starts as 0; the pass stores
 * that register and the driver checks that it is 0xff.
 * Run:  k3skip             six workers, pinned to harts 0,1,3,4,5,6
 *       k3skip -c 3        one worker on hart 3
 *       ... mapped         control: also map the page behind the straddling branch; must give no wrong results
 * Options: -c LIST (worker harts)   -t SECONDS (default 60)
 * Freestanding: no libc. */
typedef unsigned long u64;
#include "build/pages.h"		/* generated: NPAGES, page_table[] */
extern const unsigned char page_blob[];	/* generated: the contents of those pages (build/pages.bin) */
struct ctx { u64 regs[32]; u64 unused[2]; u64 exit; u64 result; };	/* offsets 272 and 280 are used by exit_stub in window.S */
extern void enter_window(struct ctx *);
extern void window_exit(void);
extern long sys6(long nr, long a, long b, long c, long d, long e, long f);
#define LIB  0x3ff3000000UL
#define PAGE (LIB + 0x2a20000)			/* the page behind the straddling branch: must have no mapping */
enum { SYS_write = 64, SYS_exit_group = 94, SYS_clock_gettime = 113, SYS_sched_setaffinity = 122, SYS_sigaltstack = 132,
       SYS_rt_sigaction = 134, SYS_prctl = 167, SYS_clone = 220, SYS_mmap = 222, SYS_mprotect = 226, SYS_riscv_flush_icache = 259,
       SYS_wait4 = 260 };
static struct ctx ctx;
static const unsigned char zero_page[4096];
/* registers at the start of every pass; everything else is 0 */
static const u64 start_regs[32] = {
	[1]  = LIB + 0x2a9896c,		/* ra: `start` in window.S, the first instruction of the pass */
	[2]  = 0x3feb8465b0UL,		/* sp: the stack F1 uses */
	[4]  = 0x3feb846540UL,		/* tp: the stack line the pass flushes */
	[18] = 0x3feb8499c0UL,		/* s2: OBJECT in data.S, handed to F1 */
	[31] = 0x3ff2ee276eUL,		/* t6: the `ret` the driver jumps to (first section of window.S) */
};
static void pr(const char *fmt, ...);
/* --- traps: a worker that gets SIGILL/SIGBUS/SIGSEGV inside the pass reports where, and goes on with the next pass --- */
static volatile u64 cur_pass, ntraps, nwrong; static long mycpu;
static volatile int probing;
static unsigned char altstack[32768];
static void on_trap(int sig, void *info, void *uc)
{
	u64 *r = (u64 *)((char *)uc + 176);		/* ucontext.uc_mcontext: pc, ra, sp, gp, tp, t0, ... */
	u64 addr = ((u64 *)info)[2];
	if (probing) { pr("k3skip: this system does not let a user program execute cbo.flush (the core lacks Zicbom, or the kernel does not enable it); cannot run here\n"); sys6(SYS_exit_group, 3, 0, 0, 0, 0, 0); }
	if (ntraps++ < 12)
		pr("k3skip: cpu %d: TRAP signal %d at pc 0x%x in pass %d: ra 0x%x sp 0x%x fault address 0x%x\n", (u64)mycpu, (u64)sig, r[0], cur_pass + 1, r[1], r[2], addr);
	r[0] = (u64)window_exit;			/* resume in the driver as if the pass had returned */
}
static void catch_traps(void)
{
	struct { void *sp; int flags; u64 size; } ss = { altstack, 0, sizeof(altstack) };
	struct { void (*fn)(int, void *, void *); u64 flags; u64 mask; } sa = { on_trap, 4 /* SA_SIGINFO */ | 0x08000000 /* SA_ONSTACK */ | 0x40000000 /* SA_NODEFER */, 0 };
	sys6(SYS_sigaltstack, (long)&ss, 0, 0, 0, 0, 0);
	sys6(SYS_rt_sigaction, 4 /* SIGILL */, (long)&sa, 0, 8, 0, 0);
	sys6(SYS_rt_sigaction, 7 /* SIGBUS */, (long)&sa, 0, 8, 0, 0);
	sys6(SYS_rt_sigaction, 11 /* SIGSEGV */, (long)&sa, 0, 8, 0, 0);
}

void *memset(void *d, int c, unsigned long n) { unsigned char *p = d; while (n--) *p++ = c; return d; }
void *memcpy(void *d, const void *s, unsigned long n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }
static void pr(const char *fmt, ...)		/* %s %d %x only */
{
	char b[300]; int n = 0; __builtin_va_list ap;
	__builtin_va_start(ap, fmt);
	for (; *fmt && n < 260; fmt++) {
		if (*fmt != '%') { b[n++] = *fmt; continue; }
		fmt++;
		if (*fmt == 's') { for (const char *s = __builtin_va_arg(ap, const char *); *s && n < 260; s++) b[n++] = *s; }
		else { u64 v = __builtin_va_arg(ap, u64), base = *fmt == 'x' ? 16 : 10; char t[24]; int i = 0;
		       do t[i++] = "0123456789abcdef"[v % base]; while (v /= base);
		       while (i) b[n++] = t[--i]; }
	}
	__builtin_va_end(ap);
	sys6(SYS_write, 1, (long)b, n, 0, 0, 0);
}
static void die(const char *s, u64 v) { pr("k3skip: %s 0x%x\n", s, v); sys6(SYS_exit_group, 2, 0, 0, 0, 0, 0); }
static u64 now_ms(void) { u64 ts[2]; sys6(SYS_clock_gettime, 1, (long)ts, 0, 0, 0, 0); return ts[0] * 1000 + ts[1] / 1000000; }
static long num(const char *s) { long v = 0; while (*s >= '0' && *s <= '9') v = v * 10 + *s++ - '0'; return v; }
static void map_page(u64 a, const unsigned char *bytes, int prot)
{
	if ((u64)sys6(SYS_mmap, a, 4096, 3, 0x32 /* PRIVATE|ANONYMOUS|FIXED */, -1, 0) != a) die("cannot map page at", a);
	for (int i = 0; i < 512; i++) ((u64 *)a)[i] = ((const u64 *)bytes)[i];
	if (prot != 3 && sys6(SYS_mprotect, a, 4096, prot, 0, 0, 0)) die("mprotect failed at", a);
}
static void pin(long cpu)
{
	u64 m[16] = { 0 };
	m[cpu / 64] = 1UL << (cpu % 64);
	if (sys6(SYS_sched_setaffinity, 0, sizeof(m), (long)m, 0, 0, 0) < 0) die("cannot pin to cpu", cpu);
}
static int in_list(const char *l, long h)		/* is hart h in the comma-separated list? */
{
	while (*l) { if (*l >= '0' && *l <= '9' && num(l) == h) return 1; while (*l && *l != ',') l++; if (*l) l++; }
	return 0;
}
static void worker(long cpu, long secs, int control, int many)
{
	u64 pass = 0, t0, tnext;

	if (many) sys6(SYS_prctl, 1 /* PR_SET_PDEATHSIG */, 9, 0, 0, 0, 0);
	pin(cpu); mycpu = cpu; catch_traps();
	{ static u64 probe_word; probing = 1; __asm__ volatile(".insn i 0x0f, 2, x0, %0, 2" : : "r"(&probe_word)); probing = 0; }	/* cbo.flush once, outside the pass: does this system allow it? */
	for (unsigned long i = 0; i < NPAGES; i++) {	/* kind 0: code (this includes the page that ends in half a branch), 1: read-only data, 2: data */
		int k = page_table[i].kind;
		map_page(page_table[i].addr, page_blob + i * 4096, k == 0 ? 5 : k == 1 ? 1 : 3);
	}
	if (control) map_page(PAGE, zero_page, 5);
	sys6(SYS_riscv_flush_icache, LIB, LIB + 0x338b000, 0, 0, 0, 0);
	pr("k3skip: cpu %d: %d pages, the page behind the branch is %s\n", (u64)cpu, (u64)NPAGES, control ? "MAPPED (control)" : "not mapped");
	t0 = now_ms(); tnext = t0 + 1000;
	for (;;) {
		for (int i = 0; i < 32; i++) ctx.regs[i] = start_regs[i];
		ctx.exit = (u64)window_exit; ctx.result = 0; cur_pass = pass;
		enter_window(&ctx);
		pass++;
		if (ctx.result != 0xff && nwrong++ < 12)
			pr("k3skip: cpu %d: WRONG RESULT in pass %d: eight instructions each set one bit, expected 0xff, got 0x%x (missing bits 0x%x)\n", (u64)cpu, pass, ctx.result, ctx.result ^ 0xff);
		if ((pass & 0x3f) == 0 || pass == 1) {
			u64 t = now_ms();
			if (t >= tnext || pass == 1) { pr("k3skip: cpu %d: %d passes, %d s\n", (u64)cpu, pass, (t - t0) / 1000); tnext = t + 1000; }
			if (t - t0 >= (u64)secs * 1000) break;
		}
	}
	pr("k3skip: cpu %d SUMMARY: %d passes, %d traps, %d wrong results\n", (u64)cpu, pass, ntraps, nwrong);
}

void k3main(long argc, char **argv)
{
	long secs = 60, control = 0, nw = 0, one = -1;
	const char *cpus = "0,1,3,4,5,6";

	for (long i = 1; i < argc; i++) {
		if (argv[i][0] == 'm') control = 1;
		else if (argv[i][0] != '-' || i + 1 >= argc) continue;
		else if (argv[i][1] == 't') secs = num(argv[++i]);
		else if (argv[i][1] == 'c') cpus = argv[++i];
		else i++;					/* any other option: skip it and its value */
	}
	for (long h = 0; h < 64; h++) if (in_list(cpus, h)) { nw++; one = h; }
	if (nw == 0) die("no worker hart in the -c list", 0);
	if (nw == 1) worker(one, secs, control, 0);
	else {
		long left = 0;
		for (long h = 0; h < 64; h++) {
			if (!in_list(cpus, h)) continue;
			if (sys6(SYS_clone, 17 /* SIGCHLD */, 0, 0, 0, 0, 0) == 0) { worker(h, secs, control, 1); sys6(SYS_exit_group, 0, 0, 0, 0, 0, 0); }
			left++;
		}
		while (left-- > 0) sys6(SYS_wait4, -1, 0, 0, 0, 0, 0);
	}
	sys6(SYS_exit_group, 0, 0, 0, 0, 0, 0);
}
