;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/sparc/values.lisp,v 1.2 1992/10/11 10:54:28 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;;    This file contains the implementation of unknown-values VOPs.
;;;
;;; Written by Rob MacLachlan
;;;
;;; Converted for SPARC by William Lott.
;;; 

(in-package "SPARC")

(define-vop (reset-stack-pointer)
  (:args (ptr :scs (any-reg)))
  (:generator 1
    (move csp-tn ptr)))


;;; Push some values onto the stack, returning the start and number of values
;;; pushed as results.  It is assumed that the Vals are wired to the standard
;;; argument locations.  Nvals is the number of values to push.
;;;
;;; The generator cost is pseudo-random.  We could get it right by defining a
;;; bogus SC that reflects the costs of the memory-to-memory moves for each
;;; operand, but this seems unworthwhile.
;;;
(define-vop (push-values)
  (:args (vals :more t))
  (:results (start :scs (any-reg) :from :load)
	    (count :scs (any-reg)))
  (:info nvals)
  (:temporary (:scs (descriptor-reg)) temp)
  (:generator 20
    (inst move start csp-tn)
    (inst add csp-tn csp-tn (* nvals vm:word-bytes))
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
    (inst li count (fixnum nvals))))

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
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 0
    (let ((loop (gen-label))
	  (done (gen-label)))

      (move list arg)
      (move start csp-tn)

      (emit-label loop)
      (inst cmp list null-tn)
      (inst b :eq done)
      (loadw temp list vm:cons-car-slot vm:list-pointer-type)
      (loadw list list vm:cons-cdr-slot vm:list-pointer-type)
      (inst add csp-tn csp-tn vm:word-bytes)
      (storew temp csp-tn -1)
      (test-type list ndescr loop nil vm:list-pointer-type)
      (error-call vop bogus-argument-to-values-list-error list)

      (emit-label done)
      (inst sub count csp-tn start))))

