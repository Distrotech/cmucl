/* $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/ldb/Attic/lispregs.h,v 1.4 1990/10/22 12:30:03 wlott Exp $ */

#ifdef LANGUAGE_ASSEMBLY
#ifdef mips
#define REG(num) $num
#endif
#else
#define REG(num) num

extern char *lisp_register_names[];
#endif

#define NREGS	(32)

#ifdef mips
#define ZERO    REG(0)
#define NL3     REG(1)
#define NL4     REG(2)
#define FLAGS   REG(3)
#define NL0     REG(4)
#define NL1     REG(5)
#define NL2     REG(6)
#define NARGS   REG(7)
#define A0      REG(8)
#define A1      REG(9)
#define A2      REG(10)
#define A3      REG(11)
#define A4      REG(12)
#define A5      REG(13)
#define CNAME   REG(14)
#define LEXENV  REG(15)
#define NFP     REG(16)
#define OCFP    REG(17)
#define LRA     REG(18)
#define L0      REG(19)
#define NULLREG REG(20)
#define BSP     REG(21)
#define CFP     REG(22)
#define CSP     REG(23)
#define L1      REG(24)
#define ALLOC   REG(25)
#define L2      REG(28)
#define NSP     REG(29)
#define CODE    REG(30)
#define LIP     REG(31)
#endif
