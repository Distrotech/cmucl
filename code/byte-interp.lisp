;;; -*- Package: C -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/byte-interp.lisp,v 1.3 1992/09/07 16:10:36 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains the noise to interpret byte-compiled stuff.
;;;
;;; Written by William Lott
;;;

(in-package "C")



;;;; Types.

(deftype stack-pointer ()
  `(integer 0 ,(1- most-positive-fixnum)))

(defconstant max-pc (1- (ash 1 24)))

(deftype pc ()
  `(integer 0 ,max-pc))

(deftype return-pc ()
  `(integer ,(- max-pc) ,max-pc))



;;;; The stack.

(declaim (inline current-stack-pointer))
(defun current-stack-pointer ()
  (declare (values stack-pointer))
  *eval-stack-top*)

(declaim (inline (setf current-stack-pointer)))
(defun (setf current-stack-pointer) (new-value)
  (declare (type stack-pointer new-value)
	   (values stack-pointer))
  (setf *eval-stack-top* new-value))

(declaim (inline eval-stack-ref))
(defun eval-stack-ref (offset)
  (declare (type stack-pointer offset))
  (svref eval::*eval-stack* offset))

(declaim (inline (setf eval-stack-ref)))
(defun (setf eval-stack-ref) (new-value offset)
  (declare (type stack-pointer offset))
  (setf (svref eval::*eval-stack* offset) new-value))

(defun push-eval-stack (value)
  (let ((len (length (the simple-vector eval::*eval-stack*)))
	(sp (current-stack-pointer)))
    (when (= len sp)
      (let ((new-stack (make-array (ash len 1))))
	(replace new-stack eval::*eval-stack* :end1 len :end2 len)
	(setf eval::*eval-stack* new-stack)))
    (setf (current-stack-pointer) (1+ sp))
    (setf (eval-stack-ref sp) value)))

(defun pop-eval-stack ()
  (let* ((new-sp (1- (current-stack-pointer)))
	 (value (eval-stack-ref new-sp)))
    (setf (current-stack-pointer) new-sp)
    value))

(defmacro multiple-value-pop-eval-stack ((&rest vars) &body body)
  (declare (optimize (inhibit-warnings 3)))
  (let ((num-vars (length vars))
	(index -1)
	(new-sp-var (gensym "NEW-SP-"))
	(decls nil))
    (loop
      (unless (and (consp body) (consp (car body)) (eq (caar body) 'declare))
	(return))
      (push (pop body) decls))
    `(let ((,new-sp-var (- (current-stack-pointer) ,num-vars)))
       (declare (type stack-pointer ,new-sp-var))
       (let ,(mapcar #'(lambda (var)
			 `(,var (eval-stack-ref
				 (+ ,new-sp-var ,(incf index)))))
		     vars)
	 ,@(nreverse decls)
	 (setf (current-stack-pointer) ,new-sp-var)
	 ,@body))))

(defun stack-copy (dest src count)
  (declare (type stack-pointer dest src count))
  (dotimes (i count)
    (setf (eval-stack-ref dest) (eval-stack-ref src))
    (incf dest)
    (incf src)))



;;;; Component access magic.

(declaim (inline component-ref))
(defun component-ref (component pc)
  (declare (type code-component component)
	   (type pc pc))
  (system:sap-ref-8 (code-instructions component) pc))

(declaim (inline (setf component-ref)))
(defun (setf component-ref) (value component pc)
  (declare (type (unsigned-byte 8) value)
	   (type code-component component)
	   (type pc pc))
  (setf (system:sap-ref-8 (code-instructions component) pc) value))

(declaim (inline component-ref-signed))
(defun component-ref-signed (component pc)
  (let ((byte (component-ref component pc)))
    (if (logbitp 7 byte)
	(logior (ash -1 8) byte)
	byte)))

(declaim (inline component-ref-24))
(defun component-ref-24 (component pc)
  (logior (ash (component-ref component pc) 16)
	  (ash (component-ref component (1+ pc)) 8)
	  (component-ref component (+ pc 2))))


;;;; Debugging support.

;;; WITH-DEBUGGER-INFO -- internal.
;;;
;;; This macro binds three magic variables.  When the debugger notices that
;;; these three variables are bound, it makes a byte-code frame out of the
;;; supplied information instead of a compiled frame.  We set each var in
;;; addition to binding it so the compiler doens't optimize away the binding.
;;;
(defmacro with-debugger-info ((component pc fp) &body body)
  `(let ((%byte-interp-component ,component)
	 (%byte-interp-pc ,pc)
	 (%byte-interp-fp ,fp))
     (declare (optimize (debug 3)))
     (setf %byte-interp-component %byte-interp-component)
     (setf %byte-interp-pc %byte-interp-pc)
     (setf %byte-interp-fp %byte-interp-fp)
     ,@body))


(defun byte-install-breakpoint (component pc)
  (declare (type code-component component)
	   (type pc pc)
	   (values (unsigned-byte 8)))
  (let ((orig (component-ref component pc)))
    (setf (component-ref component pc)
	  #.(logior byte-xop
		    (xop-index-or-lose 'breakpoint)))
    orig))

(defun byte-remove-breakpoint (component pc orig)
  (declare (type code-component component)
	   (type pc pc)
	   (type (unsigned-byte 8) orig)
	   (values (unsigned-byte 8)))
  (setf (component-ref component pc) orig))

(defun byte-skip-breakpoint (component pc fp orig)
  (declare (type code-component component)
	   (type pc pc)
	   (type stack-pointer fp)
	   (type (unsigned-byte 8) orig))
  (byte-interpret-byte component fp pc orig))




;;;; System constants

;;; We don't just use *system-constants* directly because we want to be
;;; able to change it in the compiler without breaking the running
;;; byte interpreter.
;;;
(defconstant system-constants #.*system-constants*)



;;;; Byte compiled function constructors/extractors.

(defun make-byte-compiled-function (xep)
  (declare (type byte-xep xep))
  (set-function-subtype
   #'(lambda (&rest args)
       (let ((old-sp (current-stack-pointer))
	     (num-args (length args)))
	 (declare (type stack-pointer old-sp))
	 (dolist (arg args)
	   (push-eval-stack arg))
	 (invoke-xep nil 0 old-sp 0 num-args xep)))
   vm:byte-code-function-type))

(defun byte-compiled-function-xep (function)
  (declare (type function function)
	   (values byte-xep))
  (or (system:find-if-in-closure #'byte-xep-p function)
      (error "Couldn't find the XEP in ~S" function)))

(defun make-byte-compiled-closure (xep closure-vars)
  (declare (type byte-xep xep)
	   (type simple-vector closure-vars))
  (set-function-subtype
   #'(lambda (&rest args)
       (let ((old-sp (current-stack-pointer))
	     (num-args (length args)))
	 (declare (type stack-pointer old-sp))
	 (dolist (arg args)
	   (push-eval-stack arg))
	 (invoke-xep nil 0 old-sp 0 num-args xep closure-vars)))
   vm:byte-code-closure-type))

(defun byte-compiled-closure-xep (closure)
  (declare (type function closure)
	   (values byte-xep))
  (or (system:find-if-in-closure #'byte-xep-p closure)
      (error "Couldn't find the XEP in ~S" closure)))

(defun byte-compiled-closure-closure-vars (closure)
  (declare (type function closure)
	   (values simple-vector))
  (or (system:find-if-in-closure #'simple-vector-p closure)
      (error "Couldn't find the closure vars in ~S" closure)))

(defun set-function-subtype (function subtype)
  (setf (function-subtype function) subtype)
  function)



;;;; Inlines.

(defmacro expand-into-inlines ()
  (declare (optimize (inhibit-warnings 3)))
  (labels ((build-dispatch (bit base)
	     (if (minusp bit)
		 (let ((info (nth base *inline-functions*)))
		   (if info
		       (let* ((spec (type-specifier
				     (inline-function-info-type info)))
			      (arg-types (second spec))
			      (result-type (third spec))
			      (args (mapcar #'(lambda (x)
						(declare (ignore x))
						(gensym))
					    arg-types))
			      (func
			       `(the ,result-type
				     (,(inline-function-info-function info)
				      ,@args))))
			 `(multiple-value-pop-eval-stack ,args
			    (declare ,@(mapcar #'(lambda (type var)
						   `(type ,type ,var))
					       arg-types args))
			    ,(if (and (consp result-type)
				      (eq (car result-type) 'values))
				 (let ((results
					(mapcar #'(lambda (x)
						    (declare (ignore x))
						    (gensym))
						(cdr result-type))))
				   `(multiple-value-bind
					,results ,func
				      ,@(mapcar #'(lambda (res)
						    `(push-eval-stack ,res))
						results)))
				 `(push-eval-stack ,func))))
		       `(error "Unknown inline function, id=~D" ,base)))
		 `(if (zerop (logand byte ,(ash 1 bit)))
		      ,(build-dispatch (1- bit) base)
		      ,(build-dispatch (1- bit) (+ base (ash 1 bit)))))))
    (build-dispatch 4 0)))

(declaim (inline value-cell-setf))
(defun value-cell-setf (value cell)
  (value-cell-set cell value)
  value)

(declaim (inline setf-symbol-value))
(defun setf-symbol-value (value symbol)
  (setf (symbol-value symbol) value))

(declaim (inline %byte-special-bind))
(defun %byte-special-bind (value symbol)
  (system:%primitive bind value symbol)
  (values))

(declaim (inline %byte-special-unbind))
(defun %byte-special-unbind ()
  (system:%primitive unbind)
  (values))

(declaim (inline cons-unique-tag))
(defun cons-unique-tag ()
  (list '#:%unique-tag%))


;;;; Two-arg function stubs:
;;;
;;; We have two-arg versions of some n-ary functions that are normally
;;; open-coded.

(defun two-arg-char= (x y) (char= x y))
(defun two-arg-char< (x y) (char< x y))
(defun two-arg-char> (x y) (char> x y))
(defun two-arg-char-equal (x y) (char-equal x y))
(defun two-arg-char-lessp (x y) (char-lessp x y))
(defun two-arg-char-greaterp (x y) (char-greaterp x y))


;;;; XOPs

;;; Extension operations (XOPs) are random magic things that the byte
;;; interpreter needs to do, but can't be represented as a function call.
;;; When the byte interpreter encounters an XOP in the byte stream, it
;;; tail-calls the corresponding XOP routine extracted from *byte-xops*.
;;; The XOP routine can do whatever it wants, probably re-invoking the
;;; byte interpreter.

;;; UNDEFINED-XOP -- internal.
;;;
;;; If a real XOP hasn't been defined, this gets invoked and signals an
;;; error.  This shouldn't happen in normal operation.
;;;
(defun undefined-xop (component old-pc pc fp)
  (declare (ignore component old-pc pc fp))
  (error "Undefined XOP."))

;;; *BYTE-XOPS* -- Simple vector of the XOP functions.
;;; 
(declaim (type (simple-vector 256) *byte-xops*))
(defvar *byte-xops*
  (make-array 256 :initial-element #'undefined-xop))

;;; DEFINE-XOP -- internal.
;;;
;;; Define a XOP function and install it in *BYTE-XOPS*.
;;; 
(eval-when (compile eval)
  (defmacro define-xop (name lambda-list &body body)
    (let ((defun-name (symbolicate "BYTE-" name "-XOP")))
      `(progn
	 (defun ,defun-name ,lambda-list
	   ,@body)
	 (setf (aref *byte-xops* ,(xop-index-or-lose name)) #',defun-name)
	 ',defun-name))))

;;; BREAKPOINT -- Xop.
;;;
;;; This is spliced in by the debugger in order to implement breakpoints.
;;; 
(define-xop breakpoint (component old-pc pc fp)
  (declare (type code-component component)
	   (type pc old-pc)
	   (ignore pc)
	   (type stack-pointer fp))
  ;; Invoke the debugger.
  (with-debugger-info (component old-pc fp)
    (di::handle-breakpoint component old-pc fp))
  ;; Retry the breakpoint XOP in case it was replaced with the original
  ;; displaced byte-code.
  (byte-interpret component old-pc fp))

;;; DUP -- Xop.
;;;
;;; This just duplicates whatever is on the top of the stack.
;;;
(define-xop dup (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (let ((value (eval-stack-ref (1- (current-stack-pointer)))))
    (push-eval-stack value))
  (byte-interpret component pc fp))

;;; MAKE-CLOSURE -- Xop.
;;; 
(define-xop make-closure (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (let* ((num-closure-vars (pop-eval-stack))
	 (closure-vars (make-array num-closure-vars)))
    (declare (type index num-closure-vars)
	     (type simple-vector closure-vars))
    (iterate frob ((index (1- num-closure-vars)))
      (unless (minusp index)
	(setf (svref closure-vars index) (pop-eval-stack))
	(frob (1- index))))
    (push-eval-stack (make-byte-compiled-closure (pop-eval-stack)
						 closure-vars)))
  (byte-interpret component pc fp))

(define-xop merge-unknown-values (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (labels ((grovel (remaining-blocks block-count-ptr)
	     (declare (type index remaining-blocks)
		      (type stack-pointer block-count-ptr))
	     (declare (values index stack-pointer))
	     (let ((block-count (eval-stack-ref block-count-ptr)))
	       (declare (type index block-count))
	       (if (= remaining-blocks 1)
		   (values block-count block-count-ptr)
		   (let ((src (- block-count-ptr block-count)))
		     (declare (type index src))
		     (multiple-value-bind
			 (values-above dst)
			 (grovel (1- remaining-blocks) (1- src))
		       (stack-copy dst src block-count)
		       (values (+ values-above block-count)
			       (+ dst block-count))))))))
    (multiple-value-bind
	(total-count end-ptr)
	(grovel (pop-eval-stack) (1- (current-stack-pointer)))
      (setf (eval-stack-ref end-ptr) total-count)
      (setf (current-stack-pointer) (1+ end-ptr))))
  (byte-interpret component pc fp))

(define-xop default-unknown-values (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (let* ((desired (pop-eval-stack))
	 (supplied (pop-eval-stack))
	 (delta (- desired supplied)))
    (declare (type index desired supplied)
	     (type fixnum delta))
    (cond ((minusp delta)
	   (incf (current-stack-pointer) delta))
	  ((plusp delta)
	   (dotimes (i delta)
	     (push-eval-stack nil)))))
  (byte-interpret component pc fp))

;;; THROW -- XOP
;;;
;;; %THROW is compiled down into this xop.  The stack contains the tag, the
;;; values, and then a count of the values.  We special case various small
;;; numbers of values to keep from consing if we can help it.
;;;
;;; Basically, we just extract the values and the tag and then do a throw.
;;; The native compiler will convert this throw into whatever is necessary
;;; to throw, so we don't have to duplicate all that cruft.
;;;
(define-xop throw (component old-pc pc fp)
  (declare (type code-component component)
	   (type pc old-pc)
	   (ignore pc)
	   (type stack-pointer fp))
  (let ((num-results (pop-eval-stack)))
    (declare (type index num-results))
    (case num-results
      (0
       (let ((tag (pop-eval-stack)))
	 (with-debugger-info (component old-pc fp)
	   (throw tag (values)))))
      (1
       (multiple-value-pop-eval-stack
	   (tag result)
	 (with-debugger-info (component old-pc fp)
	   (throw tag result))))
      (2
       (multiple-value-pop-eval-stack
	   (tag result0 result1)
	 (with-debugger-info (component old-pc fp)
	   (throw tag (values result0 result1)))))
      (t
       (let ((results nil))
	 (dotimes (i num-results)
	   (push (pop-eval-stack) results))
	 (let ((tag (pop-eval-stack)))
	   (with-debugger-info (component old-pc fp)
	     (throw tag (values-list results)))))))))

;;; CATCH -- XOP
;;;
;;; This is used for both CATCHes and BLOCKs that are closed over.  We
;;; establish a catcher for the supplied tag (from the stack top), and
;;; recursivly enter the byte interpreter.  If the byte interpreter exits,
;;; it must have been because of a BREAKUP (see below), so we branch (by
;;; tail-calling the byte interpreter) to the pc returned by BREAKUP.
;;; If we are thrown to, then we branch to the address encoded in the 3 bytes
;;; following the catch XOP.
;;; 
(define-xop catch (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (let ((new-pc (block nil
		  (let ((results
			 (multiple-value-list
			  (catch (pop-eval-stack)
			    (return (byte-interpret component (+ pc 3) fp))))))
		    (let ((num-results 0))
		      (declare (type index num-results))
		      (dolist (result results)
			(push-eval-stack result)
			(incf num-results))
		      (push-eval-stack num-results))
		    (component-ref-24 component pc)))))
    (byte-interpret component new-pc fp)))

;;; BREAKUP -- XOP
;;;
;;; Blow out of the dynamically nested CATCH or TAGBODY.  We just return the
;;; pc following the BREAKUP XOP and the drop-through code in CATCH or
;;; TAGBODY will do the correct thing.
;;;
(define-xop breakup (component old-pc pc fp)
  (declare (ignore component old-pc fp)
	   (type pc pc))
  pc)

;;; RETURN-FROM -- XOP
;;;
;;; This is exactly like THROW, except that the tag is the last thing on
;;; the stack instead of the first.  This is used for RETURN-FROM (hence the
;;; name).
;;; 
(define-xop return-from (component old-pc pc fp)
  (declare (type code-component component)
	   (type pc old-pc)
	   (ignore pc)
	   (type stack-pointer fp))
  (let ((tag (pop-eval-stack))
	(num-results (pop-eval-stack)))
    (declare (type index num-results))
    (case num-results
      (0
       (with-debugger-info (component old-pc fp)
	 (throw tag (values))))
      (1
       (let ((value (pop-eval-stack)))
	 (with-debugger-info (component old-pc fp)
	   (throw tag value))))
      (2
       (multiple-value-pop-eval-stack
	   (result0 result1)
	 (with-debugger-info (component old-pc fp)
	   (throw tag (values result0 result1)))))
      (t
       (let ((results nil))
	 (dotimes (i num-results)
	   (push (pop-eval-stack) results))
	 (with-debugger-info (component old-pc fp)
	   (throw tag (values-list results))))))))

;;; TAGBODY -- XOP
;;;
;;; Similar to CATCH, except for TAGBODY.  One significant difference is that
;;; when thrown to, we don't want to leave the dynamic extent of the tagbody
;;; so we loop around and re-enter the catcher.  We keep looping until BREAKUP
;;; is used to blow out.  When that happens, we just branch to the pc supplied
;;; by BREAKUP.
;;;
(define-xop tagbody (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (let* ((tag (pop-eval-stack))
	 (new-pc (block nil
		   (loop
		     (setf pc
			   (catch tag
			     (return (byte-interpret component pc fp))))))))
    (byte-interpret component new-pc fp)))

;;; GO -- XOP
;;;
;;; Yup, you guessed it.  This XOP implements GO.  There are no values to
;;; pass, so we don't have to mess with them, and multiple exits can all be
;;; using the same tag so we have to pass the pc we want to go to.
;;;
(define-xop go (component old-pc pc fp)
  (declare (type code-component component)
	   (type pc old-pc pc)
	   (type stack-pointer fp))
  (let ((tag (pop-eval-stack))
	(new-pc (component-ref-24 component pc)))
    (with-debugger-info (component old-pc fp)
      (throw tag new-pc))))

;;; UNWIND-PROTECT -- XOP
;;;
;;; Unwind-protects are handled significantly different in the byte compiler
;;; and the native compiler.  Basically, we just use the native-compiler's
;;; unwind-protect, and let it worry about continuing the unwind.
;;; 
(define-xop unwind-protect (component old-pc pc fp)
  (declare (type code-component component)
	   (ignore old-pc)
	   (type pc pc)
	   (type stack-pointer fp))
  (let ((new-pc nil))
    (unwind-protect
	(setf new-pc (byte-interpret component (+ pc 3) fp))
      (unless new-pc
	;; The cleanup function expects 3 values to be one the stack, so
	;; we have to put something there.
	(push-eval-stack nil)
	(push-eval-stack nil)
	(push-eval-stack nil)
	;; Now run the cleanup code.
	(byte-interpret component (component-ref-24 component pc) fp)))
    (byte-interpret component new-pc fp)))


(define-xop fdefn-function-or-lose (component old-pc pc fp)
  (let* ((fdefn (pop-eval-stack))
	 (fun (fdefn-function fdefn)))
    (declare (type fdefn fdefn))
    (cond (fun
	   (push-eval-stack fun)
	   (byte-interpret component pc fp))
	  (t
	   (with-debugger-info (component old-pc fp)
	     (error 'undefined-function :name (fdefn-name fdefn)))))))



;;;; Type checking:

;;;
;;; These two hashtables map between type specifiers and type predicate
;;; functions that test those types.  They are initialized according to the
;;; standard type predicates of the target system.
;;;
(defvar *byte-type-predicates* (make-hash-table :test #'equal))
(defvar *byte-predicate-types* (make-hash-table :test #'eq))

(loop for (type predicate) in
          '#.(loop for (type . predicate) in
	           (backend-type-predicates *target-backend*)
	       collect `(,(type-specifier type) ,predicate))
      do
  (let ((fun (fdefinition predicate)))
    (setf (gethash type *byte-type-predicates*) fun)
    (setf (gethash fun *byte-predicate-types*) type)))
	    

;;; LOAD-TYPE-PREDICATE  --  Internal
;;;
;;;    Called by the loader to convert a type specifier into a type predicate
;;; (as used by the TYPE-CHECK XOP.)  If it is a structure type with a
;;; predicate or has a predefined predicate, then return the predicate
;;; function, otherwise return the CTYPE structure for the type.
;;;
(defun load-type-predicate (desc)
  (or (gethash desc *byte-type-predicates*)
      (let ((type (specifier-type desc)))
	(if (structure-type-p type)
	    (let ((info (info type defined-structure-info
			      (structure-type-name type))))
	      (if (and info (eq (dd-type info) 'structure))
		  (let ((pred (dd-predicate info)))
		    (if (and pred (fboundp pred))
			(fdefinition pred)
			type))
		  type))
	    type))))

  
;;; TYPE-CHECK -- Xop.
;;;
;;;    Check the type of the value on the top of the stack.  The type is
;;; designated by an entry in the constants.  If the value is a function, then
;;; it is called as a type predicate.  Otherwise, the value is a CTYPE object,
;;; and we call %%TYPEP on it.
;;;
(define-xop type-check (component old-pc pc fp)
  (declare (type code-component component)
	   (type pc old-pc pc)
	   (type stack-pointer fp))
  (multiple-value-bind
      (operand new-pc)
      (let ((operand (component-ref component pc)))
	(if (= operand #xff)
	    (values (component-ref-24 component (1+ pc)) (+ pc 4))
	    (values operand (1+ pc))))
    (let ((value (eval-stack-ref (1- (current-stack-pointer))))
	  (type (code-header-ref component
				 (+ operand vm:code-constants-offset))))
      (unless (if (functionp type)
		  (funcall type value)
		  (lisp::%%typep value type))
	(with-debugger-info (component old-pc fp)
	  (error 'type-error
		 :datum value
		 :expected-type (if (functionp type)
				    (gethash type *byte-predicate-types*)
				    (type-specifier type))))))
    
    (byte-interpret component new-pc fp)))


;;;; The byte-interpreter.


;;; The various operations are encoded as follows.
;;;
;;; 0000xxxx push-local op
;;; 0001xxxx push-arg op   [push-local, but negative]
;;; 0010xxxx push-constant op
;;; 0011xxxx push-system-constant op
;;; 0100xxxx push-int op
;;; 0101xxxx push-neg-int op
;;; 0110xxxx pop-local op
;;; 0111xxxx pop-n op
;;; 1000nxxx call op
;;; 1001nxxx tail-call op
;;; 1010nxxx multiple-call op
;;; 10110xxx local-call
;;; 10111xxx local-tail-call
;;; 11000xxx local-multiple-call
;;; 11001xxx return
;;; 1101000r branch
;;; 1101001r if-true
;;; 1101010r if-false
;;; 1101011r if-eq
;;; 11011xxx Xop
;;; 11100000
;;;    to    various inline functions.
;;; 11111111
;;;
;;; This encoding is rather hard wired into BYTE-INTERPRET due to the binary
;;; dispatch tree.
;;; 

#+nil (declaim (start-block byte-interpret byte-interpret-byte
			    invoke-xep invoke-local-entry-point))

(defvar *byte-trace* nil)

;;; BYTE-INTERPRET -- Internal Interface.
;;;
;;; Main entry point to the byte interpreter.
;;; 
(defun byte-interpret (component pc fp)
  (declare (type code-component component)
	   (type pc pc)
	   (type stack-pointer fp))
  (byte-interpret-byte component pc fp (component-ref component pc)))

;;; BYTE-INTERPRET-BYTE -- Internal.
;;;
;;; This is seperated from BYTE-INTERPRET so we can continue from a breakpoint
;;; without having to replace the breakpoint with the original instruction
;;; and arrange to somehow put the breakpoint back after executing the
;;; instruction.  We just leave the breakpoint there, and calls this function
;;; with the byte the breakpoint displaced.
;;;
(defun byte-interpret-byte (component pc fp byte)
  (declare (type code-component component)
	   (type pc pc)
	   (type stack-pointer fp)
	   (type (unsigned-byte 8) byte))
  (locally (declare (optimize (inhibit-warnings 3)))
    (when *byte-trace*
      (format *trace-output* "pc=~D, fp=~D, sp=~D, byte=#b~8,'0B, frame=~S~%"
	      pc fp (current-stack-pointer) byte
	      (subseq eval::*eval-stack* fp (current-stack-pointer)))))
  (if (zerop (logand byte #x80))
      ;; Some stack operation.  No matter what, we need the operand,
      ;; so compute it.
      (multiple-value-bind
	  (operand new-pc)
	  (let ((operand (logand byte #xf)))
	    (if (= operand #xf)
		(let ((operand (component-ref component (1+ pc))))
		  (if (= operand #xff)
		      (values (component-ref-24 component (+ pc 2))
			      (+ pc 5))
		      (values operand (+ pc 2))))
		(values operand (1+ pc))))
	(if (zerop (logand byte #x40))
	    (push-eval-stack (if (zerop (logand byte #x20))
				 (if (zerop (logand byte #x10))
				     (eval-stack-ref (+ fp operand))
				     (eval-stack-ref (- fp operand 5)))
				 (if (zerop (logand byte #x10))
				     (code-header-ref
				      component
				      (+ operand vm:code-constants-offset))
				     (svref system-constants operand))))
	    (if (zerop (logand byte #x20))
		(push-eval-stack (if (zerop (logand byte #x10))
				     operand
				     (- (1+ operand))))
		(if (zerop (logand byte #x10))
		    (setf (eval-stack-ref (+ fp operand)) (pop-eval-stack))
		    (if (zerop operand)
			(let ((operand (pop-eval-stack)))
			  (declare (type index operand))
			  (decf (current-stack-pointer) operand))
			(decf (current-stack-pointer) operand)))))
	(byte-interpret component new-pc fp))
      (if (zerop (logand byte #x40))
	  ;; Some kind of call.
	  (let ((args (let ((args (logand byte #x07)))
			(if (= args #x07)
			    (pop-eval-stack)
			    args))))
	    (if (zerop (logand byte #x20))
		(let ((named (not (zerop (logand byte #x08)))))
		  (if (zerop (logand byte #x10))
		      ;; Call for single value.
		      (do-call component pc (1+ pc) fp args named)
		      ;; Tail call.
		      (do-tail-call component pc fp args named)))
		(if (zerop (logand byte #x10))
		    ;; Call for multiple-values.
		    (do-call component pc (- (1+ pc)) fp args
			     (not (zerop (logand byte #x08))))
		    (if (zerop (logand byte #x08))
			;; Local call
			(do-local-call component pc (+ pc 4) fp args)
			;; Local tail-call
			(do-tail-local-call component pc fp args)))))
	  (if (zerop (logand byte #x20))
	      ;; local-multiple-call, Return, branch, or Xop.
	      (if (zerop (logand byte #x10))
		  ;; local-multiple-call or return.
		  (if (zerop (logand byte #x08))
		      ;; Local-multiple-call.
		      (do-local-call component pc (- (+ pc 4)) fp
				     (let ((args (logand byte #x07)))
				       (if (= args #x07)
					   (pop-eval-stack)
					   args)))
		      ;; Return.
		      (let ((num-results
			     (let ((num-results (logand byte #x7)))
			       (if (= num-results 7)
				   (pop-eval-stack)
				   num-results))))
			(do-return fp num-results)))
		  ;; Branch or Xop.
		  (if (zerop (logand byte #x08))
		      ;; Branch.
		      (if (if (zerop (logand byte #x04))
			      (if (zerop (logand byte #x02))
				  t
				  (pop-eval-stack))
			      (if (zerop (logand byte #x02))
				  (not (pop-eval-stack))
				  (multiple-value-pop-eval-stack
				   (val1 val2)
				   (eq val1 val2))))
			  ;; Branch taken.
			  (byte-interpret
			   component
			   (if (zerop (logand byte #x01))
			       (component-ref-24 component (1+ pc))
			       (+ pc 2
				  (component-ref-signed component (1+ pc))))
			   fp)
			  ;; Branch not taken.
			  (byte-interpret component
					  (if (zerop (logand byte #x01))
					      (+ pc 4)
					      (+ pc 2))
					  fp))
		      ;; Xop.
		      (multiple-value-bind
			  (sub-code new-pc)
			  (let ((operand (logand byte #x7)))
			    (if (= operand #x7)
				(values (component-ref component (+ pc 1))
					(+ pc 2))
				(values operand (1+ pc))))
			(funcall (the function (svref *byte-xops* sub-code))
				 component pc new-pc fp))))
	      ;; Random inline function.
	      (progn
		(expand-into-inlines)
		(byte-interpret component (1+ pc) fp))))))

(defun do-local-call (component pc old-pc old-fp num-args)
  (declare (type pc pc)
	   (type return-pc old-pc)
	   (type stack-pointer old-fp)
	   (type (integer 0 #.call-arguments-limit) num-args))
  (invoke-local-entry-point component (component-ref-24 component (1+ pc))
			    component old-pc
			    (- (current-stack-pointer) num-args)
			    old-fp))

(defun do-tail-local-call (component pc fp num-args)
  (declare (type code-component component) (type pc pc)
	   (type stack-pointer fp)
	   (type index num-args))
  (let ((old-fp (eval-stack-ref (- fp 1)))
	(old-sp (eval-stack-ref (- fp 2)))
	(old-pc (eval-stack-ref (- fp 3)))
	(old-component (eval-stack-ref (- fp 4)))
	(start-of-args (- (current-stack-pointer) num-args)))
    (stack-copy old-sp start-of-args num-args)
    (setf (current-stack-pointer) (+ old-sp num-args))
    (invoke-local-entry-point component (component-ref-24 component (1+ pc))
			      old-component old-pc old-sp old-fp)))

(defun invoke-local-entry-point (component target old-component old-pc old-sp
					   old-fp &optional closure-vars)
  (declare (type pc target)
	   (type return-pc old-pc)
	   (type stack-pointer old-sp old-fp)
	   (type (or null simple-vector) closure-vars))
  (when closure-vars
    (iterate more ((index (1- (length closure-vars))))
      (unless (minusp index)
	(push-eval-stack (svref closure-vars index))
	(more (1- index)))))
  (push-eval-stack old-component)
  (push-eval-stack old-pc)
  (push-eval-stack old-sp)
  (push-eval-stack old-fp)
  (multiple-value-bind
      (stack-frame-size entry-pc)
      (let ((byte (component-ref component target)))
	(if (= byte 255)
	    (values (component-ref-24 component (1+ target)) (+ target 4))
	    (values (* byte 2) (1+ target))))
    (declare (type pc entry-pc))
    (let ((fp (current-stack-pointer)))
      (setf (current-stack-pointer) (+ fp stack-frame-size))
      (byte-interpret component entry-pc fp))))


;;; BYTE-APPLY  --  Internal
;;;
;;;    Call a function with some arguments popped off of the interpreter stack,
;;; and restore the SP to the specifier value.
;;;
(defun byte-apply (function num-args restore-sp)
  (declare (function function) (type index num-args))
  (let ((start (- (current-stack-pointer) num-args)))
    (declare (type stack-pointer start))
    (macrolet ((frob ()
		 `(case num-args
		    ,@(loop for n below 8
			collect `(,n (call-1 ,n)))
		    (t
		     (let ((args ())
			   (end (+ start num-args)))
		       (declare (type stack-pointer end))
		       (do ((i start (1+ i)))
			   ((= i end))
			 (declare (type stack-pointer i))
			 (push (eval-stack-ref i) args))
		       (setf (current-stack-pointer) restore-sp)
		       (apply function args)))))
	       (call-1 (n)
		 (collect ((binds)
			   (args))
		   (dotimes (i n)
		     (let ((dum (gensym)))
		       (binds `(,dum (eval-stack-ref (+ start ,i))))
		       (args dum)))
		   `(let ,(binds)
		      (setf (current-stack-pointer) restore-sp)
		      (funcall function ,@(args))))))
      (frob))))


(defun do-call (old-component call-pc ret-pc old-fp num-args named)
  (declare (type code-component old-component)
	   (type pc call-pc)
	   (type return-pc ret-pc)
	   (type stack-pointer old-fp)
	   (type (integer 0 #.call-arguments-limit) num-args)
	   (type (member t nil) named))
  (let* ((old-sp (- (current-stack-pointer) num-args 1))
	 (fun-or-fdefn (eval-stack-ref old-sp))
	 (function (if named
		       (or (fdefn-function fun-or-fdefn)
			   (with-debugger-info (old-component call-pc old-fp)
			     (error 'undefined-function
				    :name (fdefn-name fun-or-fdefn))))
		       fun-or-fdefn)))
    (declare (type stack-pointer old-sp)
	     (type (or function fdefn) fun-or-fdefn)
	     (type function function))
    (case (function-subtype function)
      (#.vm:byte-code-function-type
       (invoke-xep old-component ret-pc old-sp old-fp num-args
		   (byte-compiled-function-xep function)))
      (#.vm:byte-code-closure-type
       (invoke-xep old-component ret-pc old-sp old-fp num-args
		   (byte-compiled-closure-xep function)
		   (byte-compiled-closure-closure-vars function)))
      (t
       (cond ((minusp ret-pc)
	      (let* ((ret-pc (- ret-pc))
		     (results
		      (multiple-value-list
		       (with-debugger-info
			(old-component ret-pc old-fp)
			(byte-apply function num-args old-sp)))))
		(dolist (result results)
		  (push-eval-stack result))
		(push-eval-stack (length results))
		(byte-interpret old-component ret-pc old-fp)))
	     (t
	      (push-eval-stack
	       (with-debugger-info
		(old-component ret-pc old-fp)
		(byte-apply function num-args old-sp)))
	      (byte-interpret old-component ret-pc old-fp)))))))


(defun do-tail-call (component pc fp num-args named)
  (declare (type code-component component)
	   (type pc pc)
	   (type stack-pointer fp)
	   (type (integer 0 #.call-arguments-limit) num-args)
	   (type (member t nil) named))
  (let* ((start-of-args (- (current-stack-pointer) num-args))
	 (fun-or-fdefn (eval-stack-ref (1- start-of-args)))
	 (function (if named
		       (or (fdefn-function fun-or-fdefn)
			   (with-debugger-info (component pc fp)
			     (error 'undefined-function
				    :name (fdefn-name fun-or-fdefn))))
		       fun-or-fdefn))
	 (old-fp (eval-stack-ref (- fp 1)))
	 (old-sp (eval-stack-ref (- fp 2)))
	 (old-pc (eval-stack-ref (- fp 3)))
	 (old-component (eval-stack-ref (- fp 4))))
    (declare (type stack-pointer old-fp old-sp start-of-args)
	     (type return-pc old-pc)
	     (type (or fdefn function) fun-or-fdefn)
	     (type function function))
    (case (function-subtype function)
      (#.vm:byte-code-function-type
       (stack-copy old-sp start-of-args num-args)
       (setf (current-stack-pointer) (+ old-sp num-args))
       (invoke-xep old-component old-pc old-sp old-fp num-args
		   (byte-compiled-function-xep function)))
      (#.vm:byte-code-closure-type
       (stack-copy old-sp start-of-args num-args)
       (setf (current-stack-pointer) (+ old-sp num-args))
       (invoke-xep old-component old-pc old-sp old-fp num-args
		   (byte-compiled-closure-xep function)
		   (byte-compiled-closure-closure-vars function)))
      (t
       ;; We are tail-calling native code.
	 (cond ((null old-component)
		;; We were called by native code.
		(byte-apply function num-args old-sp))
	       ((minusp old-pc)
		;; We were called for multiple values.  So return multiple
		;; values.
		(let ((results
		       (multiple-value-list
			(with-debugger-info
			    (old-component old-pc old-fp)
			  (byte-apply function num-args old-sp)))))
		  (dolist (result results)
		    (push-eval-stack result))
		  (push-eval-stack (length results)))
		(byte-interpret old-component old-pc old-fp))
	       (t
		;; We were called for one value.  So return one value.
		(push-eval-stack
		 (with-debugger-info
		     (old-component old-pc old-fp)
		   (byte-apply function num-args old-sp)))
		(byte-interpret old-component old-pc old-fp)))))))

(defun invoke-xep (old-component ret-pc old-sp old-fp num-args xep
				 &optional closure-vars)
  (declare (type (or null code-component) old-component)
	   (type index num-args)
	   (type return-pc ret-pc)
	   (type stack-pointer old-sp old-fp)
	   (type byte-xep xep)
	   (type (or null simple-vector) closure-vars))
  (let ((entry-point
	 (let ((min (byte-xep-min-args xep))
	       (max (byte-xep-max-args xep)))
	   (cond
	    ((< num-args min)
	     ;; ### Flame out point.
	     (error "Not enough arguments."))
	    ((<= num-args max)
	     (nth (- num-args min) (byte-xep-entry-points xep)))
	    ((null (byte-xep-more-args-entry-point xep))
	     ;; ### Flame out point.
	     (error "Too many arguments."))
	    (t
	     (let* ((more-args-supplied (- num-args max))
		    (sp (current-stack-pointer))
		    (more-args-start (- sp more-args-supplied))
		    (restp (byte-xep-rest-arg-p xep))
		    (rest (and restp
			       (do ((index (1- sp) (1- index))
				    (result nil
					    (cons (eval-stack-ref index)
						  result)))
				   ((< index more-args-start) result)
				 (declare (type index index))))))
	       (declare (type index more-args-supplied)
			(type stack-pointer more-args-start))
	       (cond
		((not (byte-xep-keywords-p xep))
		 (assert restp)
		 (setf (current-stack-pointer) (1+ more-args-start))
		 (setf (eval-stack-ref more-args-start) rest))
		(t
		 (unless (evenp more-args-supplied)
		   ;; ### Flame out.
		   (error "Odd number of keyword arguments."))
		 (let* ((num-more-args (byte-xep-num-more-args xep))
			(new-sp (+ more-args-start num-more-args))
			(temp (max sp new-sp))
			(temp-sp (+ temp more-args-supplied))
			(keywords (byte-xep-keywords xep)))
		   (declare (type index temp)
			    (type stack-pointer new-sp temp-sp))
		   (setf (current-stack-pointer) temp-sp)
		   (stack-copy temp more-args-start more-args-supplied)
		   (when restp
		     (setf (eval-stack-ref more-args-start) rest)
		     (incf more-args-start))
		   (let ((index more-args-start))
		     (dolist (keyword keywords)
		       (setf (eval-stack-ref index) (cadr keyword))
		       (incf index)
		       (when (caddr keyword)
			 (setf (eval-stack-ref index) nil)
			 (incf index))))
		   (let ((index temp-sp)
			 (allow (eq (byte-xep-keywords-p xep) :allow-others))
			 (bogus-key nil)
			 (bogus-key-p nil))
		     (declare (type stack-pointer index))
		     (loop
		       (decf index 2)
		       (when (< index more-args-start)
			 (return))
		       (let ((key (eval-stack-ref index))
			     (value (eval-stack-ref (1+ index))))
			 (if (eq key :allow-other-keys)
			     (setf allow value)
			     (let ((target more-args-start))
			       (declare (type stack-pointer target))
			       (dolist (keyword keywords
						(setf bogus-key key
						      bogus-key-p t))
				 (cond ((eq (car keyword) key)
					(setf (eval-stack-ref target) value)
					(when (caddr keyword)
					  (setf (eval-stack-ref (1+ target))
						t))
					(return))
				       ((caddr keyword)
					(incf target 2))
				       (t
					(incf target))))))))
		     (when (and bogus-key-p (not allow))
		       ;; ### Flame out.
		       (error "Unknown keyword: ~S" bogus-key)))
		   (setf (current-stack-pointer) new-sp)))))
	     (byte-xep-more-args-entry-point xep))))))
    (declare (type pc entry-point))
    (invoke-local-entry-point (byte-xep-component xep) entry-point
			      old-component ret-pc old-sp old-fp
			      closure-vars)))

(defun do-return (fp num-results)
  (declare (type stack-pointer fp) (type index num-results))
  (let ((old-component (eval-stack-ref (- fp 4))))
    (typecase old-component
      (code-component
       ;; Returning to more byte-interpreted code.
       (do-local-return old-component fp num-results))
      (null
       ;; Returning to native code.
       (let ((old-sp (eval-stack-ref (- fp 2))))
	 (case num-results
	   (0
	    (setf (current-stack-pointer) old-sp)
	    (values))
	   (1
	    (let ((result (pop-eval-stack)))
	      (setf (current-stack-pointer) old-sp)
	      result))
	   (t
	    (let ((results nil))
	      (dotimes (i num-results)
		(push (pop-eval-stack) results))
	      (setf (current-stack-pointer) old-sp)
	      (values-list results))))))
      (t
       ;; ### Function end breakpoint?
       (error "function-end breakpoints not supported.")))))

(defun do-local-return (old-component fp num-results)
  (declare (type stack-pointer fp) (type index num-results))
  (let ((old-fp (eval-stack-ref (- fp 1)))
	(old-sp (eval-stack-ref (- fp 2)))
	(old-pc (eval-stack-ref (- fp 3))))
    (declare (type (signed-byte 25) old-pc))
    (if (plusp old-pc)
	;; Wants single value.
	(let ((result (if (zerop num-results)
			  nil
			  (eval-stack-ref (- (current-stack-pointer)
					     num-results)))))
	  (setf (current-stack-pointer) old-sp)
	  (push-eval-stack result)
	  (byte-interpret old-component old-pc old-fp))
	;; Wants multiple values.
	(progn
	  (stack-copy old-sp (- (current-stack-pointer) num-results)
		      num-results)
	  (setf (current-stack-pointer) (+ old-sp num-results))
	  (push-eval-stack num-results)
	  (byte-interpret old-component (- old-pc) old-fp)))))

;(declaim (end-block byte-interpret byte-interpret-byte invoke-xep))


;;;; Random testing noise.

(defun dump-byte-fun (fun)
  (declare (optimize (inhibit-warnings 3)))
  (let* ((xep (system:find-if-in-closure #'byte-xep-p fun))
	 (component (byte-xep-component xep))
	 (bytes (* (code-header-ref component vm:code-code-size-slot)
		   vm:word-bytes)))
    (dotimes (index bytes)
      (format t "~3D: #b~8,'0B~%" index (component-ref component index)))))


(defun disassem-byte-fun (fun)
  (declare (optimize (inhibit-warnings 3)))
  (let* ((xep (system:find-if-in-closure #'byte-xep-p fun))
	 (component (byte-xep-component xep))
	 (bytes (* (code-header-ref component vm:code-code-size-slot)
		   vm:word-bytes))
	 (index 0))
    (labels ((newline ()
	       (format t "~&~4D:" index))
	     (next-byte ()
	       (let ((byte (component-ref component index)))
		 (format t " ~2,'0X" byte)
		 (incf index)
		 byte))
	     (extract-24-bits ()
	       (logior (ash (next-byte) 16)
		       (ash (next-byte) 8)
		       (next-byte)))
	     (extract-extended-op ()
	       (let ((byte (next-byte)))
		 (if (= byte 255)
		     (extract-24-bits)
		     byte)))       
	     (extract-4-bit-op (byte)
	       (let ((4-bits (ldb (byte 4 0) byte)))
		 (if (= 4-bits 15)
		     (extract-extended-op)
		     4-bits)))
	     (extract-3-bit-op (byte)
	       (let ((3-bits (ldb (byte 3 0) byte)))
		 (if (= 3-bits 7)
		     :var
		     3-bits)))
	     (extract-branch-target (byte)
	       (if (logbitp 0 byte)
		   (let ((disp (next-byte)))
		     (if (logbitp 7 disp)
			 (+ index disp -256)
			 (+ index disp)))
		   (extract-24-bits)))
	     (note (string &rest noise)
	       (format t "~12T~?" string noise))
	     (get-constant (index)
	       (let ((index (+ index vm:code-constants-offset)))
		 (if (< (1- vm:code-constants-offset)
			index
			(get-header-data component))
		     (code-header-ref component index)
		     "<bogus index>"))))

      (newline)
      (let ((frame-size
	     (let ((byte (next-byte)))
	       (if (< byte 255)
		   (* byte 2)
		   (logior (ash (next-byte) 16)
			   (ash (next-byte) 8)
			   (next-byte))))))
	(note "Entry point, frame-size=~D~%" frame-size))
      (loop
	(unless (< index bytes)
	  (return))
	(newline)
	(let ((byte (next-byte)))
	  (macrolet ((dispatch (&rest clauses)
		       `(cond ,@(mapcar #'(lambda (clause)
					    `((= (logand byte ,(caar clause))
						 ,(cadar clause))
					      ,@(cdr clause)))
					clauses))))
	    (dispatch
	     ((#b11110000 #b00000000)
	      (let ((op (extract-4-bit-op byte)))
		(note "push-local ~D" op)))
	     ((#b11110000 #b00010000)
	      (let ((op (extract-4-bit-op byte)))
		(note "push-arg ~D" op)))
	     ((#b11110000 #b00100000)
	      (let ((index (+ (extract-4-bit-op byte)
			      vm:code-constants-offset))
		    (*print-level* 3)
		    (*print-lines* 2))
		(note "push-const ~S"
		      (if (< (1- vm:code-constants-offset)
			     index
			     (get-header-data component))
			  (code-header-ref component index)
			  "<bogus index>"))))
	     ((#b11110000 #b00110000)
	      (let ((op (extract-4-bit-op byte))
		    (*print-level* 3)
		    (*print-lines* 2))
		(note "push-sys-const ~S"
		      (svref system-constants op))))
	     ((#b11110000 #b01000000)
	      (let ((op (extract-4-bit-op byte)))
		(note "push-int ~D" op)))
	     ((#b11110000 #b01010000)
	      (let ((op (extract-4-bit-op byte)))
		(note "push-neg-int ~D" (- (1+ op)))))
	     ((#b11110000 #b01100000)
	      (let ((op (extract-4-bit-op byte)))
		(note "pop-local ~D" op)))
	     ((#b11110000 #b01110000)
	      (let ((op (extract-4-bit-op byte)))
		(note "pop-n ~D" op)))
	     ((#b11110000 #b10000000)
	      (let ((op (extract-3-bit-op byte)))
		(note "~:[~;named-~]call, ~D args"
		      (logbitp 3 byte) op)))
	     ((#b11110000 #b10010000)
	      (let ((op (extract-3-bit-op byte)))
		(note "~:[~;named-~]tail-call, ~D args"
		      (logbitp 3 byte) op)))
	     ((#b11110000 #b10100000)
	      (let ((op (extract-3-bit-op byte)))
		(note "~:[~;named-~]multiple-call, ~D args"
		      (logbitp 3 byte) op)))
	     ((#b11111000 #b10110000)
	      ;; local call
	      (let ((op (extract-3-bit-op byte))
		    (target (extract-24-bits)))
		(note "local call ~D, ~D args" target op)))
	     ((#b11111000 #b10111000)
	      ;; local tail-call
	      (let ((op (extract-3-bit-op byte))
		    (target (extract-24-bits)))
		(note "local tail-call ~D, ~D args" target op)))
	     ((#b11111000 #b11000000)
	      ;; local-multiple-call
	      (let ((op (extract-3-bit-op byte))
		    (target (extract-24-bits)))
		(note "local multiple-call ~D, ~D args" target op)))
	     ((#b11111000 #b11001000)
	      ;; return
	      (let ((op (extract-3-bit-op byte)))
		(note "return, ~D vals" op)))
	     ((#b11111110 #b11010000)
	      ;; branch
	      (note "branch ~D" (extract-branch-target byte)))
	     ((#b11111110 #b11010010)
	      ;; if-true
	      (note "if-true ~D" (extract-branch-target byte)))
	     ((#b11111110 #b11010100)
	      ;; if-false
	      (note "if-false ~D" (extract-branch-target byte)))
	     ((#b11111110 #b11010110)
	      ;; if-eq
	      (note "if-eq ~D" (extract-branch-target byte)))
	     ((#b11111000 #b11011000)
	      ;; XOP
	      (let* ((low-3-bits (extract-3-bit-op byte))
		     (xop (nth (if (eq low-3-bits :var) (next-byte) low-3-bits)
			       *xop-names*)))
		(note "xop ~A~@[ ~D~]"
		      xop
		      (case xop
			((catch go unwind-protect)
			 (extract-24-bits))
			(type-check
			 (get-constant (extract-extended-op)))))))
			 
	     ((#b11100000 #b11100000)
	      ;; inline
	      (note "inline ~A"
		    (inline-function-info-function
		     (nth (ldb (byte 5 0) byte) *inline-functions*)))))))))))

