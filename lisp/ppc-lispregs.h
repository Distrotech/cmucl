#if defined DARWIN
#if defined LANGUAGE_ASSEMBLY
#define REG(num) r##num
#else
#define REG(num) num
#endif
#else
#define REG(num) num
#endif

#define NREGS 32

#define reg_ZERO      REG(0)	/* Should alwasy contain 0 in lisp */
#define reg_NSP       REG(1)	/* The number/C stack pointer */
#define reg_POLL      REG(2)	/* Lisp preemption/Mystery SVR4 ABI reg */
#define reg_NL0       REG(3)	/* FF param/result 1 */
#define reg_NL1       REG(4)	/* FF param/result 2 */
#define reg_NL2       REG(5)	/* FF param 3 */
#define reg_NL3       REG(6)
#define reg_NL4       REG(7)
#define reg_NL5       REG(8)
#define reg_NL6       REG(9)
#define reg_FDEFN     REG(10)	/* Last (8th) FF param */
#define reg_NARGS     REG(11)
#define reg_CFUNC     REG(12)	/* Silly to blow a reg on FF-name */
#define reg_NFP       REG(13)	/* Lisp may save around FF-call */
#define reg_BSP       REG(14)   /* Binding stack pointer */
#define reg_CFP       REG(15)	/* Control/value stack frame pointer */
#define reg_CSP       REG(16)	/* Control/value stack top */
#define reg_ALLOC     REG(17)	/* (Global) dynamic free pointer */
#define reg_NULL      REG(18)	/* NIL and globals nearby */
#define reg_CODE      REG(19)	/* Current function object */
#define reg_CNAME     REG(20)	/* Current function name */
#define reg_LEXENV    REG(21)	/* And why burn a register for this ? */
#define reg_OCFP      REG(22)   /* The caller's reg_CFP */
#define reg_LRA       REG(23)	/* Tagged lisp return address */
#define reg_A0        REG(24)	/* First function arg/return value */
#define reg_A1        REG(25)	/* Second. */
#define reg_A2        REG(26)	/*  */
#define reg_A3        REG(27)	/* Last of (only) 4 arg regs */
#define reg_L0	      REG(28)	/* Tagged temp regs */
#define reg_L1        REG(29)
#define reg_L2        REG(30)	/* Last lisp temp reg */
#define reg_LIP       REG(31)	/* Lisp Interior Pointer, e.g., locative */

#define REGNAMES \
        "ZERO",		"NSP",	        "POLL",		"NL0", \
	"NL1",		"NL2",		"NL3P",		"NL4", \
        "NL5",		"NL6",		"FDEFN",	"NARGS", \
        "CFUNC",	"NFP"		"BSP",		"CFP", \
        "CSP",		"ALLOC",	"NULL",		"CODE", \
        "CNAME",	"LEXENV",	"OCFP",		"LRA", \
        "A0",	        "A1",	        "A2",		"A3", \
        "L0",		"L1",		"L2",		"LIP"

#define BOXED_REGISTERS { \
    reg_FDEFN, reg_CODE, reg_CNAME, reg_LEXENV, reg_OCFP, reg_LRA, \
    reg_A0, reg_A1, reg_A2, reg_A3, \
    reg_L0, reg_L1, reg_L2 \
}

#ifndef LANGUAGE_ASSEMBLY
#if defined DARWIN
#define SC_REG(sc,reg) (*sc_reg(sc,reg))
#define SC_PC(sc) (sc->uc_mcontext->ss.srr0)
#else
#define SC_REG(sc,reg) (((unsigned long *)(sc->regs))[(reg)])
#define SC_PC(sc) (((unsigned long *)(sc->regs))[PT_NIP])
#endif

#endif
