;;; -*- Package: MIPS; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/mips/subprim.lisp,v 1.21 1992/07/28 20:37:52 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;;    Linkage information for standard static functions, and random vops.
;;;
;;; Written by William Lott.
;;; 
(in-package "MIPS")



;;;; Length

(define-vop (length/list)
  (:translate length)
  (:args (object :scs (descriptor-reg) :target ptr))
  (:arg-types list)
  (:temporary (:scs (descriptor-reg) :from (:argument 0)) ptr)
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:temporary (:scs (any-reg) :type fixnum :to (:result 0) :target result)
	      count)
  (:results (result :scs (any-reg descriptor-reg)))
  (:policy :fast-safe)
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 50
    (move ptr object)
    (move count zero-tn)
    
    LOOP
    
    (inst beq ptr null-tn done)
    (inst nop)
    
    (inst and temp ptr lowtag-mask)
    (inst xor temp list-pointer-type)
    (inst bne temp zero-tn not-list)
    (inst nop)
    
    (loadw ptr ptr cons-cdr-slot list-pointer-type)
    (inst b loop)
    (inst addu count count (fixnum 1))
    
    NOT-LIST
    (cerror-call vop done object-not-list-error ptr)
    
    DONE
    (move result count)))
       

(define-static-function length (object) :translate length)



