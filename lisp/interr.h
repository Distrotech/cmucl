/*
 * $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/lisp/interr.h,v 1.2 2004/07/12 23:44:07 pmai Exp $
 */

#ifndef _INTERR_H_
#define _INTERR_H_

#define crap_out(msg) do { write(2, msg, sizeof(msg)); lose(); } while (0)

extern void lose(char *fmt, ...);
extern void set_lossage_handler(void fun(void));
extern void internal_error(os_context_t *context);

extern lispobj debug_print(lispobj string);

#endif
