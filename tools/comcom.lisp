;;; -*- Package: User -*-
;;;
(in-package "USER")

#+bootstrap
(copy-packages (cons (c::backend-name c::*target-backend*) '("ASSEM" "C")))
#+bootstrap
(export '(assem::nop) "ASSEM")

(defparameter *load-stuff* #+bootstrap t #-bootstrap nil)

;;; Import so that these types which appear in the globldb are the same...
#+bootstrap
(import '(old-c::approximate-function-type
	  old-c::function-info old-c::defstruct-description
	  old-c::defstruct-slot-description)
	"C")

(with-compiler-log-file
    ("target:compile-compiler.log"
     :optimize
     '(optimize (speed 2) (space 2) (inhibit-warnings 2)
		(safety #+small 0 #-small 1)
		(debug-info #+small .5 #-small 2))
     :optimize-interface
     '(optimize-interface (safety #+small 1 #-small 2)
			  (debug-info #+small .5 #-small 2))
     :context-declarations
     '(#+small
       ((:or :macro
	     (:match "$SOURCE-TRANSFORM-" "$IR1-CONVERT-"
		     "$PRIMITIVE-TRANSLATE-" "$PARSE-"))
	(declare (optimize (safety 1))))
       (:external (declare (optimize-interface (safety 2) (debug-info 1))))))

(comf "target:compiler/macros" :load *load-stuff*)
(comf "target:compiler/generic/vm-macs" :load *load-stuff* :proceed t)
(comf "target:compiler/backend" :load *load-stuff* :proceed t)

(defvar c::*target-backend* (c::make-backend))

(when (c:target-featurep :pmax)
  (comf "target:compiler/mips/parms" :proceed t))
(when (c:target-featurep :sparc)
  (comf "target:compiler/sparc/parms" :proceed t))
(when (c:target-featurep :rt)
  (comf "target:compiler/rt/params" :proceed t))
(when (c:target-featurep :hppa)
  (comf "target:compiler/hppa/parms" :proceed t))
(when (c:target-featurep :x86)
  (comf "target:compiler/hppa/x86" :proceed t))
(comf "target:compiler/generic/objdef" :proceed t)
(comf "target:compiler/generic/interr")

(comf "target:code/struct") ; For defstruct description structures.
(comf "target:compiler/proclaim") ; For COOKIE structure.
(comf "target:compiler/globals")

(comf "target:compiler/type")
(comf "target:compiler/generic/vm-type")
(comf "target:compiler/type-init")
(comf "target:compiler/sset")
(comf "target:compiler/node")
(comf "target:compiler/ctype")
(comf "target:compiler/vop" :proceed t)
(comf "target:compiler/vmdef" :load *load-stuff* :proceed t)

(unless (c:target-featurep '(or :hppa :x86))
  (comf "target:compiler/assembler" :proceed t)
  (comf "target:compiler/disassem"))
(comf "target:compiler/new-assem")
(comf "target:compiler/alloc")
(comf "target:compiler/knownfun")
(comf "target:compiler/fndb")
(comf "target:compiler/generic/vm-fndb")
(comf "target:compiler/main")

(with-compilation-unit
    (:optimize '(optimize (debug-info 2) (safety 1)))
  (comf "target:compiler/ir1tran")
  (comf "target:compiler/ir1util")
  (comf "target:compiler/ir1opt"))

(comf "target:compiler/ir1final")
(comf "target:compiler/srctran")
(comf "target:compiler/array-tran")
(comf "target:compiler/seqtran")
(comf "target:compiler/typetran")
(comf "target:compiler/generic/vm-typetran")
(comf "target:compiler/float-tran")
(comf "target:compiler/saptran")
(comf "target:compiler/locall")
(comf "target:compiler/dfo")
(comf "target:compiler/checkgen")
(comf "target:compiler/constraint")
(comf "target:compiler/envanal")

(comf "target:compiler/tn")
(comf "target:compiler/bit-util")
(comf "target:compiler/life")

(comf "target:code/debug-info")

(comf "target:compiler/debug-dump")
(comf "target:compiler/generic/utils")
(comf "target:assembly/assemfile" :load *load-stuff*)

(with-compilation-unit
    (:optimize '(optimize (safety #+small 0 #-small 1) #+small (debug-info 1)))

(when (c:target-featurep :pmax)
  (comf "target:compiler/mips/insts")
  (comf "target:compiler/mips/macros" :load *load-stuff*)
  (comf "target:compiler/mips/vm")
  (comf "target:compiler/generic/primtype")
  (comf "target:assembly/mips/support" :load *load-stuff*)
  (comf "target:compiler/mips/move")
  (comf "target:compiler/mips/float")
  (comf "target:compiler/mips/sap")
  (comf "target:compiler/mips/system")
  (comf "target:compiler/mips/char")
  (comf "target:compiler/mips/memory")
  (comf "target:compiler/mips/static-fn")
  (comf "target:compiler/mips/arith")
  (comf "target:compiler/mips/subprim")
  (comf "target:compiler/mips/debug")
  (comf "target:compiler/mips/c-call")
  (comf "target:compiler/mips/cell")
  (comf "target:compiler/mips/values")
  (comf "target:compiler/mips/alloc")
  (comf "target:compiler/mips/call")
  (comf "target:compiler/mips/nlx")
  (comf "target:compiler/mips/print")
  (comf "target:compiler/mips/array")
  (comf "target:compiler/mips/pred")
  (comf "target:compiler/mips/type-vops")

  (comf "target:assembly/mips/assem-rtns")
  (comf "target:assembly/mips/array")
  (comf "target:assembly/mips/arith")
  (comf "target:assembly/mips/alloc"))

(when (c:target-featurep :sparc)
  (comf "target:compiler/sparc/insts")
  (comf "target:compiler/sparc/macros" :load *load-stuff*)
  (comf "target:compiler/sparc/vm")
  (comf "target:compiler/generic/primtype")
  (comf "target:compiler/sparc/move")
  (comf "target:compiler/sparc/float")
  (comf "target:compiler/sparc/sap")
  (comf "target:compiler/sparc/system")
  (comf "target:compiler/sparc/char")
  (comf "target:compiler/sparc/memory")
  (comf "target:compiler/sparc/static-fn")
  (comf "target:compiler/sparc/arith")
  (comf "target:compiler/sparc/subprim")
  (comf "target:compiler/sparc/debug")
  (comf "target:compiler/sparc/c-call")
  (comf "target:compiler/sparc/cell")
  (comf "target:compiler/sparc/values")
  (comf "target:compiler/sparc/alloc")
  (comf "target:compiler/sparc/call")
  (comf "target:compiler/sparc/nlx")
  (comf "target:compiler/sparc/print")
  (comf "target:compiler/sparc/array")
  (comf "target:compiler/sparc/pred")
  (comf "target:compiler/sparc/type-vops")

  (comf "target:assembly/sparc/support" :load *load-stuff*)
  (comf "target:assembly/sparc/assem-rtns")
  (comf "target:assembly/sparc/array")
  (comf "target:assembly/sparc/arith")
  (comf "target:assembly/sparc/alloc"))

(when (c:target-featurep :rt)
  (comf "target:compiler/rt/insts")
  (comf "target:compiler/rt/macros" :load *load-stuff*)
  (comf "target:compiler/rt/vm")
  (comf "target:compiler/rt/move")
  (if (c:target-featurep :afpa)
      (comf "target:compiler/rt/afpa")
      (comf "target:compiler/rt/mc68881"))
  (comf "target:compiler/rt/sap")
  (comf "target:compiler/rt/system")
  (comf "target:compiler/rt/char")
  (comf "target:compiler/rt/memory")
  (comf "target:compiler/rt/static-fn")
  (comf "target:compiler/rt/arith")
  (comf "target:compiler/rt/subprim")
  (comf "target:compiler/rt/debug")
  (comf "target:compiler/rt/c-call")
  (comf "target:compiler/rt/cell")
  (comf "target:compiler/rt/values")
  (comf "target:compiler/rt/alloc")
  (comf "target:compiler/rt/call")
  (comf "target:compiler/rt/nlx")
  (comf "target:compiler/rt/print")
  (comf "target:compiler/rt/array")
  (comf "target:compiler/rt/pred")
  (comf "target:compiler/rt/type-vops")

  (comf "target:assembly/rt/support" :load *load-stuff*)
  (comf "target:assembly/rt/assem-rtns")
  (comf "target:assembly/rt/array")
  (comf "target:assembly/rt/arith")
  (comf "target:assembly/rt/alloc"))

(when (c:target-featurep :hppa)
  (comf "target:compiler/hppa/insts")
  (comf "target:compiler/hppa/macros" :load *load-stuff*)
  (comf "target:compiler/hppa/vm")
  (comf "target:compiler/generic/primtype")
  (comf "target:assembly/hppa/support" :load *load-stuff*)
  (comf "target:compiler/hppa/move")
  (comf "target:compiler/hppa/float")
  (comf "target:compiler/hppa/sap")
  (comf "target:compiler/hppa/system")
  (comf "target:compiler/hppa/char")
  (comf "target:compiler/hppa/memory")
  (comf "target:compiler/hppa/static-fn")
  (comf "target:compiler/hppa/arith")
  (comf "target:compiler/hppa/subprim")
  (comf "target:compiler/hppa/debug")
  (comf "target:compiler/hppa/c-call")
  (comf "target:compiler/hppa/cell")
  (comf "target:compiler/hppa/values")
  (comf "target:compiler/hppa/alloc")
  (comf "target:compiler/hppa/call")
  (comf "target:compiler/hppa/nlx")
  (comf "target:compiler/hppa/print")
  (comf "target:compiler/hppa/array")
  (comf "target:compiler/hppa/pred")
  (comf "target:compiler/hppa/type-vops")

  (comf "target:assembly/hppa/assem-rtns")
  (comf "target:assembly/hppa/array")
  (comf "target:assembly/hppa/arith")
  (comf "target:assembly/hppa/alloc"))

(when (c:target-featurep :x86)
  (comf "target:compiler/x86/insts")
  (comf "target:compiler/x86/macros" :load *load-stuff*)
  (comf "target:compiler/x86/vm")
  (comf "target:compiler/generic/primtype")
  (comf "target:assembly/x86/support" :load *load-stuff*)
  (comf "target:compiler/x86/move")
  (comf "target:compiler/x86/float")
  (comf "target:compiler/x86/sap")
  (comf "target:compiler/x86/system")
  (comf "target:compiler/x86/char")
  (comf "target:compiler/x86/memory")
  (comf "target:compiler/x86/static-fn")
  (comf "target:compiler/x86/arith")
  (comf "target:compiler/x86/subprim")
  (comf "target:compiler/x86/debug")
  (comf "target:compiler/x86/c-call")
  (comf "target:compiler/x86/cell")
  (comf "target:compiler/x86/values")
  (comf "target:compiler/x86/alloc")
  (comf "target:compiler/x86/call")
  (comf "target:compiler/x86/nlx")
  (comf "target:compiler/x86/print")
  (comf "target:compiler/x86/array")
  (comf "target:compiler/x86/pred")
  (comf "target:compiler/x86/type-vops")

  (comf "target:assembly/x86/assem-rtns")
  (comf "target:assembly/x86/array")
  (comf "target:assembly/x86/arith")
  (comf "target:assembly/x86/alloc"))

(comf "target:compiler/pseudo-vops")

); with-compilation-unit for back end.

(comf "target:compiler/aliencomp")
(comf "target:compiler/ltv")
(comf "target:compiler/gtn")
(with-compilation-unit
    (:optimize '(optimize (debug-info 2) (safety 1)))
  (comf "target:compiler/ltn"))
(comf "target:compiler/stack")
(comf "target:compiler/control")
(comf "target:compiler/entry")
(with-compilation-unit
    (:optimize '(optimize (debug-info 2) (safety 1)))
  (comf "target:compiler/ir2tran"))
(comf "target:compiler/copyprop")
(unless (c:target-featurep '(or :hppa :x86))
  (comf "target:compiler/assem-opt"))
(with-compilation-unit
    (:optimize '(optimize (debug-info 2) (safety 1)))
  (comf "target:compiler/represent"))
(comf "target:compiler/generic/vm-tran")
(with-compilation-unit
    (:optimize '(optimize (debug-info 2) (safety 1)))
  (comf "target:compiler/pack"))
(comf "target:compiler/codegen")
(with-compilation-unit
    (:optimize '(optimize (debug-info 2) (safety 2)))
  (comf "target:compiler/debug"))
(comf "target:compiler/assem-check")
(comf "target:compiler/statcount")
(comf "target:compiler/dyncount")

(comf "target:compiler/dump")

(comf "target:compiler/generic/core")
(if (c:target-featurep '(or :hppa :x86))
    (comf "target:compiler/generic/new-genesis")
    (comf "target:compiler/generic/genesis"))

(comf "target:compiler/eval-comp")
(comf "target:compiler/eval")

); with-compiler-error-log
