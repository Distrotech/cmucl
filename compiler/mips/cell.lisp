;;; -*- Package: MIPS; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/mips/cell.lisp,v 1.62 1992/12/16 13:58:00 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;;    This file contains the VM definition of various primitive memory access
;;; VOPs for the MIPS.
;;;
;;; Written by Rob MacLachlan
;;;
;;; Converted by William Lott.
;;; 

(in-package "MIPS")


;;;; Data object ref/set stuff.

(define-vop (slot)
  (:args (object :scs (descriptor-reg)))
  (:info name offset lowtag)
  (:ignore name)
  (:results (result :scs (descriptor-reg any-reg)))
  (:generator 1
    (loadw result object offset lowtag)))

(define-vop (set-slot)
  (:args (object :scs (descriptor-reg))
	 (value :scs (descriptor-reg any-reg)))
  (:info name offset lowtag #+gengc remember)
  (:ignore name)
  (:results)
  (:generator 1
    #+gengc
    (if remember
	(storew-and-remember-slot value object offset lowtag)
	(storew value object offset lowtag))
    #-gengc
    (storew value object offset lowtag)))


;;;; Symbol hacking VOPs:

;;; The compiler likes to be able to directly SET symbols.
;;;
(define-vop (set cell-set)
  (:variant symbol-value-slot other-pointer-type))

;;; Do a cell ref with an error check for being unbound.
;;;
(define-vop (checked-cell-ref)
  (:args (object :scs (descriptor-reg) :target obj-temp))
  (:results (value :scs (descriptor-reg any-reg)))
  (:policy :fast-safe)
  (:vop-var vop)
  (:save-p :compute-only)
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:temporary (:scs (descriptor-reg) :from (:argument 0)) obj-temp))

;;; With Symbol-Value, we check that the value isn't the trap object.  So
;;; Symbol-Value of NIL is NIL.
;;;
(define-vop (symbol-value checked-cell-ref)
  (:translate symbol-value)
  (:generator 9
    (move obj-temp object)
    (loadw value obj-temp symbol-value-slot other-pointer-type)
    (let ((err-lab (generate-error-code vop unbound-symbol-error obj-temp)))
      (inst xor temp value unbound-marker-type)
      (inst beq temp zero-tn err-lab)
      (inst nop))))

;;; Like CHECKED-CELL-REF, only we are a predicate to see if the cell is bound.
(define-vop (boundp-frob)
  (:args (object :scs (descriptor-reg)))
  (:conditional)
  (:info target not-p)
  (:policy :fast-safe)
  (:temporary (:scs (descriptor-reg)) value)
  (:temporary (:scs (non-descriptor-reg)) temp))

(define-vop (boundp boundp-frob)
  (:translate boundp)
  (:generator 9
    (loadw value object symbol-value-slot other-pointer-type)
    (inst xor temp value unbound-marker-type)
    (if not-p
	(inst beq temp zero-tn target)
	(inst bne temp zero-tn target))
    (inst nop)))

(define-vop (fast-symbol-value cell-ref)
  (:variant symbol-value-slot other-pointer-type)
  (:policy :fast)
  (:translate symbol-value))



;;;; Fdefinition (fdefn) objects.

(define-vop (fdefn-function cell-ref)
  (:variant fdefn-function-slot-slot other-pointer-type))

(define-vop (safe-fdefn-function)
  (:args (object :scs (descriptor-reg) :target obj-temp))
  (:results (value :scs (descriptor-reg any-reg)))
  (:vop-var vop)
  (:save-p :compute-only)
  (:temporary (:scs (descriptor-reg) :from (:argument 0)) obj-temp)
  (:generator 10
    (move obj-temp object)
    (loadw value obj-temp fdefn-function-slot other-pointer-type)
    (let ((err-lab (generate-error-code vop undefined-symbol-error obj-temp)))
      (inst beq value null-tn err-lab))
    (inst nop)))

(define-vop (set-fdefn-function)
  (:policy :fast-safe)
  (:translate (setf fdefn-function))
  (:args (function :scs (descriptor-reg) :target result)
	 (fdefn :scs (descriptor-reg)))
  (:temporary (:scs (interior-reg)) lip)
  (:temporary (:scs (non-descriptor-reg)) type)
  (:results (result :scs (descriptor-reg)))
  (:generator 38
    (let ((normal-fn (gen-label)))
      (load-type type function (- function-pointer-type))
      (inst nop)
      (inst xor type function-header-type)
      (inst beq type zero-tn normal-fn)
      (inst addu lip function
	    (- (ash function-header-code-offset word-shift)
	       function-pointer-type))
      (inst li lip (make-fixup "closure_tramp" :foreign))
      (emit-label normal-fn)
      (storew lip fdefn fdefn-raw-addr-slot other-pointer-type)
      (#+gengc storew-and-remember-object #-gengc storew
	       function fdefn fdefn-function-slot
	       other-pointer-type)
      (move result function))))

