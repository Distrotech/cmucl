;;; -*- Package: MIPS; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/mips/float.lisp,v 1.12 1991/02/20 15:14:35 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/mips/float.lisp,v 1.12 1991/02/20 15:14:35 ram Exp $
;;;
;;;    This file contains floating point support for the MIPS.
;;;
;;; Written by Rob MacLachlan
;;;
(in-package "MIPS")


;;;; Move functions:

(define-move-function (load-single 1) (vop x y)
  ((single-stack) (single-reg))
  (inst lwc1 y (current-nfp-tn vop) (* (tn-offset x) vm:word-bytes))
  (inst nop))

(define-move-function (store-single 1) (vop x y)
  ((single-reg) (single-stack))
  (inst swc1 x (current-nfp-tn vop) (* (tn-offset y) vm:word-bytes)))


(define-move-function (load-double 2) (vop x y)
  ((double-stack) (double-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (inst lwc1 y nfp offset)
    (inst lwc1-odd y nfp (+ offset vm:word-bytes)))
  (inst nop))

(define-move-function (store-double 2) (vop x y)
  ((double-reg) (double-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (inst swc1 x nfp offset)
    (inst swc1-odd x nfp (+ offset vm:word-bytes))))



;;;; Move VOPs:

(macrolet ((frob (vop sc format)
	     `(progn
		(define-vop (,vop)
		  (:args (x :scs (,sc)
			    :target y
			    :load-if (not (location= x y))))
		  (:results (y :scs (,sc)
			       :load-if (not (location= x y))))
		  (:note "float move")
		  (:generator 0
		    (unless (location= y x)
		      (inst move ,format y x))))
		(define-move-vop ,vop :move (,sc) (,sc)))))
  (frob single-move single-reg :single)
  (frob double-move double-reg :double))


(define-vop (move-from-float)
  (:args (x :to :save))
  (:results (y))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:variant-vars double-p size type data)
  (:note "float to pointer coercion")
  (:generator 13
    (with-fixed-allocation (y ndescr type size)
      (inst swc1 x y (- (* data vm:word-bytes) vm:other-pointer-type))
      (when double-p
	(inst swc1-odd x y (- (* (1+ data) vm:word-bytes)
			      vm:other-pointer-type))))))

(macrolet ((frob (name sc &rest args)
	     `(progn
		(define-vop (,name move-from-float)
		  (:args (x :scs (,sc) :to :save))
		  (:results (y :scs (descriptor-reg)))
		  (:variant ,@args))
		(define-move-vop ,name :move (,sc) (descriptor-reg)))))
  (frob move-from-single single-reg
    nil vm:single-float-size vm:single-float-type vm:single-float-value-slot)
  (frob move-from-double double-reg
    t vm:double-float-size vm:double-float-type vm:double-float-value-slot))

(macrolet ((frob (name sc double-p value)
	     `(progn
		(define-vop (,name)
		  (:args (x :scs (descriptor-reg)))
		  (:results (y :scs (,sc)))
		  (:note "pointer to float coercion")
		  (:generator 2
		    (inst lwc1 y x (- (* ,value vm:word-bytes)
				      vm:other-pointer-type))
		    ,@(when double-p
			`((inst lwc1-odd y x (- (* (1+ ,value) vm:word-bytes)
						vm:other-pointer-type))))
		    (inst nop)))
		(define-move-vop ,name :move (descriptor-reg) (,sc)))))
  (frob move-to-single single-reg nil vm:single-float-value-slot)
  (frob move-to-double double-reg t vm:double-float-value-slot))


(macrolet ((frob (name sc stack-sc format double-p)
	     `(progn
		(define-vop (,name)
		  (:args (x :scs (,sc) :target y)
			 (nfp :scs (any-reg)
			      :load-if (not (sc-is y ,sc))))
		  (:results (y))
		  (:note "float argument move")
		  (:generator ,(if double-p 2 1)
		    (sc-case y
		      (,sc
		       (unless (location= x y)
			 (inst move ,format y x)))
		      (,stack-sc
		       (let ((offset (* (tn-offset y) vm:word-bytes)))
			 (inst swc1 x nfp offset)
			 ,@(when double-p
			     '((inst swc1-odd x nfp
				     (+ offset vm:word-bytes)))))))))
		(define-move-vop ,name :move-argument
		  (,sc descriptor-reg) (,sc)))))
  (frob move-single-float-argument single-reg single-stack :single nil)
  (frob move-double-float-argument double-reg double-stack :double t))


(define-move-vop move-argument :move-argument
  (single-reg double-reg) (descriptor-reg))


;;;; Arithmetic VOPs:

(define-vop (float-op)
  (:args (x) (y))
  (:results (r))
  (:variant-vars format operation)
  (:policy :fast-safe)
  (:note "inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 0
    (note-this-location vop :internal-error)
    (inst float-op operation format r x y)))

(macrolet ((frob (name sc ptype)
	     `(define-vop (,name float-op)
		(:args (x :scs (,sc))
		       (y :scs (,sc)))
		(:results (r :scs (,sc)))
		(:arg-types ,ptype ,ptype)
		(:result-types ,ptype))))
  (frob single-float-op single-reg single-float)
  (frob double-float-op double-reg double-float))

