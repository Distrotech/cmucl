;;; -*- Log: code.log; Package: Lisp -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/sharpm.lisp,v 1.9 1992/02/12 01:44:58 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;; Spice Lisp Interim Sharp Macro
;;; Written by David Dill
;;; Runs in the standard Spice Lisp environment.
;;; This uses the special std-lisp-readtable, which is internal to READER.LISP
;;;
(in-package "LISP")
(export '(*read-eval*))


;;; declared in READ.LISP

(proclaim '(special *read-suppress* std-lisp-readtable *bq-vector-flag*))

(defun ignore-numarg (sub-char numarg)
  (when numarg
    (warn "Numeric argument ignored in #~D~A." numarg sub-char)))

(defun sharp-backslash (stream backslash numarg)
  (ignore-numarg backslash numarg)
  (unread-char backslash stream)
  (let* ((*readtable* std-lisp-readtable)
	 (charstring (read-extended-token stream)))
    (declare (simple-string charstring))
    (cond (*read-suppress* nil)
	  ((= (the fixnum (length charstring)) 1)
	   (char charstring 0))
	  ((name-char charstring))
	  (t
	   (%reader-error stream "Unrecognized character name: ~S"
			  charstring)))))


(defun sharp-quote (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  ;; 4th arg tells read that this is a recrusive call.
  `(function ,(read stream t nil t)))

(defun sharp-left-paren (stream ignore length)
  (declare (ignore ignore) (special *backquote-count*))
  (let* ((list (read-list stream nil))
	 (listlength (length list)))
    (declare (list list)
	     (fixnum listlength))
    (cond (*read-suppress* nil)
	  ((zerop *backquote-count*)
	   (if length
	       (cond ((> listlength (the fixnum length))
		      (%reader-error
		       stream
		       "Vector longer than specified length: #~S~S"
		       length list))
		     (t
		      (fill (the simple-vector
				 (replace (the simple-vector
					       (make-array length))
					  list))
			    (car (last list))
			    :start listlength)))
	       (coerce list 'vector)))
	  (t (cons *bq-vector-flag* list)))))

(defun sharp-star (stream ignore numarg)
  (declare (ignore ignore))
  (multiple-value-bind (bstring escape-appearedp)
		       (read-extended-token stream)
    (declare (simple-string bstring))
    (cond (*read-suppress* nil)
	  (escape-appearedp
	   (%reader-error stream "Escape character appeared after #*"))
	  ((and numarg (zerop (length bstring)) (not (zerop numarg)))
	   (%reader-error
	    stream
	    "You have to give a little bit for non-zero #* bit-vectors."))
	  ((or (null numarg) (>= (the fixnum numarg) (length bstring)))
	   (let* ((len1 (length bstring))
		  (last1 (1- len1))
		  (len2 (or numarg len1))
		  (bvec (make-array len2 :element-type 'bit
				    :initial-element 0)))
	     (declare (fixnum len1 last1 len2))
	     (do ((i 0 (1+ i))
		  (char ()))
		 ((= i len2))
	       (declare (fixnum i))
	       (setq char (elt bstring (if (< i len1) i last1)))
	       (setf (elt bvec i)
		     (cond ((char= char #\0) 0)
			   ((char= char #\1) 1)
			   (t
			    (%reader-error
			     stream
			     "Illegal element given for bit-vector: ~S"
			     char)))))
	     bvec))
	  (t
	   (%reader-error stream
			 "Bit vector is longer than specified length #~A*~A"
			 numarg bstring)))))


(defun sharp-colon (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (multiple-value-bind (token escapep colon)
		       (read-extended-token stream)
    (declare (simple-string token) (ignore escapep))
    (cond
     (*read-suppress* nil)
     (colon
      (%reader-error stream "Symbol following #: contains a package marker: ~S"
		     token))
     ((eql (length token) 0)
      (let ((ch (read-char stream nil nil t)))
	(when ch
	  (%reader-error stream
			 "Illegal terminating character after a colon: ~S."
			 ch))
	(reader-eof-error stream "after a colon")))
     (t
      (make-symbol token)))))

;;;; #. handling.

(defvar *read-eval* t
  "If false, then the #. read macro is disabled.")

(defun sharp-dot (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (let ((token (read stream t nil t)))
    (unless *read-suppress*
      (unless *read-eval*
	(%reader-error stream
		      "Attempt to read #. while *READ-EVAL* is bound to NIL."))
      (eval token))))


;;;; Numeric radix stuff:
 
(defun sharp-R (stream sub-char radix)
  (cond (*read-suppress*
	 (read-extended-token stream)
	 nil)
	((not radix)
	 (%reader-error stream "Radix missing in #R."))
	((not (<= 2 radix 36))
	 (%reader-error stream "Illegal radix for #R: ~D." radix))
	(t
	 (let ((res (let ((*read-base* radix))
		      (read stream t nil t))))
	   (unless (typep res 'rational)
	     (%reader-error stream "#~A (base ~D) value is not a rational: ~S."
			   sub-char radix res))
	   res))))

(defun sharp-B (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (sharp-r stream sub-char 2))

(defun sharp-O (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (sharp-r stream sub-char 8))

(defun sharp-X (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (sharp-r stream sub-char 16))



(defun sharp-A (stream ignore dimensions)
  (declare (ignore ignore))
  (when *read-suppress*
    (read stream t nil t)
    (return-from sharp-A nil))
  (unless dimensions (%reader-error stream "No dimensions argument to #A."))
  (if (> dimensions 0)
      (let ((dlist (make-list dimensions))
	    (init-list
	     (if (char= (read-char stream t) #\()
		 (read-list stream nil)
		 (%reader-error stream "Array values must be a list."))))
	(do ((dl dlist (cdr dl))
	     (il init-list (car il)))
	    ;; I think the nreverse is causing the problem.
	    ((null dl))
	  (if (listp il)
	      (rplaca dl (length il))
	      (%reader-error
	       stream
	       "Initial contents for #A is inconsistent with ~
		dimensions: #~SA~S" dimensions init-list)))
	(make-array dlist :initial-contents init-list))
      (make-array nil :initial-element (read stream t nil t))))


(defun sharp-S (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  ;;this needs to know about defstruct implementation
  (when *read-suppress*
    (read stream t nil t)
    (return-from sharp-S nil))
  (let ((body (if (char= (read-char stream t) #\( )
		  (read-list stream nil)
		  (%reader-error stream "Non-list following #S"))))
    (cond ((listp body)
	   (unless (symbolp (car body))
	     (%reader-error stream
			   "Structure type is not a symbol: ~S" (car body)))
	   (let ((defstruct (info type defined-structure-info (car body))))
	     (unless defstruct
	       (%reader-error stream
			     "~S is not a defined structure type."
			     (car body)))
	     (unless (c::dd-constructors defstruct)
	       (%reader-error
		stream "The ~S structure does not have a default constructor."
		(car body)))
	     (do ((arg (cdr body) (cddr arg))
		  (res ()))
		 ((endp arg)
		  (apply (car (c::dd-constructors defstruct)) res))
	       (push (cadr arg) res)
	       (push (intern (string (car arg)) *keyword-package*) res))))
	  (t (%reader-error stream "Non-list following #S: ~S" body)))))



;;;; #=/##

;;; Holds objects already seen by CIRCLE-SUBST.
;;;
(defvar *sharp-equal-circle-table*)

;; This function is kind of like to NSUBLIS, but checks for circularities and
;; substitutes in arrays and structures as well as lists.  The first arg is an
;; alist of the things to be replaced assoc'd with the things to replace them.
;;
(defun circle-subst (old-new-alist tree)
  (cond ((not (typep tree '(or cons (array t) structure)))
	 (let ((entry (find tree old-new-alist :key #'second)))
	   (if entry (third entry) tree)))
	((null (gethash tree *sharp-equal-circle-table*))
	 (setf (gethash tree *sharp-equal-circle-table*) t)
	 (cond ((structurep tree)
		(dotimes (i (structure-length tree) tree)
		  (structure-set tree i
				 (circle-subst old-new-alist
					       (structure-ref tree i)))))
	       ((arrayp tree)
		(with-array-data ((data tree) (start) (end))
		  (declare (fixnum start end))
		  (do ((i start (1+ i)))
		      ((>= i end))
		    (setf (aref data i)
			  (circle-subst old-new-alist (aref data i)))))
		tree)
	       (t
		(let ((a (circle-subst old-new-alist (car tree)))
		      (d (circle-subst old-new-alist (cdr tree))))
		  (if (eq a (car tree))
		      tree
		      (rplaca tree a))
		  (if (eq d (cdr tree))
		      tree
		      (rplacd tree d)))
		  tree)))
	(t tree)))

;;; Sharp-equal works as follows.  When a label is assigned (ie when #= is
;;; called) we GENSYM a symbol is which is used as an unforgeable tag.
;;; *SHARP-SHARP-ALIST* maps the integer tag to this gensym.
;;;
;;; When SHARP-SHARP encounters a reference to a label, it returns the symbol
;;; assoc'd with the label.  Resolution of the reference is deferred until the
;;; read done by #= finishes.  Any already resolved tags (in
;;; *SHARP-EQUAL-ALIST*) are simply returned.
;;;
;;; After reading of the #= form is completed, we add an entry to
;;; *SHARP-EQUAL-ALIST* that maps the gensym tag to the resolved object.  Then
;;; for each entry in the *SHARP-SHARP-ALIST, the current object is searched
;;; and any uses of the gensysm token are replaced with the actual value.
;;;
(defvar *sharp-sharp-alist* ())
;;;
(defun sharp-equal (stream ignore label)
  (declare (ignore ignore))
  (when *read-suppress* (return-from sharp-equal (values)))
  (unless label
    (%reader-error stream "Missing label for #=." label))
  (when (or (assoc label *sharp-sharp-alist*)
	    (assoc label *sharp-equal-alist*))
    (%reader-error stream "Multiply defined label: #~D=" label))
  (let* ((tag (gensym))
	 (*sharp-sharp-alist* (acons label tag *sharp-sharp-alist*))
	 (obj (read stream t nil t)))
    (when (eq obj tag)
      (%reader-error stream "Have to tag something more than just #~D#."
		     label))
    (push (list label tag obj) *sharp-equal-alist*)
    (let ((*sharp-equal-circle-table* (make-hash-table :test #'eq :size 20)))
      (circle-subst *sharp-equal-alist* obj))))
;;;
(defun sharp-sharp (stream ignore label)
  (declare (ignore ignore))
  (when *read-suppress* (return-from sharp-sharp nil))
  (unless label
    (%reader-error stream "Missing label for ##." label))

  (let ((entry (assoc label *sharp-equal-alist*)))
    (if entry
	(third entry)
	(let ((pair (assoc label *sharp-sharp-alist*)))
	  (unless pair
	    (%reader-error stream "Object is not labelled #~S#" label))
	  (cdr pair)))))


;;;; #+/-

(flet ((guts (stream not-p)
	 (unless (if (handler-case
			 (let ((*package* *keyword-package*)
			       (*read-suppress* nil))
			   (featurep (read stream t nil t)))
		       (reader-package-error
			(condition)
			(declare (ignore condition))
			nil))
		     (not not-p)
		     not-p)
	   (let ((*read-suppress* t))
	     (read stream t nil t)))
	 (values)))

  (defun sharp-plus (stream sub-char numarg)
    (ignore-numarg sub-char numarg)
    (guts stream nil))

  (defun sharp-minus (stream sub-char numarg)
    (ignore-numarg sub-char numarg)
    (guts stream t)))

(defun sharp-C (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  ;;next thing better be a list of two numbers.
  (let ((cnum (read stream t nil t)))
    (when *read-suppress* (return-from sharp-c nil))
    (if (and (listp cnum) (= (length cnum) 2))
	(complex (car cnum) (cadr cnum))
	(%reader-error stream "Illegal complex number format: #C~S" cnum))))

(defun sharp-vertical-bar (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (prepare-for-fast-read-char stream
    (do ((level 1)
	 (prev (fast-read-char) char)
	 (char (fast-read-char) (fast-read-char)))
	(())
      (cond ((and (char= prev #\|) (char= char #\#))
	     (setq level (1- level))
	     (when (zerop level)
	       (done-with-fast-read-char)
	       (return (values)))
	     (setq char (fast-read-char)))
	    ((and (char= prev #\#) (char= char #\|))
	     (setq char (fast-read-char))
	     (setq level (1+ level)))))))

(defun sharp-illegal (stream sub-char ignore)
  (declare (ignore ignore))
  (%reader-error stream "Illegal sharp character ~S" sub-char))

(defun sharp-P (stream sub-char numarg)
  (ignore-numarg sub-char numarg)
  (parse-namestring (read stream t nil t)))

(defun sharp-init ()
  (declare (special std-lisp-readtable))
  (let ((*readtable* std-lisp-readtable))
    (make-dispatch-macro-character #\# t)
    (set-dispatch-macro-character #\# #\\ #'sharp-backslash)
    (set-dispatch-macro-character #\# #\' #'sharp-quote)
    (set-dispatch-macro-character #\# #\( #'sharp-left-paren)
    (set-dispatch-macro-character #\# #\* #'sharp-star)
    (set-dispatch-macro-character #\# #\: #'sharp-colon)
    (set-dispatch-macro-character #\# #\. #'sharp-dot)
    (set-dispatch-macro-character #\# #\R #'sharp-R)
    (set-dispatch-macro-character #\# #\r #'sharp-R)
    (set-dispatch-macro-character #\# #\B #'sharp-B)
    (set-dispatch-macro-character #\# #\b #'sharp-B)
    (set-dispatch-macro-character #\# #\O #'sharp-O)
    (set-dispatch-macro-character #\# #\o #'sharp-O)
    (set-dispatch-macro-character #\# #\X #'sharp-X)
    (set-dispatch-macro-character #\# #\x #'sharp-X)
    (set-dispatch-macro-character #\# #\A #'sharp-A)
    (set-dispatch-macro-character #\# #\a #'sharp-A)
    (set-dispatch-macro-character #\# #\S #'sharp-S)
    (set-dispatch-macro-character #\# #\s #'sharp-S)
    (set-dispatch-macro-character #\# #\= #'sharp-equal)
    (set-dispatch-macro-character #\# #\# #'sharp-sharp)
    (set-dispatch-macro-character #\# #\+ #'sharp-plus)
    (set-dispatch-macro-character #\# #\- #'sharp-minus)
    (set-dispatch-macro-character #\# #\C #'sharp-C)
    (set-dispatch-macro-character #\# #\c #'sharp-C)
    (set-dispatch-macro-character #\# #\| #'sharp-vertical-bar)
    (set-dispatch-macro-character #\# #\p #'sharp-p)
    (set-dispatch-macro-character #\# #\P #'sharp-p)
    (set-dispatch-macro-character #\# #\tab #'sharp-illegal)
    (set-dispatch-macro-character #\# #\  #'sharp-illegal)
    (set-dispatch-macro-character #\# #\) #'sharp-illegal)
    (set-dispatch-macro-character #\# #\< #'sharp-illegal)
    (set-dispatch-macro-character #\# #\form #'sharp-illegal)
    (set-dispatch-macro-character #\# #\return #'sharp-illegal)))
