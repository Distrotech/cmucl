;;; -*- Mode: Lisp; Package: Lisp; Log: code.log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/describe.lisp,v 1.20 1992/05/07 08:52:52 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; This is the describe mechanism for Common Lisp.
;;;
;;; Written by Skef Wholey or Rob MacLachlan originally.
;;; Cleaned up, reorganized, and enhanced by Blaine Burks.
;;; Ported to the new system and cleaned up some more by Rob MacLachlan.
;;;
;;; This should be done better using CLOS more effectively once CMU Common
;;; Lisp is brought up to the new standard.  The TYPECASE in DESCRIBE-AUX
;;; should be unnecessary.	-- Bill Chiles
;;;

(in-package "LISP")
(export '(describe))

(in-package "EXT")
(export '(*describe-level* *describe-verbose* *describe-print-level*
	  *describe-print-length* *describe-indentation*))

(in-package "LISP")


;;;; DESCRIBE public switches.

(defvar *describe-level* 2
  "Depth of recursive descriptions allowed.")

(defvar *describe-verbose* nil
  "If non-nil, descriptions may provide interpretations of information and
  pointers to additional information.  Normally nil.")

(defvar *describe-print-level* 2
  "*print-level* gets bound to this inside describe.  If null, use
  *print-level*")

(defvar *describe-print-length* 5
  "*print-length* gets bound to this inside describe.  If null, use
  *print-length*.")

(defvar *describe-indentation* 3
  "Number of spaces that sets off each line of a recursive description.")

(defvar *in-describe* nil
  "Used to tell whether we are doing a recursive describe.")
(defvar *current-describe-level* 0
  "Used to implement recursive description cutoff.  Don't touch.")
(defvar *describe-output* nil
  "An output stream used by Describe for indenting and stuff.")
(defvar *described-objects* nil
  "List of all objects describe within the current top-level call to describe.")
(defvar *current-describe-object* nil
  "The last object passed to describe.")

;;; DESCRIBE sets up the output stream and calls DESCRIBE-AUX, which does the
;;; hard stuff.
;;;
(defun describe (x &optional stream)
  "Prints a description of the object X."
  (declare (type (or stream (member t nil)) stream))
  (unless *describe-output*
    (setq *describe-output* (make-indenting-stream *standard-output*)))
  (cond (*in-describe*
	 (unless (or (eq x nil) (eq x t))
	   (let ((*current-describe-level* (1+ *current-describe-level*))
		 (*current-describe-object* x))
	     (indenting-further *describe-output* *describe-indentation*
	       (describe-aux x)))))
	(t
	 (setf (indenting-stream-stream *describe-output*)
	       (case stream
		 ((t) *terminal-io*)
		 ((nil) *standard-output*)
		 (t stream)))
	 (let ((*standard-output* *describe-output*)
	       (*print-level* (or *describe-print-level* *print-level*))
	       (*print-length* (or *describe-print-length* *print-length*))
	       (*described-objects* ())
	       (*in-describe* t)
	       (*current-describe-object* x))
	   (describe-aux x))
	 (values))))

;;; DESCRIBE-AUX does different things for each type.  The order of the
;;; TYPECASE branches matters with respect to:
;;;    - symbols and functions until the new standard makes them disjoint.
;;;    - packages and structure since packages are structures.
;;; We punt a given call if the current level is greater than *describe-level*,
;;; or if we detect an object into which we have already descended.
;;;
(defun describe-aux (x)
  (when (or (not (integerp *describe-level*))
	    (minusp *describe-level*))
    (error "*describe-level* should be a nonnegative integer - ~A."
	   *describe-level*))
  (when (or (>= *current-describe-level* *describe-level*)
	    (member x *described-objects*))
    (return-from describe-aux x))
  (push x *described-objects*)
  (typecase x
    (symbol (describe-symbol x))
    (function (describe-function x))
    (package (describe-package x))
    (hash-table (describe-hash-table x))
    (structure (describe-structure x))
    (array (describe-array x))
    (fixnum (describe-fixnum x))
    (cons
     (if (and (eq (car x) 'setf) (consp (cdr x)) (null (cddr x))
	      (symbolp (cadr x))
	      (fboundp x))
	 (describe-function (fdefinition x) :function x)
	 (default-describe x)))
    (t (default-describe x)))
  x)



;;;; Implementation properties.

;;; This supresses random garbage that users probably don't want to see.
;;;
(defparameter *implementation-properties*
  '(%loaded-address CONDITIONS::MAKE-FUNCTION CONDITIONS::REPORT-FUNCTION
		    CONDITIONS::CONC-NAME CONDITIONS::SLOTS
		    CONDITIONS::PARENT-TYPE))


;;;; Miscellaneous DESCRIBE methods:
	  
(defun default-describe (x)
  (format t "~&~S is a ~S." x (type-of x)))

(defun describe-structure (x)
  (cond ((and (fboundp 'pcl::std-instance-p)
	      (pcl::std-instance-p x))
	 (pcl::describe-object x *standard-output*))
	(t
	 (format t "~&~S is a structure of type ~A." x (c::structure-ref x 0))
	 (dolist (slot (cddr (inspect::describe-parts x)))
	   (format t "~%~A: ~S." (car slot) (cdr slot))))))

(defun describe-array (x)
  (let ((rank (array-rank x)))
    (cond ((> rank 1)
	   (format t "~&~S is " x)
	   (write-string (if (%array-displaced-p x) "a displaced" "an"))
	   (format t " array of rank ~A." rank)
	   (format t "~%Its dimensions are ~S." (array-dimensions x)))
	  (t
	   (format t "~&~S is a ~:[~;displaced ~]vector of length ~D." x
		   (and (array-header-p x) (%array-displaced-p x)) (length x))
	   (if (array-has-fill-pointer-p x)
	       (format t "~&It has a fill pointer, currently ~d"
		       (fill-pointer x))
	       (format t "~&It has no fill pointer."))))
  (format t "~&Its element type is ~S." (array-element-type x))))

(defun describe-fixnum (x)
  (cond ((not (or *describe-verbose* (zerop *current-describe-level*))))
	((primep x)
	 (format t "~&It is a prime number."))
	(t
	 (format t "~&It is a composite number."))))

(defun describe-hash-table (x)
  (format t "~&~S is an ~A hash table." x (hash-table-test x))
  (format t "~&Its size is ~D buckets." (length (hash-table-table x)))
  (format t "~&Its rehash-size is ~S." (hash-table-rehash-size x))
  (format t "~&Its rehash-threshold is ~S."
	  (hash-table-rehash-threshold x))
  (format t "~&It currently holds ~d entries."
	  (hash-table-number-entries x)))

(defun describe-package (x)
  (describe-structure x)
  (let* ((internal (package-internal-symbols x))
	 (internal-count (- (package-hashtable-size internal)
			    (package-hashtable-free internal)))
	 (external (package-external-symbols x))
	 (external-count (- (package-hashtable-size external)
			    (package-hashtable-free external))))
    (format t "~&~d symbols total: ~d internal and ~d external."
	     (+ internal-count external-count) internal-count external-count)))


;;;; Function and symbol description (documentation):

;;; DESC-DOC prints the specified kind of documentation about the given Name.
;;; If Name is null, or not a valid name, then don't print anything.
;;;
(defun desc-doc (name kind kind-doc)
  (when (and name (typep name '(or symbol cons)))
    (let ((doc (documentation name kind)))
      (when doc
	(format t "~&~@(~A documentation:~)~&  ~A"
		(or kind-doc kind) doc)))))


;;; DESCRIBE-FUNCTION-NAME  --  Internal
;;;
;;;    Describe various stuff about the functional semantics attached to the
;;; specified Name.  Type-Spec is the function type specifier extracted from
;;; the definition, or NIL if none.
;;;
(defun describe-function-name (name type-spec)
  (let ((*print-level* nil)
	(*print-length* nil))
    (multiple-value-bind
	(type where)
	(if (or (symbolp name) (and (listp name) (eq (car name) 'setf)))
	    (values (type-specifier (info function type name))
		    (info function where-from name))
	    (values type-spec :defined))
      (when (consp type)
	(format t "~&Its ~(~A~) argument types are:~%  ~S"
		where (second type))
	(format t "~&Its result type is:~%  ~S" (third type)))))
      
  (let ((inlinep (info function inlinep name)))
    (when inlinep
      (format t "~&It is currently declared ~(~A~);~
		 ~:[no~;~] expansion is available."
	      inlinep (info function inline-expansion name)))))


;;; DESCRIBE-FUNCTION-INTERPRETED  --  Internal
;;;
;;;    Interpreted function describing; handles both closure and non-closure
;;; functions.  Instead of printing the compiled-from info, we print the
;;; definition.
;;;
(defun describe-function-interpreted (x kind name)
  (multiple-value-bind (exp closure-p dname)
		       (eval:interpreted-function-lambda-expression x)
    (let ((args (eval:interpreted-function-arglist x)))
      (format t "~&~@(~@[~A ~]arguments:~%~)" kind)
      (cond ((not args)
	     (write-string "  There are no arguments."))
	    (t
	     (write-string "  ")
	     (indenting-further *standard-output* 2
	       (prin1 args)))))
    
    (let ((name (or name dname)))
      (desc-doc name 'function kind)
      (unless (eq kind :macro)
	(describe-function-name
	 name
	 (type-specifier (eval:interpreted-function-type x)))))
    
    (when closure-p
      (format t "~&Its closure environment is:")
      (indenting-further *standard-output* 2
	(let ((clos (eval:interpreted-function-closure x)))
	  (dotimes (i (length clos))
	    (format t "~&~D: ~S" i (svref clos i))))))
    
    (format t "~&Its definition is:~%  ~S" exp)))


;;; PRINT-COMPILED-FROM  --  Internal
;;;
;;;    Print information from the debug-info about where X was compiled from.
;;;
(defun print-compiled-from (x)
  (let ((info (kernel:code-debug-info (kernel:function-code-header x))))
    (when info
      (let ((sources (c::compiled-debug-info-source info)))
	(format t "~&On ~A it was compiled from:"
		(format-universal-time nil
				       (c::debug-source-compiled
					(first sources))))
	(dolist (source sources)
	  (let ((name (c::debug-source-name source)))
	    (ecase (c::debug-source-from source)
	      (:file
	       (format t "~&~A~%  Created: " (namestring name))
	       (ext:format-universal-time t (c::debug-source-created source))
	       (let ((comment (c::debug-source-comment source)))
		 (when comment
		   (format t "~&  Comment: ~A" comment))))
	      (:stream (format t "~&~S" name))
	      (:lisp (format t "~&~S" name)))))))))


;;; DESCRIBE-FUNCTION-COMPILED  --  Internal
;;;
;;;    Describe a compiled function.  The closure case calls us to print the
;;; guts.
;;;
(defun describe-function-compiled (x kind name)
  (let ((args (%function-header-arglist x)))
    (format t "~&~@(~@[~A ~]arguments:~%~)" kind)
    (cond ((not args)
	   (format t "  There is no argument information available."))
	  ((string= args "()")
	   (write-string "  There are no arguments."))
	  (t
	   (write-string "  ")
	   (indenting-further *standard-output* 2
	     (write-string args)))))

  (let ((name (or name (%function-header-name x))))
    (desc-doc name 'function kind)
    (unless (eq kind :macro)
      (describe-function-name name (%function-header-type x))))
    
  (print-compiled-from x))


;;; DESCRIBE-FUNCTION  --  Internal
;;;
;;;    Describe a function with the specified kind and name.  The latter
;;; arguments provide some information about where the function came from. Kind
;;; NIL means not from a name.
;;;
(defun describe-function (x &optional (kind nil) name)
  (declare (type function x) (type (member :macro :function nil) kind))
  (fresh-line)
  (ecase kind
    (:macro (format t "Macro-function: ~S" x))
    (:function (format t "Function: ~S" x))
    ((nil)
     (format t "~S is function." x)))
  (case (get-type x)
    (#.vm:closure-header-type
     (cond ((eval:interpreted-function-p x)
	    (describe-function-interpreted x kind name))
	   (t
	    (describe-function-compiled (%closure-function x) kind name)
	    (format t "~&Its closure environment is:")
	    (indenting-further *standard-output* 8)
	    (dotimes (i (- (get-closure-length x) (1- vm:closure-info-offset)))
	      (format t "~&~D: ~S" i (%closure-index-ref x i))))))
    ((#.vm:function-header-type #.vm:closure-function-header-type)
     (describe-function-compiled x kind name))
    (#.vm:funcallable-instance-header-type
     (pcl::describe-object x *standard-output*))
    (t
     (format t "~&It is an unknown type of function."))))


(defun describe-symbol (x)
  (let ((package (symbol-package x)))
    (if package
	(multiple-value-bind (symbol status)
			     (find-symbol (symbol-name x) package)
	  (declare (ignore symbol))
	  (format t "~&~A is an ~A symbol in the ~A package." x
		  (string-downcase (symbol-name status))
		  (package-name (symbol-package x))))
	(format t "~&~A is an uninterned symbol." x)))
  ;;
  ;; Describe the value cell.
  (let* ((kind (info variable kind x))
	 (wot (ecase kind
		(:special "special variable")
		(:constant "constant")
		(:global "undefined variable")
		(:alien nil))))
    (cond
     ((eq kind :alien)
      (let ((info (info variable alien-info x)))
	(format t "~&~@<It is an alien at #x~8,'0X of type ~3I~:_~S.~:>~%"
		(sap-int (eval (alien::heap-alien-info-sap-form info)))
		(alien-internals:unparse-alien-type
		 (alien::heap-alien-info-type info)))
	(format t "~@<It's current value is ~3I~:_~S.~:>"
		(eval x))))
     ((boundp x)
      (let ((value (symbol-value x)))
	(format t "~&It is a ~A; its value is ~S." wot value)
	(describe value)))
     ((not (eq kind :global))
      (format t "~&It is a ~A; no current value." wot)))

    (when (eq (info variable where-from x) :declared)
      (format t "~&Its declared type is ~S."
	      (type-specifier (info variable type x))))

    (desc-doc x 'variable kind))
  ;;
  ;; Describe the function cell.
  (cond ((macro-function x)
	 (describe-function (macro-function x) :macro x))
	((special-form-p x)
	 (desc-doc x 'function "Special form"))
	((fboundp x)
	 (describe-function (fdefinition x) :function x)))
  ;;
  ;; Print other documentation.
  (desc-doc x 'structure "Structure")
  (desc-doc x 'type "Type")
  (desc-doc x 'setf "Setf macro")
  (dolist (assoc (info random-documentation stuff x))
    (format t "~&Documentation on the ~(~A~):~%~A" (car assoc) (cdr assoc)))
  ;;
  ;; Print out properties, possibly ignoring implementation details.
  (do ((plist (symbol-plist X) (cddr plist)))
      ((null plist) ())
    (unless (member (car plist) *implementation-properties*)
      (format t "~&Its ~S property is ~S." (car plist) (cadr plist))
      (describe (cadr plist)))))