(macrolet ((frob (op sname scost dname dcost)
	     `(progn
		(define-vop (,sname single-float-op)
		  (:translate ,op)
		  (:variant :single ',op)
		  (:variant-cost ,scost))
		(define-vop (,dname double-float-op)
		  (:translate ,op)
		  (:variant :double ',op)
		  (:variant-cost ,dcost)))))
  (frob + +/single-float 2 +/double-float 2)
  (frob - -/single-float 2 -/double-float 2)
  (frob * */single-float 4 */double-float 5)
  (frob / //single-float 12 //double-float 19))

(macrolet ((frob (name inst translate format sc type)
	     `(define-vop (,name)
		(:args (x :scs (,sc)))
		(:results (y :scs (,sc)))
		(:translate ,translate)
		(:policy :fast-safe)
		(:arg-types ,type)
		(:result-types ,type)
		(:note "inline float arithmetic")
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 1
		  (note-this-location vop :internal-error)
		  (inst ,inst ,format y x)))))
  (frob abs/single-float fabs abs :single single-reg single-float)
  (frob abs/double-float fabs abs :double double-reg double-float)
  (frob %negate/single-float fneg %negate :single single-reg single-float)
  (frob %negate/double-float fneg %negate :double double-reg double-float))


;;;; Comparison:

(define-vop (float-compare)
  (:args (x) (y))
  (:conditional)
  (:info target not-p)
  (:variant-vars format operation complement)
  (:policy :fast-safe)
  (:note "inline float comparison")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 3
    (note-this-location vop :internal-error)
    (inst fcmp operation format x y)
    (inst nop)
    (if (if complement (not not-p) not-p)
	(inst bc1f target)
	(inst bc1t target))
    (inst nop)))

(macrolet ((frob (name sc ptype)
	     `(define-vop (,name float-compare)
		(:args (x :scs (,sc))
		       (y :scs (,sc)))
		(:arg-types ,ptype ,ptype))))
  (frob single-float-compare single-reg single-float)
  (frob double-float-compare double-reg double-float))

(macrolet ((frob (translate op complement sname dname)
	     `(progn
		(define-vop (,sname single-float-compare)
		  (:translate ,translate)
		  (:variant :single ,op ,complement))
		(define-vop (,dname double-float-compare)
		  (:translate ,translate)
		  (:variant :double ,op ,complement)))))
  (frob < :lt nil </single-float </double-float)
  (frob > :ngt t >/single-float >/double-float)
  (frob eql :seq nil eql/single-float eql/double-float))


;;;; Conversion:

(macrolet ((frob (name translate
		       from-sc from-type from-format
		       to-sc to-type to-format)
	     (let ((word-p (eq from-format :word)))
	       `(define-vop (,name)
		  (:args (x :scs (,from-sc)))
		  (:results (y :scs (,to-sc)))
		  (:arg-types ,from-type)
		  (:result-types ,to-type)
		  (:policy :fast-safe)
		  (:note "inline float coercion")
		  (:translate ,translate)
		  (:vop-var vop)
		  (:save-p :compute-only)
		  (:generator ,(if word-p 3 2)
		    ,@(if word-p
			  `((inst mtc1 y x)
			    (inst nop)
			    (note-this-location vop :internal-error)
			    (inst fcvt ,to-format :word y y))
			  `((note-this-location vop :internal-error)
			    (inst fcvt ,to-format ,from-format y x))))))))
  (frob %single-float/signed %single-float
    signed-reg signed-num :word
    single-reg single-float :single)
  (frob %double-float/signed %double-float
    signed-reg signed-num :word
    double-reg double-float :double)
  (frob %single-float/double-float %single-float
    double-reg double-float :double
    single-reg single-float :single)
  (frob %double-float/single-float %double-float
    single-reg single-float :single
    double-reg double-float :double))


(macrolet ((frob (name from-sc from-type from-format)
	     `(define-vop (,name)
		(:args (x :scs (,from-sc)))
		(:results (y :scs (signed-reg)))
		(:temporary (:from (:argument 0) :sc ,from-sc) temp)
		(:arg-types ,from-type)
		(:result-types signed-num)
		(:translate %unary-round)
		(:policy :fast-safe)
		(:note "inline float round")
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 3
		  (note-this-location vop :internal-error)
		  (inst fcvt :word ,from-format temp x)
		  (inst mfc1 y temp)
		  (inst nop)))))
  (frob %unary-round/single-float single-reg single-float :single)
  (frob %unary-round/double-float double-reg double-float :double))


