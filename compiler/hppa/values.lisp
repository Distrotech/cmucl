;;; -*- Package: HPPA -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/hppa/values.lisp,v 1.1 1992/07/13 03:48:39 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains the implementation of unknown-values VOPs.
;;;
;;; Written by William Lott.
;;; 

(in-package "HPPA")

(define-vop (reset-stack-pointer)
  (:args (ptr :scs (any-reg)))
  (:generator 1
    (move ptr csp-tn)))


;;; Push some values onto the stack, returning the start and number of values
;;; pushed as results.  It is assumed that the Vals are wired to the standard
;;; argument locations.  Nvals is the number of values to push.
;;;
;;; The generator cost is pseudo-random.  We could get it right by defining a
;;; bogus SC that reflects the costs of the memory-to-memory moves for each
;;; operand, but this seems unworthwhile.
;;;
(define-vop (push-values)
  (:args
   (vals :more t))
  (:results (start :scs (any-reg) :from :load)
	    (count :scs (any-reg)))
  (:info nvals)
  (:temporary (:scs (descriptor-reg)) temp)
  (:generator 20
    (move csp-tn start)
    (inst addi (* nvals word-bytes) csp-tn csp-tn)
    (do ((val vals (tn-ref-across val))
	 (i 0 (1+ i)))
	((null val))
      (let ((tn (tn-ref-tn val)))
	(sc-case tn
	  (descriptor-reg
	   (storew tn start i))
	  (control-stack
	   (load-stack-tn temp tn)
	   (storew temp start i)))))
    (inst li (fixnum nvals) count)))


;;; Push a list of values on the stack, returning Start and Count as used in
;;; unknown values continuations.
;;;
(define-vop (values-list)
  (:args (arg :scs (descriptor-reg) :target list))
  (:arg-types list)
  (:policy :fast-safe)
  (:results (start :scs (any-reg))
	    (count :scs (any-reg)))
  (:temporary (:scs (descriptor-reg) :type list :from (:argument 0)) list)
  (:temporary (:scs (descriptor-reg)) temp)
  (:temporary (:scs (non-descriptor-reg) :type random) ndescr)
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 0
    (move arg list)
    (inst comb := list null-tn done)
    (move csp-tn start)

    LOOP
    (loadw temp list cons-car-slot list-pointer-type)
    (loadw list list cons-cdr-slot list-pointer-type)
    (inst addi word-bytes csp-tn csp-tn)
    (storew temp csp-tn -1)
    (inst extru list 31 lowtag-bits ndescr)
    (inst comib := list-pointer-type ndescr loop)
    (inst comb := list null-tn done :nullify t)
    (error-call vop bogus-argument-to-values-list-error list)

    DONE
    (inst sub csp-tn start count)))