(define-vop (fdefn-makunbound)
  (:policy :fast-safe)
  (:translate fdefn-makunbound)
  (:args (fdefn :scs (descriptor-reg) :target result))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg)))
  (:generator 38
    (storew null-tn fdefn fdefn-function-slot other-pointer-type)
    (inst li temp (make-fixup "undefined_tramp" :foreign))
    (storew temp fdefn fdefn-raw-addr-slot other-pointer-type)
    (move result fdefn)))



;;;; Binding and Unbinding.

;;; BIND -- Establish VAL as a binding for SYMBOL.  Save the old value and
;;; the symbol on the binding stack and stuff the new value into the
;;; symbol.

(define-vop (bind)
  (:args (val :scs (any-reg descriptor-reg))
	 (symbol :scs (descriptor-reg)))
  (:temporary (:scs (descriptor-reg)) temp)
  (:generator 5
    (loadw temp symbol symbol-value-slot other-pointer-type)
    (inst addu bsp-tn bsp-tn (* 2 word-bytes))
    (storew temp bsp-tn (- binding-value-slot binding-size))
    (storew symbol bsp-tn (- binding-symbol-slot binding-size))
    (#+gengc storew-and-remember-slot #-gengc storew
	     val symbol symbol-value-slot other-pointer-type)))


(define-vop (unbind)
  (:temporary (:scs (descriptor-reg)) symbol value)
  (:generator 0
    (loadw symbol bsp-tn (- binding-symbol-slot binding-size))
    (loadw value bsp-tn (- binding-value-slot binding-size))
    (#+gengc storew-and-remember-slot #-gengc
	     value symbol symbol-value-slot other-pointer-type)
    (storew zero-tn bsp-tn (- binding-symbol-slot binding-size))
    (inst addu bsp-tn bsp-tn (* -2 word-bytes))))


(define-vop (unbind-to-here)
  (:args (arg :scs (descriptor-reg any-reg) :target where))
  (:temporary (:scs (any-reg) :from (:argument 0)) where)
  (:temporary (:scs (descriptor-reg)) symbol value)
  (:generator 0
    (let ((loop (gen-label))
	  (skip (gen-label))
	  (done (gen-label)))
      (move where arg)
      (inst beq where bsp-tn done)

      (emit-label loop)
      (loadw symbol bsp-tn (- binding-symbol-slot binding-size))
      (inst beq symbol zero-tn skip)
      (loadw value bsp-tn (- binding-value-slot binding-size))
      (#+gengc storew-and-remember-slot #-gengc
	       value symbol symbol-value-slot other-pointer-type)
      (storew zero-tn bsp-tn (- binding-symbol-slot binding-size))

      (emit-label skip)
      (inst addu bsp-tn bsp-tn (* -2 word-bytes))
      (inst bne where bsp-tn loop)
      (inst nop)

      (emit-label done))))



;;;; Closure indexing.

(define-full-reffer closure-index-ref *
  closure-info-offset function-pointer-type
  (descriptor-reg any-reg) * %closure-index-ref)

(define-full-setter set-funcallable-instance-info *
  funcallable-instance-info-offset function-pointer-type
  (descriptor-reg any-reg) * %set-funcallable-instance-info)

(define-vop (closure-ref slot-ref)
  (:variant closure-info-offset function-pointer-type))

(define-vop (closure-init slot-set)
  (:variant closure-info-offset function-pointer-type))


;;;; Value Cell hackery.

(define-vop (value-cell-ref cell-ref)
  (:variant value-cell-value-slot other-pointer-type))

(define-vop (value-cell-set cell-set)
  (:variant value-cell-value-slot other-pointer-type))



;;;; Structure hackery:

(define-vop (structure-length)
  (:policy :fast-safe)
  (:translate structure-length)
  (:args (struct :scs (descriptor-reg)))
  (:results (res :scs (unsigned-reg)))
  (:result-types positive-fixnum)
  (:generator 4
    (loadw res struct 0 structure-pointer-type)
    (inst srl res type-bits)))

(define-vop (structure-ref slot-ref)
  (:variant structure-slots-offset structure-pointer-type)
  (:policy :fast-safe)
  (:translate structure-ref)
  (:arg-types structure (:constant index)))

(define-vop (structure-set slot-set)
  (:policy :fast-safe)
  (:translate structure-set)
  (:variant structure-slots-offset structure-pointer-type)
  (:arg-types structure (:constant index) *))

(define-full-reffer structure-index-ref * structure-slots-offset
  structure-pointer-type (descriptor-reg any-reg) * structure-ref)

(define-full-setter structure-index-set * structure-slots-offset
  structure-pointer-type (descriptor-reg any-reg) * structure-set)



;;;; Code object frobbing.

(define-full-reffer code-header-ref * 0 other-pointer-type
  (descriptor-reg any-reg) * code-header-ref)

(define-full-setter code-header-set * 0 other-pointer-type
  (descriptor-reg any-reg) * code-header-set)
