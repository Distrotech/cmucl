/* $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/ldb/Attic/ldb.c,v 1.5 1990/05/23 19:02:45 ch Exp $ */
/* Lisp kernel core debugger */

#include <stdio.h>
#include <sys/types.h>
#include <sys/file.h>
#include <mach.h>

#include "ldb.h"
#include "lisp.h"
#include "alloc.h"
#include "vars.h"

lispobj lisp_nil_reg = NIL;
char *lisp_csp_reg, *lisp_bsp_reg;

static lispobj alloc_str_list(list)
char *list[];
{
    lispobj result, newcons;
    struct cons *ptr;

    if (*list == NULL)
        result = NIL;
    else {
        result = newcons = alloc_cons(alloc_string(*list++), NIL);

        while (*list != NULL) {
            ptr = (struct cons *)PTR(newcons);
            newcons = alloc_cons(alloc_string(*list++), NIL);
            ptr->cdr = newcons;
        }
    }

    return result;
}


main(argc, argv, envp)
int argc;
char *argv[];
char *envp[];
{
    char *arg, **argptr;
    char *core = NULL;

    define_var("nil", NIL, TRUE);
    define_var("t", T, TRUE);

    argptr = argv;
    while ((arg = *++argptr) != NULL) {
        if (strcmp(arg, "-core") == 0) {
            if (core != NULL) {
                fprintf(stderr, "can only specify one core file.\n");
                exit(1);
            }
            core = *++argptr;
            if (core == NULL) {
                fprintf(stderr, "-core must be followed by the name of the core file to use.\n");
                exit(1);
            }
        }
    }

    if (core == NULL)
        core = "test.core";

#if defined(EXT_PAGER)
    pager_init();
#endif

    gc_init();
    
    validate();

    load_core_file(core);

    globals_init();

    interrupt_init();

    /* Convert the argv and envp to something Lisp can grok. */
    SetSymbolValue(LISP_COMMAND_LINE_LIST, alloc_str_list(argv));
    SetSymbolValue(LISP_ENVIRONMENT_LIST, alloc_str_list(envp));

    test_init();

    while (1)
        monitor();
}
