/*

 $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/lisp/ppc-arch.c,v 1.1 2004/07/13 00:26:22 pmai Exp $

 This code was written as part of the CMU Common Lisp project at
 Carnegie Mellon University, and has been placed in the public domain.

*/

#include <stdio.h>

#include "arch.h"
#include "lisp.h"
#include "internals.h"
#include "globals.h"
#include "validate.h"
#include "os.h"
#include "lispregs.h"
#include "signal.h"
#include "interrupt.h"
#include "interr.h"

  /* The header files may not define PT_DAR/PT_DSISR.  This definition
     is correct for all versions of ppc linux >= 2.0.30

     As of DR2.1u4, MkLinux doesn't pass these registers to signal
     handlers correctly; a patch is necessary in order to (partially)
     correct this.

     Even with the patch, the DSISR may not have its 'write' bit set
     correctly (it tends not to be set if the fault was caused by
     something other than a protection violation.)
     
     Caveat callers.  */

#ifndef PT_DAR
#define PT_DAR		41
#endif

#ifndef PT_DSISR
#define PT_DSISR	42
#endif

char * arch_init(void)
{
  return "lisp.core";
}

os_vm_address_t 
arch_get_bad_addr(HANDLER_ARGS)
{
  unsigned long badinstr, pc = SC_PC(context);
  int instclass;
  os_vm_address_t addr;


  /* Make sure it's not the pc thats bogus, and that it was lisp code */
  /* that caused the fault. */
  if ((pc & 3) != 0 ||
      ((pc < READ_ONLY_SPACE_START ||
	pc >= READ_ONLY_SPACE_START+READ_ONLY_SPACE_SIZE) &&
       ((lispobj *)pc < current_dynamic_space &&
	(lispobj *)pc >= current_dynamic_space + DYNAMIC_SPACE_SIZE)))
    return 0;
  

  addr = (os_vm_address_t) SC_REG(context, PT_DAR);
  return addr;
}
      

void 
arch_skip_instruction(os_context_t *context)
{
  /* Skip the offending instruction */
  SC_PC(context) += 4;
}

unsigned char *
arch_internal_error_arguments(os_context_t *scp)
{
  return (unsigned char *)(SC_PC(scp)+4);
}

boolean 
arch_pseudo_atomic_atomic(os_context_t *scp)
{
  return (SC_REG(scp, reg_ALLOC) & 4);
}

#define PSEUDO_ATOMIC_INTERRUPTED_BIAS 0x7f000000

void 
arch_set_pseudo_atomic_interrupted(os_context_t *scp)
{
  SC_REG(scp, reg_NL3) += PSEUDO_ATOMIC_INTERRUPTED_BIAS;
}

unsigned long 
arch_install_breakpoint(void *pc)
{
  unsigned long *ptr = (unsigned long *)pc;
  unsigned long result = *ptr;
  *ptr = (3<<26) | (5 << 21) | trap_Breakpoint;
  os_flush_icache((os_vm_address_t) pc, sizeof(unsigned long));
  return result;
}

void 
arch_remove_breakpoint(void *pc, unsigned long orig_inst)
{
  *(unsigned long *)pc = orig_inst;
  os_flush_icache((os_vm_address_t) pc, sizeof(unsigned long));
}

static unsigned long *skipped_break_addr, displaced_after_inst;
static sigset_t orig_sigmask;

void 
arch_do_displaced_inst(os_context_t *scp, unsigned long orig_inst)
{
  unsigned long *pc = (unsigned long *)SC_PC(scp);

  orig_sigmask = scp->uc_sigmask;
  sigemptyset(&scp->uc_sigmask);
  FILLBLOCKSET(&scp->uc_sigmask);

  *pc = orig_inst;
  os_flush_icache((os_vm_address_t) pc, sizeof(unsigned long));
  skipped_break_addr = pc;
}

