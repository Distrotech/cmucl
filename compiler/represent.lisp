;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;;    This file contains the implementation independent code for the
;;; representation selection phase in the compiler.  Representation selection
;;; decides whether to use non-descriptor representations for objects and emits
;;; the appropriate representation-specific move and coerce vops.
;;;
;;; Written by Rob MacLachlan
;;;
(in-package 'c)


;;;; Error routines:
;;;
;;;    Problems in the VM definition often show up here, so we try to be as
;;; implementor-friendly as possible.
;;;

;;; GET-OPERAND-INFO  --  Interface
;;;
;;;    Given a TN ref for a VOP argument or result, return these values:
;;; 1] True if the operand is an argument, false otherwise.
;;; 2] The ordinal position of the operand.
;;; 3] True if the operand is a more operand, false otherwise.
;;; 4] The costs for this operand.
;;; 5] The load-scs vector for this operand (NIL if more-p.)
;;; 6] True if the costs or SCs in the VOP-INFO are inconsistent with the
;;;    currently record ones.
;;;
(defun get-operand-info (ref)
  (declare (type tn-ref ref))
  (let* ((arg-p (not (tn-ref-write-p ref)))
	 (vop (tn-ref-vop ref))
	 (info (vop-info vop)))
    (flet ((frob (refs costs load more-cost)
	     (do ((refs refs (tn-ref-across refs))
		  (costs costs (cdr costs))
		  (load load (cdr load))
		  (n 0 (1+ n)))
		 ((null costs)
		  (assert more-cost)
		  (values arg-p
			  (+ n (position-in #'tn-ref-across ref refs) 1)
			  t
			  more-cost
			  nil
			  nil))
	       (when (eq refs ref)
		 (let ((parse (vop-parse-or-lose (vop-info-name info))))
		   (multiple-value-bind
		       (ccosts cscs)
		       (compute-loading-costs
			(elt (if arg-p
				 (vop-parse-args parse)
				 (vop-parse-results parse))
			     n)
			arg-p)
		     
		     (return
		      (values arg-p
			      (1+ n)
			      nil
			      (car costs)
			      (car load)
			      (not (and (equalp ccosts (car costs))
					(equalp cscs (car load))))))))))))
      (if arg-p
	  (frob (vop-args vop) (vop-info-arg-costs info)
	        (vop-info-arg-load-scs info)
	        (vop-info-more-arg-costs info))
	  (frob (vop-results vop) (vop-info-result-costs info)
	        (vop-info-result-load-scs info)
	        (vop-info-more-result-costs info))))))


;;; LISTIFY-RESTRICTIONS  --  Interface
;;;
;;;    Convert a load-costs vector to the list of SCs allowed by the operand
;;; restriction.
;;;
(defun listify-restrictions (restr)
  (declare (type sc-vector restr))
  (collect ((res))
    (dotimes (i sc-number-limit)
      (when (eq (svref restr i) t)
	(res (svref (backend-sc-numbers *backend*) i))))
    (res)))

    
;;; BAD-COSTS-ERROR  --  Internal
;;;
;;;    Try to give a helpful error message when Ref has no cost specified for
;;; some SC allowed by the TN's primitive-type.
;;;
(defun bad-costs-error (ref)
  (declare (type tn-ref ref))
  (let* ((tn (tn-ref-tn ref))
	 (ptype (tn-primitive-type tn)))
    (multiple-value-bind (arg-p pos more-p costs load-scs incon)
			 (get-operand-info ref)
      (collect ((losers))
	(dolist (scn (primitive-type-scs ptype))
	  (unless (svref costs scn)
	    (losers (svref (backend-sc-numbers *backend*) scn))))

	(unless (losers)
	  (error "Representation selection flamed out for no obvious reason.~@
	          Try again after recompiling the VM definition."))
	
	(error "~S is not valid as the ~:R ~:[result~;argument~] to the~@
	        ~S VOP, since the TN's primitive type ~S allows SCs:~%  ~S~@
		~:[which cannot be coerced or loaded into the allowed SCs:~
		~%  ~S~;~*~]~:[~;~@
		Current cost info inconsistent with that in effect at compile ~
		time.  Recompile.~%Compilation order may be incorrect.~]"
	       tn pos arg-p
	       (template-name (vop-info (tn-ref-vop ref)))
	       (primitive-type-name ptype)
	       (mapcar #'sc-name (losers))
	       more-p
	       (mapcar #'sc-name (listify-restrictions load-scs))
	       incon)))))


;;; BAD-COERCE-ERROR  --  Internal
;;;
;;;    Try to give a helpful error message when we fail to do a coercion
;;; for some reason.
;;;
(defun bad-coerce-error (op)
  (declare (type tn-ref op))
  (let* ((op-tn (tn-ref-tn op))
	 (op-sc (tn-sc op-tn))
	 (op-scn (sc-number op-sc))
	 (ptype (tn-primitive-type op-tn))
	 (write-p (tn-ref-write-p op)))
    (multiple-value-bind (arg-p pos more-p costs load-scs incon)
			 (get-operand-info op)
      (declare (ignore costs more-p))
      (collect ((load-lose)
		(no-move-scs)
		(move-lose))
	(dotimes (i sc-number-limit)
	  (let ((i-sc (svref (backend-sc-numbers *backend*) i)))
	    (when (eq (svref load-scs i) t)
	      (cond ((not (sc-allowed-by-primitive-type i-sc ptype))
		     (load-lose i-sc))
		    ((not (find-move-vop op-tn write-p i-sc ptype
					 #'sc-move-vops))
		     (let ((vops (if write-p
				     (svref (sc-move-vops op-sc) i)
				     (svref (sc-move-vops i-sc) op-scn))))
		       (if vops
			   (dolist (vop vops) (move-lose (template-name vop)))
			   (no-move-scs i-sc))))
		    (t
		     (error "Representation selection flamed out for no ~
		             obvious reason."))))))
	
	(unless (or (load-lose) (no-move-scs) (move-lose))
	  (error "Representation selection flamed out for no obvious reason.~@
	          Try again after recompiling the VM definition."))

	(error "~S is not valid as the ~:R ~:[result~;argument~] to VOP:~
	        ~%  ~S~%Primitive type: ~S~@
		SC restrictions:~%  ~S~@
		~@[The primitive type disallows these loadable SCs:~%  ~S~%~]~
		~@[No move VOPs are defined to coerce to these allowed SCs:~
		~%  ~S~%~]~
		~@[These move VOPs couldn't be used due to operand type ~
		restrictions:~%  ~S~%~]~
		~:[~;~@
		Current cost info inconsistent with that in effect at compile ~
		time.  Recompile.~%Compilation order may be incorrect.~]"
	       op-tn pos arg-p
	       (template-name (vop-info (tn-ref-vop op)))
	       (primitive-type-name ptype)
	       (mapcar #'sc-name (listify-restrictions load-scs))
	       (mapcar #'sc-name (load-lose))
	       (mapcar #'sc-name (no-move-scs))
	       (move-lose)
	       incon)))))


;;; BAD-MOVE-ARG-ERROR  --  Internal
;;;
(defun bad-move-arg-error (val pass)
  (declare (type tn val pass))
  (error "No :MOVE-ARGUMENT VOP defined to move ~S (SC ~S) to ~
          ~S (SC ~S.)"
	 val (sc-name (tn-sc val))
	 pass (sc-name (tn-sc pass))))


;;;; VM Consistency Checking:
;;;
;;;    We do some checking of the consistency of the VM definition at load
;;; time.

;;; CHECK-MOVE-FUNCTION-CONSISTENCY  --  Interface
;;;
(defun check-move-function-consistency ()
  (dotimes (i sc-number-limit)
    (let ((sc (svref (backend-sc-numbers *backend*) i)))
      (when sc
	(let ((moves (sc-move-functions sc)))
	  (dolist (const (sc-constant-scs sc))
	    (unless (svref moves (sc-number const))
	      (error "No move function defined to load SC ~S from constant ~
	              SC ~S."
		     (sc-name sc) (sc-name const))))

	  (dolist (alt (sc-alternate-scs sc))
	    (unless (svref moves (sc-number alt))
	      (error "No move function defined to load SC ~S from alternate ~
	              SC ~S."
		     (sc-name sc) (sc-name alt)))
	    (unless (svref (sc-move-functions alt) i)
	      (error "No move function defined to save SC ~S to alternate ~
	              SC ~S."
		     (sc-name sc) (sc-name alt)))))))))
;;;
(check-move-function-consistency)


;;; SELECT-TN-REPRESENTATION  --  Internal
;;;
;;;    Return the best representation for a normal TN.  SCs is a list of the SC
;;; numbers of the SCs to select from.  Costs is a scratch vector.
;;;
;;;     What we do is sum the costs for each reference to TN in each of the
;;; SCs, and then return the SC having the lowest cost.  We ignore references
;;; by the MOVE VOP, since counting them would spuriously encourage descriptor
;;; representations.  We won't actually need to coerce to descriptor and back,
;;; since we will replace the MOVE with a specialized move VOP.
;;;
(defun select-tn-representation (tn scs costs)
  (declare (type tn tn) (type sc-vector costs))
  (dolist (scn scs)
    (setf (svref costs scn) 0))
  
  (macrolet ((scan-refs (refs ops-slot costs-slot more-costs-slot)
	       `(do ((ref ,refs (tn-ref-next ref)))
		    ((null ref))
		  (let* ((vop (tn-ref-vop ref))
			 (info (vop-info vop)))
		    (unless (eq (vop-info-name info) 'move)
		      (do ((cost (,costs-slot info) (cdr cost))
			   (op (,ops-slot vop) (tn-ref-across op)))
			  ((null cost)
			   (add-costs (,more-costs-slot info)))
			(when (eq op ref)
			  (add-costs (car cost))
			  (return)))))))
	     (add-costs (cost)
	       `(let ((cost ,cost))
		  (dolist (scn scs)
		    (let ((res (svref cost scn)))
		      (unless res
			(bad-costs-error ref))
		      (incf (svref costs scn) res))))))
    
    (scan-refs (tn-reads tn) vop-args vop-info-arg-costs
	       vop-info-more-arg-costs)
    (scan-refs (tn-writes tn) vop-results vop-info-result-costs
	       vop-info-more-result-costs))
  
  (let ((min most-positive-fixnum)
	(min-scn nil))
    (dolist (scn scs)
      (let ((cost (svref costs scn)))
	(when (< cost min)
	  (setq min cost)
	  (setq min-scn scn))))
    
    (svref (backend-sc-numbers *backend*) min-scn)))


;;; NOTE-NUMBER-STACK-TN  --  Internal
;;;
;;;    Prepare for the possibility of a TN being allocated on the number stack
;;; by setting NUMBER-STACK-P in all functions that TN is referenced in and in
;;; all the functions in their tail sets.  Refs is a TN-Refs list of references
;;; to the TN.
;;;
(defun note-number-stack-tn (refs)
  (declare (type (or tn-ref null) refs))
  
  (do ((ref refs (tn-ref-next ref)))
      ((null ref))
    (let* ((lambda (block-home-lambda
		    (ir2-block-block
		     (vop-block (tn-ref-vop ref)))))
	   (tails (lambda-tail-set lambda)))
      (flet ((frob (fun)
	       (setf (ir2-environment-number-stack-p
		      (environment-info
		       (lambda-environment fun)))
		     t)))
	(frob lambda)
	(when tails
	  (dolist (fun (tail-set-functions tails))
	    (frob fun))))))

  (undefined-value))


;;; GET-OPERAND-NAME  --  Internal
;;;
;;;    If TN is a variable, return the name.  If TN is used by a VOP emitted
;;; for a return, then return a string indicating this.  Otherwise, return NIL.
;;;
(defun get-operand-name (tn arg-p)
  (declare (type tn tn))
  (let* ((actual (if (eq (tn-kind tn) :alias) (tn-save-tn tn) tn))
	 (reads (tn-reads tn))
	 (leaf (tn-leaf actual)))
    (cond ((lambda-var-p leaf) (leaf-name leaf))
	  ((and (not arg-p) reads
		(return-p (vop-node (tn-ref-vop reads))))
	   "<return value>")
	  (t
	   nil))))


;;; DO-COERCE-EFFICENCY-NOTE  --  Internal
;;;
;;;    If policy indicates, give an efficency note for doing the a coercion
;;; Vop, where Op is the operand we are coercing for and Dest-TN is the
;;; distinct destination in a move.
;;;
(defun do-coerce-efficency-note (vop op dest-tn)
  (declare (type vop-info vop) (type tn-ref op) (type (or tn null) dest-tn))
  (let* ((note (or (template-note vop) (template-name vop)))
	 (cost (template-cost vop))
	 (op-vop (tn-ref-vop op))
	 (op-node (vop-node op-vop))
	 (op-tn (tn-ref-tn op))
	 (*compiler-error-context* op-node))
    (cond ((eq (tn-kind op-tn) :constant))
	  ((policy op-node (<= speed brevity) (<= space brevity)))
	  ((null dest-tn)
	   (let* ((op-info (vop-info op-vop))
		  (op-note (or (template-note op-info)
			       (template-name op-info)))
		  (arg-p (not (tn-ref-write-p op)))
		  (name (get-operand-name op-tn arg-p)))
	     (multiple-value-bind (ignore pos)
				  (get-operand-info op)
	       (declare (ignore ignore))
	       (compiler-note
		"Doing ~A (cost ~D)~:[~2*~; ~:[to~;from~] ~S~], for:~%~6T~
		The ~:R ~:[result~;argument~] of ~A."
		note cost name arg-p name
		pos arg-p op-note))))
	  (t
	   (compiler-note "Doing ~A (cost ~D)~@[ from ~S~]~@[ to ~S~]."
			  note cost (get-operand-name op-tn t)
			  (get-operand-name dest-tn nil)))))
  (undefined-value))


;;; FIND-MOVE-VOP  --  Internal
;;;
;;;    Find a move VOP to move from the operand OP-TN to some other
;;; representation corresponding to OTHER-SC and OTHER-PTYPE.  Slot is the SC
;;; slot that we grab from (move or move-argument).  Write-P indicates that OP
;;; is a VOP result, so OP is the move result and other is the arg, otherwise
;;; OP is the arg and other is the result.
;;;
;;;    If an operand is of primitive type T, then we use the type of the other
;;; operand instead, effectively intersecting the argument and result type
;;; assertions.  This way, a move VOP can restrict whichever operand makes more
;;; sense, without worrying about which operand has the type info.
;;;
(defun find-move-vop (op-tn write-p other-sc other-ptype slot)
  (declare (type tn op-tn) (type sc other-sc)
	   (type primitive-type other-ptype)
	   (type function slot))
  (let* ((op-sc (tn-sc op-tn))
	 (op-scn (sc-number op-sc))
	 (other-scn (sc-number other-sc))
	 (any-ptype (backend-any-primitive-type *backend*))
	 (op-ptype (tn-primitive-type op-tn)))
    (dolist (info (if write-p
		      (svref (funcall slot op-sc) other-scn)
		      (svref (funcall slot other-sc) op-scn))
		  nil)
      (when (and (operand-restriction-ok
		  (first (template-arg-types info))
		  (if (or write-p (eq op-ptype any-ptype))
		      other-ptype op-ptype)
		  :tn op-tn :t-ok nil)
		 (operand-restriction-ok
		  (first (template-result-types info))
		  (if (or write-p (eq other-ptype any-ptype))
		      op-ptype other-ptype)
		  :t-ok nil))
	(return info)))))

	
;;; EMIT-COERCE-VOP  --  Internal
;;;
;;;    Emit a coercion VOP for Op Before the specifed VOP or die trying.  SCS
;;; is the operand's LOAD-SCS vector, which we use to determine what SCs the
;;; VOP will accept.  We pick any acceptable coerce VOP, since it practice it
;;; seems uninteresting to have more than one applicable.
;;;
;;;    What we do is look at each SC allowed by both the operand restriction
;;; and the operand primitive-type, and see if there is a move VOP which moves
;;; between the operand's SC and load SC.  If we find such a VOP, then we make
;;; a TN having the load SC as the representation.
;;;
;;;    Dest-TN is the TN that we are moving to, for a move or move-arg.  This
;;; is only for efficiency notes.
;;;
;;;    If the TN is an unused result TN, then we don't actually emit the move;
;;; we just change to the right kind of TN.
;;;
(defun emit-coerce-vop (op dest-tn scs before)
  (declare (type tn-ref op) (type sc-vector scs) (type (or vop null) before)
	   (type (or tn null) dest-tn))
  (let* ((op-tn (tn-ref-tn op))
	 (ptype (tn-primitive-type op-tn))
	 (write-p (tn-ref-write-p op))
	 (vop (tn-ref-vop op))
	 (node (vop-node vop))
	 (block (vop-block vop)))
    (dotimes (i sc-number-limit (bad-coerce-error op))
      (let ((i-sc (svref (backend-sc-numbers *backend*) i)))
	(when (and (eq (svref scs i) t)
		   (sc-allowed-by-primitive-type i-sc ptype))
	  (let ((res (find-move-vop op-tn write-p i-sc ptype #'sc-move-vops)))
	    (when res
	      (when (>= (vop-info-cost res) *efficency-note-cost-threshold*)
		(do-coerce-efficency-note res op dest-tn))
	      (let ((temp (make-representation-tn ptype i)))
		(change-tn-ref-tn op temp)
		(cond
		 ((not write-p)
		  (emit-move-template node block res op-tn temp before))
		 ((and (null (tn-reads op-tn))
		       (eq (tn-kind op-tn) :normal)))
		 (t
		  (emit-move-template node block res temp op-tn before))))
	      (return))))))))


;;; COERCE-SOME-OPERANDS  --  Internal
;;;
;;;    Scan some operands and call EMIT-COERCE-VOP on any for which we can't
;;; load the operand.  The coerce VOP is inserted Before the specified VOP.
;;; Dest-TN is the destination TN if we are doing a move or move-arg, and is
;;; NIL otherwise.  This is only used for efficency notes.
;;;
(proclaim '(inline coerce-some-operands))
(defun coerce-some-operands (ops dest-tn load-scs before)
  (declare (type (or tn-ref null) ops) (list load-scs)
	   (type (or tn null) dest-tn) (type (or vop null) before))
  (do ((op ops (tn-ref-across op))
       (scs load-scs (cdr scs)))
      ((null scs))
    (unless (svref (car scs)
		   (sc-number (tn-sc (tn-ref-tn op))))
      (emit-coerce-vop op dest-tn (car scs) before)))
  (undefined-value))


;;; COERCE-VOP-OPERANDS  --  Internal
;;;
;;;    Emit coerce VOPs for the args and results, as needed.
;;;
(defun coerce-vop-operands (vop)
  (declare (type vop vop))
  (let ((info (vop-info vop)))
    (coerce-some-operands (vop-args vop) nil (vop-info-arg-load-scs info) vop)
    (coerce-some-operands (vop-results vop) nil (vop-info-result-load-scs info)
			  (vop-next vop)))
  (undefined-value))


;;; EMIT-ARG-MOVES  --  Internal
;;;
;;;    Iterate over the more operands to a call VOP, emitting move-arg VOPs and
;;; any necessary coercions.  We determine which FP to use by looking at the
;;; MOVE-ARGS annotation.
;;;
(defun emit-arg-moves (vop)
  (let* ((info (vop-info vop))
	 (node (vop-node vop))
	 (block (vop-block vop))
	 (how (vop-info-move-args info))
	 (args (vop-args vop))
	 (fp-tn (tn-ref-tn args))
	 (nfp-tn (if (eq how :local-call)
		     (tn-ref-tn (tn-ref-across args))
		     nil))
	 (pass-locs (first (vop-codegen-info vop)))
	 (prev (vop-prev vop)))
    (do ((val (do ((arg args (tn-ref-across arg))
		   (req (template-arg-types info) (cdr req)))
		  ((null req) arg))
	      (tn-ref-across val))
	 (pass pass-locs (cdr pass)))
	((null val)
	 (assert (null pass)))
      (let* ((val-tn (tn-ref-tn val))
	     (pass-tn (first pass))
	     (pass-sc (tn-sc pass-tn))
	     (res (find-move-vop val-tn nil pass-sc
				 (tn-primitive-type pass-tn)
				 #'sc-move-arg-vops)))
	(unless res
	  (bad-move-arg-error val-tn pass-tn))
	
	(change-tn-ref-tn val pass-tn)
	(let* ((this-fp
		(cond ((not (sc-number-stack-p pass-sc)) fp-tn)
		      (nfp-tn)
		      (t
		       (assert (eq how :known-return))
		       (setq nfp-tn (make-number-stack-pointer-tn))
		       (setf (tn-sc nfp-tn)
			     (svref (backend-sc-numbers *backend*)
				    (first (primitive-type-scs
					    (tn-primitive-type nfp-tn)))))
		       (emit-context-template
			node block
			(template-or-lose 'compute-old-nfp)
			nfp-tn vop)
		       (assert (not (sc-number-stack-p (tn-sc nfp-tn))))
		       nfp-tn)))
	       (new (emit-move-arg-template node block res val-tn this-fp
					    pass-tn vop)))
	  (coerce-some-operands (vop-args new) pass-tn
				(vop-info-arg-load-scs res)
				(if prev
				    (vop-next prev)
				    (ir2-block-start-vop block)))))))
  (undefined-value))


;;; EMIT-MOVES-AND-COERCIONS  --  Internal
;;;
;;;    Scan the IR2 looking for move operations that need to be replaced with
;;; special-case VOPs and emitting coercion VOPs for operands of normal VOPs.
;;; We delete moves to TNs that are never read at this point, rather than
;;; possibly converting them to some expensive move operation.
;;;
(defun emit-moves-and-coercions (block)
  (declare (type ir2-block block))
  (do ((vop (ir2-block-start-vop block)
	    (vop-next vop)))
      ((null vop))
    (let ((info (vop-info vop))
	  (node (vop-node vop))
	  (block (vop-block vop)))
      (cond
       ((eq (vop-info-name info) 'move)
	(let* ((args (vop-args vop))
	       (x (tn-ref-tn args))
	       (y (tn-ref-tn (vop-results vop)))
	       (res (find-move-vop x nil (tn-sc y) (tn-primitive-type y)
				   #'sc-move-vops)))
	  (cond ((and (null (tn-reads y))
		      (eq (tn-kind y) :normal))
		 (delete-vop vop))
		((eq res info))
		(res
		 (when (>= (vop-info-cost res) *efficency-note-cost-threshold*)
		   (do-coerce-efficency-note res args y))
		 (emit-move-template node block res x y vop)
		 (delete-vop vop))
		(t
		 (coerce-vop-operands vop)))))
       ((vop-info-move-args info)
	(emit-arg-moves vop))
       (t
	(coerce-vop-operands vop))))))


;;; NOTE-IF-NUMBER-STACK  --  Internal
;;;
;;;    If TN is in a number stack SC, make all the right annotations.  Note
;;; that this should be called after TN has been referenced, since it must
;;; iterate over the referencing environments.
;;;
(proclaim '(inline note-if-number-stack))
(defun note-if-number-stack (tn 2comp restricted)
  (declare (type tn tn) (type ir2-component 2comp))
  (when (if restricted
	    (eq (sb-name (sc-sb (tn-sc tn))) 'non-descriptor-stack)
	    (sc-number-stack-p (tn-sc tn)))
    (unless (ir2-component-nfp 2comp)
      (setf (ir2-component-nfp 2comp) (make-nfp-tn)))
    (note-number-stack-tn (tn-reads tn))
    (note-number-stack-tn (tn-writes tn)))
  (undefined-value))


;;; SELECT-REPRESENTATIONS  --  Interface
;;;
;;;    Entry to representation selection.  First we select the representation
;;; for all normal TNs, setting the TN-SC.  After selecting the TN
;;; representations, we set the SC for all :ALIAS TNs to be the representation
;;; chosen for the original TN.  We then scan all the IR2, emitting any
;;; necessary coerce and move-arg VOPs.  Finally, we scan all TNs looking for
;;; ones that might be placed on the number stack, noting this so that the
;;; number-FP can be allocated.  This must be done last, since references in
;;; new environments may be introduced by MOVE-ARG insertion.
;;;
(defun select-representations (component)
  (let ((costs (make-array sc-number-limit))
	(2comp (component-info component)))
	        
    (do ((tn (ir2-component-normal-tns 2comp)
	     (tn-next tn)))
	((null tn))
      (assert (tn-primitive-type tn))
      (unless (tn-sc tn)
	(let* ((scs (primitive-type-scs (tn-primitive-type tn)))
	       (sc (if (rest scs)
		       (select-tn-representation tn scs costs)
		       (svref (backend-sc-numbers *backend*) (first scs)))))
	  (assert sc)
	  (setf (tn-sc tn) sc))))

    (do ((alias (ir2-component-alias-tns 2comp)
		(tn-next alias)))
	((null alias))
      (setf (tn-sc alias) (tn-sc (tn-save-tn alias))))

    (do-ir2-blocks (block component)
      (emit-moves-and-coercions block))
    
    (macrolet ((frob (slot restricted)
		 `(do ((tn (,slot 2comp) (tn-next tn)))
		      ((null tn))
		    (note-if-number-stack tn 2comp ,restricted))))
      (frob ir2-component-normal-tns nil)
      (frob ir2-component-wired-tns t)
      (frob ir2-component-restricted-tns t)))

  (undefined-value))