;;; These VOPs have to uninterruptibly frob the rounding mode in order to get
;;; the desired round-to-zero behavior.
;;;
(macrolet ((frob (name from-sc from-type from-format)
	     `(define-vop (,name)
		(:args (x :scs (,from-sc)))
		(:results (y :scs (signed-reg)))
		(:temporary (:from (:argument 0) :sc ,from-sc) temp)
		(:temporary (:sc non-descriptor-reg) status-save new-status)
		(:arg-types ,from-type)
		(:result-types signed-num)
		(:translate %unary-truncate)
		(:policy :fast-safe)
		(:note "inline float truncate")
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 16
		  (pseudo-atomic (status-save)
		    (inst cfc1 status-save 31)
		    (inst li new-status (lognot 3))
		    (inst and new-status status-save)
		    (inst or new-status float-round-to-zero)
		    (inst ctc1 new-status 31)
		    (inst nop)
		    (note-this-location vop :internal-error)
		    (inst fcvt :word ,from-format temp x)
		    (inst mfc1 y temp)
		    (inst nop)
		    (inst ctc1 status-save 31))))))
  (frob %unary-truncate/single-float single-reg single-float :single)
  (frob %unary-truncate/double-float double-reg double-float :double))


(define-vop (make-single-float)
  (:args (bits :scs (signed-reg)))
  (:results (res :scs (single-reg)))
  (:arg-types signed-num)
  (:result-types single-float)
  (:translate make-single-float)
  (:policy :fast-safe)
  (:generator 2
    (inst mtc1 res bits)
    (inst nop)))

(define-vop (make-double-float)
  (:args (hi-bits :scs (signed-reg))
	 (lo-bits :scs (unsigned-reg)))
  (:results (res :scs (double-reg)))
  (:arg-types signed-num unsigned-num)
  (:result-types double-float)
  (:translate make-double-float)
  (:policy :fast-safe)
  (:generator 2
    (inst mtc1 res lo-bits)
    (inst mtc1-odd res hi-bits)
    (inst nop)))

(define-vop (single-float-bits)
  (:args (float :scs (single-reg)))
  (:results (bits :scs (signed-reg)))
  (:arg-types single-float)
  (:result-types signed-num)
  (:translate single-float-bits)
  (:policy :fast-safe)
  (:generator 2
    (inst mfc1 bits float)
    (inst nop)))

(define-vop (double-float-high-bits)
  (:args (float :scs (double-reg)))
  (:results (hi-bits :scs (signed-reg)))
  (:arg-types double-float)
  (:result-types signed-num)
  (:translate double-float-high-bits)
  (:policy :fast-safe)
  (:generator 2
    (inst mfc1-odd hi-bits float)
    (inst nop)))

(define-vop (double-float-low-bits)
  (:args (float :scs (double-reg)))
  (:results (lo-bits :scs (unsigned-reg)))
  (:arg-types double-float)
  (:result-types unsigned-num)
  (:translate double-float-low-bits)
  (:policy :fast-safe)
  (:generator 2
    (inst mfc1 lo-bits float)
    (inst nop)))


;;;; SAP accessors/setters

(define-vop (sap-ref-single sap-ref)
  (:translate sap-ref-single)
  (:results (result :scs (single-reg)))
  (:result-types single-float)
  (:variant :single nil))

(define-vop (sap-set-single sap-set)
  (:translate %set-sap-ref-single)
  (:args (object :scs (sap-reg) :target sap)
	 (offset :scs (any-reg negative-immediate zero immediate))
	 (value :scs (single-reg) :target result))
  (:arg-types system-area-pointer positive-fixnum single-float)
  (:results (result :scs (single-reg)))
  (:result-types single-float)
  (:variant :single))

(define-vop (sap-ref-double sap-ref)
  (:translate sap-ref-double)
  (:results (result :scs (double-reg)))
  (:result-types double-float)
  (:variant :double nil))

(define-vop (sap-set-double sap-set)
  (:translate %set-sap-ref-double)
  (:args (object :scs (sap-reg) :target sap)
	 (offset :scs (any-reg negative-immediate zero immediate))
	 (value :scs (double-reg) :target result))
  (:arg-types system-area-pointer positive-fixnum double-float)
  (:results (result :scs (double-reg)))
  (:result-types double-float)
  (:variant :double))


;;;; Float mode hackery:

(deftype float-modes () '(unsigned-byte 24))
(defknown floating-point-modes () float-modes (flushable))
(defknown ((setf floating-point-modes)) (float-modes)
  float-modes)

(define-vop (floating-point-modes)
  (:results (res :scs (unsigned-reg)))
  (:result-types unsigned-num)
  (:translate floating-point-modes)
  (:policy :fast-safe)
  (:generator 3
    (inst cfc1 res 31)
    (inst nop)))

(define-vop (set-floating-point-modes)
  (:args (new :scs (unsigned-reg) :target res))
  (:results (res :scs (unsigned-reg)))
  (:arg-types unsigned-num)
  (:result-types unsigned-num)
  (:translate (setf floating-point-modes))
  (:policy :fast-safe)
  (:generator 3
    (inst ctc1 res 31)
    (move res new)))
