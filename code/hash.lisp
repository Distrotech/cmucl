;;; -*- Package: CL -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/hash.lisp,v 1.20 1992/10/26 03:44:16 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; Hashing and hash table functions for Spice Lisp.
;;; Originally written by Skef Wholey.
;;; Everything except SXHASH rewritten by William Lott.
;;;
(in-package :common-lisp)

(export '(hash-table hash-table-p make-hash-table
	  gethash remhash maphash clrhash
	  hash-table-count with-hash-table-iterator
	  hash-table-rehash-size hash-table-rehash-threshold
	  hash-table-size hash-table-test
	  sxhash))

(in-package :ext)
(export '(*hash-table-tests*))

(in-package :common-lisp)


;;;; The hash-table structure.

(defstruct (hash-table
	    (:constructor %make-hash-table)
	    (:print-function %print-hash-table)
	    (:make-load-form-fun make-hash-table-load-form))
  "Structure used to implement hash tables."
  ;;
  ;; The type of hash table this is.  Only used for printing and as part of
  ;; the exported interface.
  (test (required-argument) :type symbol :read-only t)
  ;;
  ;; The function used to compare two keys.  Returns T if they are the same
  ;; and NIL if not.
  (test-fun (required-argument) :type function :read-only t)
  ;;
  ;; The function used to compute the hashing of a key.  Returns two values:
  ;; the index hashing and T if that might change with the next GC.
  (hash-fun (required-argument) :type function :read-only t)
  ;;
  ;; How much to grow the hash table by when it fills up.  If an index, then
  ;; add that amount.  If a floating point number, then multiple it by that.
  (rehash-size (required-argument) :type (or index (float (1.0))) :read-only t)
  ;;
  ;; How full the hash table has to get before we rehash.
  (rehash-threshold (required-argument) :type (real 0 1) :read-only t)
  ;;
  ;; (* rehash-threshold (length table)), saved here so we don't have to keep
  ;; recomputing it.
  (rehash-trigger (required-argument) :type index)
  ;;
  ;; The current number of entries in the table.
  (number-entries 0 :type index)
  ;;
  ;; Vector of ht-buckets.
  (table (required-argument) :type simple-vector))
;;;
(defun %print-hash-table (ht stream depth)
  (declare (ignore depth))
  (print-unreadable-object (ht stream :identity t)
    (format stream "~A hash table, ~D entr~@:P"
	    (symbol-name (hash-table-test ht))
	    (hash-table-number-entries ht))))

(defconstant max-hash most-positive-fixnum)

(deftype hash ()
  `(integer 0 ,max-hash))


(defstruct hash-table-bucket
  ;;
  ;; The hashing associated with key, kept around so we don't have to recompute
  ;; it each time.  When NIL, then just use %primitive make-fixnum.  We don't
  ;; cache the results of make-fixnum, because it can change with a GC.
  (hash nil :type (or hash null))
  ;;
  ;; The key and value, originally supplied by the user.
  (key nil :type t)
  (value nil :type t)
  ;;
  ;; The next bucket, or NIL if there are no more.
  (next nil :type (or hash-table-bucket null)))



;;;; Utility functions.

(declaim (inline pointer-hash))
(defun pointer-hash (key)
  (declare (values hash))
  (truly-the hash (%primitive make-fixnum key)))

(declaim (inline eq-hash))
(defun eq-hash (key)
  (declare (values hash (member t nil)))
  (values (pointer-hash key)
	  (oddp (get-lisp-obj-address key))))

(declaim (inline eql-hash))
(defun eql-hash (key)
  (declare (values hash (member t nil)))
  (if (numberp key)
      (equal-hash key)
      (eq-hash key)))

(declaim (inline equal-hash))
(defun equal-hash (key)
  (declare (values hash (member t nil)))
  (values (sxhash key) nil))


(defun almost-primify (num)
  (declare (type index num))
  "Almost-Primify returns an almost prime number greater than or equal
   to NUM."
  (if (= (rem num 2) 0)
      (setq num (+ 1 num)))
  (if (= (rem num 3) 0)
      (setq num (+ 2 num)))
  (if (= (rem num 7) 0)
      (setq num (+ 4 num)))
  num)



;;;; Construction and simple accessors.

;;; *HASH-TABLE-TESTS* -- Public.
;;; 
(defvar *hash-table-tests* nil)

;;; MAKE-HASH-TABLE -- public.
;;; 
(defun make-hash-table (&key (test 'eql) (size 65) (rehash-size 1.5)
			     (rehash-threshold 1))
  "Creates and returns a new hash table.  The keywords are as follows:
     :TEST -- Indicates what kind of test to use.  Only EQ, EQL, and EQUAL
       are currently supported.
     :SIZE -- A hint as to how many elements will be put in this hash
       table.
     :REHASH-SIZE -- Indicates how to expand the table when it fills up.
       If an integer, add space for that many elements.  If a floating
       point number (which must be greater than 1.0), multiple the size
       by that amount.
     :REHASH-THRESHOLD -- Indicates how dense the table can become before
       forcing a rehash.  Can be any real number between 0 and 1 (inclusive)."
  (declare (type (or function (member eq eql equal)) test)
	   (type index size)
	   (type (or index (float (1.0))) rehash-size)
	   (type (real 0 1) rehash-threshold))
  (multiple-value-bind
      (test test-fun hash-fun)
      (cond ((or (eq test #'eq) (eq test 'eq))
	     (values 'eq #'eq #'eq-hash))
	    ((or (eq test #'eql) (eq test 'eql))
	     (values 'eql #'eql #'eql-hash))
	    ((or (eq test #'equal) (eq test 'equal))
	     (values 'equal #'equal #'equal-hash))
	    (t
	     (dolist (info *hash-table-tests*
			   (error "Unknown :TEST for MAKE-HASH-TABLE: ~S"
				  test))
	       (destructuring-bind
		   (test-name test-fun hash-fun)
		   info
		 (when (or (eq test test-name) (eq test test-fun))
		   (return (values test-name test-fun hash-fun)))))))
    (let* ((size (ceiling size rehash-threshold))
	   (length (if (<= size 37) 37 (almost-primify size)))
	   (vector (make-array length :initial-element nil)))
      (declare (type index size length)
	       (type simple-vector vector))
      (%make-hash-table
       :test test
       :test-fun test-fun
       :hash-fun hash-fun
       :rehash-size rehash-size
       :rehash-threshold rehash-threshold
       :rehash-trigger (* size rehash-threshold)
       :table vector))))

(defun hash-table-count (hash-table)
  "Returns the number of entries in the given HASH-TABLE."
  (declare (type hash-table hash-table)
	   (values index))
  (hash-table-number-entries hash-table))

(setf (documentation 'hash-table-rehash-size 'function)
      "Return the rehash-size HASH-TABLE was created with.")

(setf (documentation 'hash-table-rehash-threshold 'function)
      "Return the rehash-threshold HASH-TABLE was created with.")

(defun hash-table-size (hash-table)
  "Return a size that can be used with MAKE-HASH-TABLE to create a hash
   table that can hold however many entries HASH-TABLE can hold without
   having to be grown."
  (hash-table-rehash-trigger hash-table))

(setf (documentation 'hash-table-test 'function)
      "Return the test HASH-TABLE was created with.")


;;;; Accessing functions.

;;; REHASH -- internal.
;;;
;;; Make a new vector for TABLE.  If GROW is NIL, use the same size as before,
;;; otherwise extend the table based on the rehash-size.
;;;
(defun rehash (table grow)
  (declare (type hash-table table))
  (let* ((old-vector (hash-table-table table))
	 (old-length (length old-vector))
	 (new-length
	  (if grow
	      (let ((rehash-size (hash-table-rehash-size table)))
		(etypecase rehash-size
		  (fixnum
		   (+ rehash-size old-length))
		  (float
		   (ceiling (* rehash-size old-length)))))
	      old-length))
	 (new-vector (make-array new-length :initial-element nil)))
    (dotimes (i old-length)
      (do ((bucket (svref old-vector i) next)
	   (next nil))
	  ((null bucket))
	(setf next (hash-table-bucket-next bucket))
	(let* ((old-hashing (hash-table-bucket-hash bucket))
	       (hashing (cond
			 (old-hashing old-hashing)
			 (t
			  (set-header-data new-vector
					   vm:vector-valid-hashing-subtype)
			  (pointer-hash (hash-table-bucket-key bucket)))))
	       (index (rem hashing new-length)))
	  (setf (hash-table-bucket-next bucket) (svref new-vector index))
	  (setf (svref new-vector index) bucket)))
      ;; We clobber the old vector contents so that if it is living in
      ;; static space it won't keep ahold of pointers into dynamic space.
      (setf (svref old-vector i) nil))
    (setf (hash-table-table table) new-vector)
    (unless (= new-length old-length)
      (setf (hash-table-rehash-trigger table)
	    (let ((threshold (hash-table-rehash-threshold table)))
	      ;; Optimize the threshold=1 case so we don't have to use
	      ;; generic arithmetic in the most common case.
	      (if (eql threshold 1)
		  new-length
		  (truncate (* threshold new-length)))))))
  (undefined-value))

;;; GETHASH -- Public.
;;; 
(defun gethash (key hash-table &optional default)
  "Finds the entry in HASH-TABLE whose key is KEY and returns the associated
   value and T as multiple values, or returns DEFAULT and NIL if there is no
   such entry.  Entries can be added using SETF."
  (declare (type hash-table hash-table)
	   (values t (member t nil)))
  (without-gcing
   (when (= (get-header-data (hash-table-table hash-table))
	    vm:vector-must-rehash-subtype)
     (rehash hash-table nil))
   (let* ((vector (hash-table-table hash-table))
	  (length (length vector))
	  (hashing (funcall (hash-table-hash-fun hash-table) key))
	  (index (rem hashing length))
	  (test-fun (hash-table-test-fun hash-table)))
     (do ((bucket (svref vector index) (hash-table-bucket-next bucket)))
	 ((null bucket) (values default nil))
       (let ((bucket-hashing (hash-table-bucket-hash bucket)))
	 (when (if bucket-hashing
		   (and (= bucket-hashing hashing)
			(funcall test-fun key (hash-table-bucket-key bucket)))
		   (eq key (hash-table-bucket-key bucket)))
	   (return (values (hash-table-bucket-value bucket) t))))))))

;;; %PUTHASH -- public setf method.
;;; 
(defun %puthash (key hash-table value)
  (declare (type hash-table hash-table))
  (without-gcing
   (let ((entries (1+ (hash-table-number-entries hash-table))))
     (setf (hash-table-number-entries hash-table) entries)
     (cond ((> entries (hash-table-rehash-trigger hash-table))
	    (rehash hash-table t))
	   ((= (get-header-data (hash-table-table hash-table))
	       vm:vector-must-rehash-subtype)
	    (rehash hash-table nil))))
   (multiple-value-bind
       (hashing eq-based)
       (funcall (hash-table-hash-fun hash-table) key)
     (let* ((vector (hash-table-table hash-table))
	    (length (length vector))
	    (index (rem hashing length))
	    (first-bucket (svref vector index))
	    (test-fun (hash-table-test-fun hash-table)))
       (do ((bucket first-bucket (hash-table-bucket-next bucket)))
	   ((null bucket)
	    (when eq-based
	      (set-header-data vector vm:vector-valid-hashing-subtype))
	    (setf (svref vector index)
		  (make-hash-table-bucket
		   :hash (unless eq-based hashing)
		   :key key
		   :value value
		   :next first-bucket)))
	 (let ((bucket-hashing (hash-table-bucket-hash bucket)))
	   (when (if bucket-hashing
		     (and (= bucket-hashing hashing)
			  (funcall test-fun
				   key (hash-table-bucket-key bucket)))
		     (eq key (hash-table-bucket-key bucket)))
	     (setf (hash-table-bucket-value bucket) value)
	     (decf (hash-table-number-entries hash-table))
	     (return)))))))
  value)

;;; REMHASH -- public.
;;; 
(defun remhash (key hash-table)
  "Remove the entry in HASH-TABLE associated with KEY.  Returns T if there
   was such an entry, and NIL if not."
  (declare (type hash-table hash-table)
	   (values (member t nil)))
  (without-gcing
   (when (= (get-header-data (hash-table-table hash-table))
	    vm:vector-must-rehash-subtype)
     (rehash hash-table nil))
   (let* ((vector (hash-table-table hash-table))
	  (length (length vector))
	  (hashing (funcall (hash-table-hash-fun hash-table) key))
	  (index (rem hashing length))
	  (test-fun (hash-table-test-fun hash-table)))
     (do ((prev nil bucket)
	  (bucket (svref vector index) (hash-table-bucket-next bucket)))
	 ((null bucket) nil)
       (let ((bucket-hashing (hash-table-bucket-hash bucket)))
	 (when (if bucket-hashing
		   (and (= bucket-hashing hashing)
			(funcall test-fun key (hash-table-bucket-key bucket)))
		   (eq key (hash-table-bucket-key bucket)))
	   (if prev
	       (setf (hash-table-bucket-next prev)
		     (hash-table-bucket-next bucket))
	       (setf (svref vector index)
		     (hash-table-bucket-next bucket)))
	   (decf (hash-table-number-entries hash-table))
	   (return t)))))))

;;; CLRHASH -- public.
;;; 
(defun clrhash (hash-table)
  "This removes all the entries from HASH-TABLE and returns the hash table
   itself."
  (let ((vector (hash-table-table hash-table)))
    (dotimes (i (length vector))
      (setf (aref vector i) nil))
    (setf (hash-table-number-entries hash-table) 0)
    (set-header-data vector vm:vector-normal-subtype))
  hash-table)



;;;; MAPHASH and WITH-HASH-TABLE-ITERATOR

(declaim (maybe-inline maphash))
(defun maphash (map-function hash-table)
  "For each entry in HASH-TABLE, calls MAP-FUNCTION on the key and value
   of the entry; returns NIL."
  (declare (type (or function symbol) map-function)
	   (type hash-table hash-table))
  (let ((fun (etypecase map-function
	       (function
		map-function)
	       (symbol
		(symbol-function map-function))))
	(vector (hash-table-table hash-table)))
    (dotimes (i (length vector))
      (do ((bucket (svref vector i) (hash-table-bucket-next bucket)))
	  ((null bucket))
	(funcall fun
		 (hash-table-bucket-key bucket)
		 (hash-table-bucket-value bucket))))))


(defmacro with-hash-table-iterator ((function hash-table) &body body)
  "WITH-HASH-TABLE-ITERATOR ((function hash-table) &body body)
   provides a method of manually looping over the elements of a hash-table.
   function is bound to a generator-macro that, withing the scope of the
   invocation, returns three values.  First, whether there are any more objects
   in the hash-table, second, the key, and third, the value."
  (let ((n-function (gensym "WITH-HASH-TABLE-ITERRATOR-")))
    `(let ((,n-function
	    (let* ((table ,hash-table)
		   (vector (hash-table-table table))
		   (length (length vector))
		   (index 0)
		   (bucket (svref vector 0)))
	      (labels
		  ((,function ()
		     (cond
		      (bucket
		       (multiple-value-prog1
			   (values t
				   (hash-table-bucket-key bucket)
				   (hash-table-bucket-value bucket))
			 (setf bucket (hash-table-bucket-next bucket))))
		      ((= (incf index) length)
		       (values nil))
		      (t
		       (setf bucket (svref vector index))
		       (,function)))))
		#',function))))
       (macrolet ((,function () '(funcall ,n-function)))
	 ,@body))))



;;;; SXHASH and support functions

;;; The maximum length and depth to which we hash lists.
(defconstant sxhash-max-len 7)
(defconstant sxhash-max-depth 3)

(eval-when (compile eval)

(defconstant sxhash-bits-byte (byte 23 0))
(defconstant sxmash-total-bits 26)
(defconstant sxmash-rotate-bits 7)

(defmacro sxmash (place with)
  (let ((n-with (gensym)))
    `(let ((,n-with ,with))
       (declare (fixnum ,n-with))
       (setf ,place
	     (logxor (ash ,n-with ,(- sxmash-rotate-bits sxmash-total-bits))
		     (ash (logand ,n-with
				  ,(1- (ash 1
					    (- sxmash-total-bits
					       sxmash-rotate-bits))))
			  ,sxmash-rotate-bits)
		     (the fixnum ,place))))))

(defmacro sxhash-simple-string (sequence)
  `(%sxhash-simple-string ,sequence))

(defmacro sxhash-string (sequence)
  (let ((data (gensym))
	(start (gensym))
	(end (gensym)))
    `(with-array-data ((,data ,sequence)
		       (,start)
		       (,end))
       (if (zerop ,start)
	   (%sxhash-simple-substring ,data ,end)
	   (sxhash-simple-string (coerce (the string ,sequence)
					 'simple-string))))))

(defmacro sxhash-list (sequence depth)
  `(if (= ,depth sxhash-max-depth)
       0
       (do ((sequence ,sequence (cdr (the list sequence)))
	    (index 0 (1+ index))
	    (hash 2))
	   ((or (atom sequence) (= index sxhash-max-len)) hash)
	 (declare (fixnum hash index))
	 (sxmash hash (internal-sxhash (car sequence) (1+ ,depth))))))


); eval-when (compile eval)


(defun sxhash (s-expr)
  "Computes a hash code for S-EXPR and returns it as an integer."
  (internal-sxhash s-expr 0))


(defun internal-sxhash (s-expr depth)
  (typecase s-expr
    ;; The pointers and immediate types.
    (list (sxhash-list s-expr depth))
    (fixnum
     (ldb sxhash-bits-byte s-expr))
    (structure
     (internal-sxhash (type-of s-expr) depth))
    ;; Other-pointer types.
    (simple-string (sxhash-simple-string s-expr))
    (symbol (sxhash-simple-string (symbol-name s-expr)))
    (number
     (etypecase s-expr
       (integer (ldb sxhash-bits-byte s-expr))
       (single-float
	(let ((bits (single-float-bits s-expr)))
	  (ldb sxhash-bits-byte
	       (logxor (ash bits (- sxmash-rotate-bits))
		       bits))))
       (double-float
	(let* ((val s-expr)
	       (lo (double-float-low-bits val))
	       (hi (double-float-high-bits val)))
	  (ldb sxhash-bits-byte
	       (logxor (ash lo (- sxmash-rotate-bits))
		       (ash hi (- sxmash-rotate-bits))
		       lo hi))))
       (ratio (the fixnum (+ (internal-sxhash (numerator s-expr) 0)
			     (internal-sxhash (denominator s-expr) 0))))
       (complex (the fixnum (+ (internal-sxhash (realpart s-expr) 0)
			       (internal-sxhash (imagpart s-expr) 0))))))
    (array
     (typecase s-expr
       (string (sxhash-string s-expr))
       (t (array-rank s-expr))))
    ;; Everything else.
    (t 42)))



;;;; Dumping one as a constant.

(defun make-hash-table-load-form (table)
  (values
   `(make-hash-table
     :test ',(hash-table-test table) :size ',(hash-table-size table)
     :rehash-size ',(hash-table-rehash-size table)
     :rehash-threshold ',(hash-table-rehash-threshold table))
   (let ((values nil))
     (declare (inline maphash))
     (maphash #'(lambda (key value)
		  (push (cons key value) values))
	      table)
     (if values
	 `(stuff-hash-table ,table ',values)
	 nil))))

(defun stuff-hash-table (table alist)
  (dolist (x alist)
    (setf (gethash (car x) table) (cdr x))))