static void 
sigill_handler(HANDLER_ARGS)
{
  int badinst;
  int opcode;
  HANDLER_GET_CONTEXT
    
    SAVE_CONTEXT();

  sigprocmask(SIG_SETMASK, &context->uc_sigmask, 0);
  opcode = *((int *) SC_PC(context));

  if (opcode == ((3 << 26) | (16 << 21) | (reg_ALLOC << 16))) {
    /* twlti reg_ALLOC,0 - check for deferred interrupt */
    (SC_REG(context, reg_ALLOC) -= PSEUDO_ATOMIC_INTERRUPTED_BIAS);
    arch_skip_instruction(context);
    interrupt_handle_pending(context);
#ifdef DARWIN
    /* Work around G5 bug; fix courtesy gbyers via chandler */
    sigreturn(context);
#endif
    return;
  }

  if ((opcode >> 16) == ((3 << 10) | (6 << 5))) {
    /* twllei reg_ZERO,N will always trap if reg_ZERO = 0 */
    int trap = opcode & 0x1f, extra = (opcode >> 5) & 0x1f;
    
    switch (trap) {
    case trap_Halt:
      fake_foreign_function_call(context);
      lose("%%primitive halt called; the party is over.\n");
      
    case trap_Error:
    case trap_Cerror:
      interrupt_internal_error(signal, code, context, trap == trap_Cerror);
      break;

    case trap_PendingInterrupt:
      arch_skip_instruction(context);
      interrupt_handle_pending(context);
      break;

    case trap_Breakpoint:
      handle_breakpoint(signal, code, context);
      break;
      
    case trap_FunctionEndBreakpoint:
      SC_PC(context)=(int)handle_function_end_breakpoint(signal, code, context);
      break;

    case trap_AfterBreakpoint:
      *skipped_break_addr = trap_Breakpoint;
      skipped_break_addr = NULL;
      *(unsigned long *)SC_PC(context) = displaced_after_inst;
      context->uc_sigmask = orig_sigmask;
      
      os_flush_icache((os_vm_address_t) SC_PC(context),
		      sizeof(unsigned long));
      break;

    default:
      interrupt_handle_now(signal, code, context);
      break;
    }
#ifdef DARWIN
    /* Work around G5 bug; fix courtesy gbyers via chandler */
    sigreturn(context);
#endif
    return;
  }
  if (((opcode >> 26) == 3) && (((opcode >> 21) & 31) == 24)) {
    interrupt_internal_error(signal, code, context, 0);
#ifdef DARWIN
    /* Work around G5 bug; fix courtesy gbyers via chandler */
    sigreturn(context);
#endif
    return;
  }

  interrupt_handle_now(signal, code, context);
#ifdef DARWIN
  /* Work around G5 bug; fix courtesy gbyers via chandler */
  sigreturn(context);
#endif
}


void arch_install_interrupt_handlers()
{
    interrupt_install_low_level_handler(SIGILL,sigill_handler);
    interrupt_install_low_level_handler(SIGTRAP,sigill_handler);
}


extern lispobj call_into_lisp(lispobj fun, lispobj *args, int nargs);

lispobj funcall0(lispobj function)
{
    lispobj *args = current_control_stack_pointer;

    return call_into_lisp(function, args, 0);
}

lispobj funcall1(lispobj function, lispobj arg0)
{
    lispobj *args = current_control_stack_pointer;

    current_control_stack_pointer += 1;
    args[0] = arg0;

    return call_into_lisp(function, args, 1);
}

lispobj funcall2(lispobj function, lispobj arg0, lispobj arg1)
{
    lispobj *args = current_control_stack_pointer;

    current_control_stack_pointer += 2;
    args[0] = arg0;
    args[1] = arg1;

    return call_into_lisp(function, args, 2);
}

lispobj funcall3(lispobj function, lispobj arg0, lispobj arg1, lispobj arg2)
{
    lispobj *args = current_control_stack_pointer;

    current_control_stack_pointer += 3;
    args[0] = arg0;
    args[1] = arg1;
    args[2] = arg2;

    return call_into_lisp(function, args, 3);
}

void
ppc_flush_icache(os_vm_address_t address, os_vm_size_t length)
{
  os_vm_address_t end = (os_vm_address_t) ((int)(address+length+(32-1)) &~(32-1));
  extern void ppc_flush_cache_line(os_vm_address_t);

  while (address < end) {
    ppc_flush_cache_line(address);
    address += 32;
  }
}
