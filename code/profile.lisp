;;; -*- Package: Profile -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/profile.lisp,v 1.5 1992/02/18 19:49:32 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;; Description: Simple profiling facility.
;;;
;;; Author: Skef Wholey, Rob MacLachlan
;;;
;;; Compatibility: Runs in any valid Common Lisp.  Three small implementation-
;;;   dependent changes can be made to improve performance and prettiness.
;;;
;;; Dependencies: The macro Quickly-Get-Time and the function
;;;   Required-Arguments should probably be tailored to the implementation for
;;;   the best results.  They will default to working, albeit inefficent, forms
;;;   in non-CMU implementations.  The Total-Consing macro is used to profile
;;;   consing: in unknown implementations 0 will be used.
;;;   See the "Implementation Parameters" section.
;;;
;;; Note: a timing overhead factor is computed when REPORT-TIME is first
;;; called.  This will be incorrect if profiling code is run in a different
;;; environment than the first call to REPORT-TIME.  For example, saving a core
;;; image on a high performance machine and running it on a low performance one
;;; will result in use of an erroneously small timing overhead factor.  In CMU
;;; CL, this cache is invalidated when a core is saved.
;;;
(in-package "PROFILE")

(export '(*timed-functions* profile unprofile report-time reset-time))


;;;; Implementation dependent interfaces:


(progn
  #-cmu
  (eval-when (compile eval)
    (warn
     "You may want to supply an implementation-specific ~
     Quickly-Get-Time function."))

  (defconstant quick-time-units-per-second internal-time-units-per-second)
  
  (defmacro quickly-get-time ()
    `(the time-type (get-internal-run-time))))


;;; The type of the result from quickly-get-time.
#+cmu
(deftype time-type () '(unsigned-byte 29))
#-cmu
(deftype time-type () 'unsigned-byte)


;;; To avoid unnecessary consing in the "encapsulation" code, we find out the
;;; number of required arguments, and use &rest to capture only non-required
;;; arguments.  The function Required-Arguments returns two values: the first
;;; is the number of required arguments, and the second is T iff there are any
;;; non-required arguments (e.g. &optional, &rest, &key).

#+cmu (progn
(defun required-arguments-aux (name function)
  (let ((type (kernel:%function-header-type function)))
    (typecase type
      (cons
       (let* ((args (cadr type))
	      (pos (position-if
		    #'(lambda (x)
			(and (symbolp x)
			     (let ((name (symbol-name x)))
			       (and (>= (length name) 1)
				    (char= (schar name 0) #\&)))))
		    args)))
	 (if pos
	     (values pos t)
	     (values (length args) nil))))
      (t
       (warn "No argument count information available for:~%  ~S~@
	      Allow for &rest arg consing."
	     name)
       (values 0 t)))))

(defun required-arguments (name)
  (let* ((function (fdefinition name)))
    (case (kernel:get-type function)
      (#.vm:function-header-type (required-arguments-aux name function))
      ((#.vm:closure-header-type #.vm:funcallable-instance-header-type)
       (required-arguments-aux name (kernel:%closure-function function)))
      (t
       (values 0 t)))))

); #+cmu progn

#-cmu
(progn
 (eval-when (compile eval)
   (warn
    "You may want to add an implementation-specific Required-Arguments function."))
 (eval-when (load eval)
   (defun required-arguments (name)
     (declare (ignore name))
     (values 0 t))))



;;; The Total-Consing macro is called to find the total number of bytes consed
;;; since the beginning of time.

#+cmu
(defmacro total-consing () '(the consing-type (ext:get-bytes-consed)))

#-cmu
(progn
  (eval-when (compile eval)
    (warn "No consing will be reported unless a Total-Consing function is ~
           defined."))

  (defmacro total-consing () '0))


;;; The type of the result of TOTAL-CONSING.
#+cmu
(deftype consing-type () '(unsigned-byte 29))
#-cmu
(deftype consing-type () 'unsigned-byte)


;;;; Global data structures:

(defvar *timed-functions* ()
  "List of functions that are currently being timed.")

;;; We associate a PROFILE-INFO structure with each profiled function name.
;;; This holds the functions that we call to manipulate the closure which
;;; implements the encapsulation.
;;;
(defvar *profile-info* (make-hash-table :test #'equal))
(defstruct profile-info
  (name nil)
  (old-definition (error "Required keyword arg not supplied.") :type function)
  (new-definition (error "Required keyword arg not supplied.") :type function)
  (read-time (error "Required keyword arg not supplied.") :type function)
  (reset-time (error "Required keyword arg not supplied.") :type function))

;;; PROFILE-INFO-OR-LOSE  --  Internal
;;;
(defun profile-info-or-lose (name)
  (or (gethash name *profile-info*)
      (error "~S is not a profiled function." name)))


;;; We keep around a bunch of functions that make encapsulations, one of each
;;; (min-args . optional-p) signature we have encountered so far.  We also
;;; precompute a bunch of encapsulation functions.
;;;
(defvar *existing-encapsulations* (make-hash-table :test #'equal))


;;; These variables are used to subtract out the time and consing for recursive
;;; and other dynamically nested profiled calls.  The total resource consumed
;;; for each nested call is added into the appropriate variable.  When the
;;; outer function returns, these amounts are subtracted from the total.
;;;
(defvar *enclosed-time* 0)
(defvar *enclosed-consing* 0)
(defvar *enclosed-profilings* 0)
(proclaim '(type time-type *enclosed-time*))
(proclaim '(type consing-type *enclosed-consing*))
(proclaim '(fixnum *enclosed-profilings*))


;;; The number of seconds a bare function call takes.  Factored into the other
;;; overheads, but not used for itself.
;;;
(defvar *call-overhead*)

;;; The number of seconds that will be charged to a profiled function due to
;;; the profiling code.
(defvar *internal-profile-overhead*)

;;; The number of seconds of overhead for profiling that a single profiled call
;;; adds to the total runtime for the program.
;;;
(defvar *total-profile-overhead*)

(proclaim '(single-float *call-overhead* *internal-profile-overhead*
			 *total-profile-overhead*))


;;;; Profile encapsulations:

(eval-when (compile load eval)

;;; MAKE-PROFILE-ENCAPSULATION  --  Internal
;;;
;;;    Return a lambda expression for a function that (when called with the
;;; function name) will set up that function for profiling.
;;;
;;; A function is profiled by replacing its definition with a closure created
;;; by the following function.  The closure records the starting time, calls
;;; the original function, and records finishing time.  Other closures are used
;;; to perform various operations on the encapsulated function.
;;;
(defun make-profile-encapsulation (min-args optionals-p)
  (let ((required-args ()))
    (dotimes (i min-args)
      (push (gensym) required-args))
    `(lambda (name)
       (let* ((time 0)
	      (count 0)
	      (consed 0)
	      (profile 0)
	      (old-definition (fdefinition name)))
	 (declare (type time-type time) (type consing-type consed)
		  (fixnum count))
	 (pushnew name *timed-functions*)

	 (setf (fdefinition name)
	       #'(lambda (,@required-args
			  ,@(if optionals-p
				`(&rest optional-args)))
		   (incf count)
		   (let ((time-inc 0) (cons-inc 0) (profile-inc 0))
		     (declare (type time-type time-inc)
			      (type consing-type cons-inc)
			      (fixnum profile-inc))
		     (multiple-value-prog1
			 (let ((start-time (quickly-get-time))
			       (start-consed (total-consing))
			       (*enclosed-time* 0)
			       (*enclosed-consing* 0)
			       (*enclosed-profilings* 0))
			   (multiple-value-prog1
			       ,(if optionals-p
				    `(apply old-definition
					    ,@required-args optional-args)
				    `(funcall old-definition ,@required-args))
			     (setq time-inc (- (quickly-get-time) start-time))
			     (setq cons-inc (- (total-consing) start-consed))
			     (setq profile-inc *enclosed-profilings*)
			     (incf time
				   (the time-type
					(- time-inc *enclosed-time*)))
			     (incf consed
				   (the consing-type
					(- cons-inc *enclosed-consing*)))
			     (incf profile profile-inc)))
		       (incf *enclosed-time* time-inc)
		       (incf *enclosed-consing* cons-inc)
		       (incf *enclosed-profilings*
			     (the fixnum (1+ profile-inc)))))))
	 
	 (setf (gethash name *profile-info*)
	       (make-profile-info
		:name name
		:old-definition old-definition
		:new-definition (fdefinition name)
		:read-time
		#'(lambda ()
		    (values count time consed profile))
		:reset-time
		#'(lambda ()
		    (setq count 0)
		    (setq time 0)
		    (setq consed 0)
		    (setq profile 0)
		    t)))))))

); EVAL-WHEN (COMPILE LOAD EVAL)


;;; Precompute some encapsulation functions:
;;;
(eval-when (compile eval)
  (defconstant precomputed-encapsulations 8))
;;;
(macrolet ((frob ()
	     (let ((res ()))
	       (dotimes (i precomputed-encapsulations)
		 (push `(setf (gethash '(,i . nil) *existing-encapsulations*)
			      #',(make-profile-encapsulation i nil))
		       res)
		 (push `(setf (gethash '(,i . t) *existing-encapsulations*)
			      #',(make-profile-encapsulation i t))
		       res))
	       `(progn ,@res))))
  (frob))



;;; Interfaces:

;;; PROFILE-1-FUNCTION  --  Internal
;;;
;;;    Profile the function Name.  If already profiled, unprofile first.
;;;
(defun profile-1-function (name)
  (cond ((fboundp name)
	 (when (gethash name *profile-info*)
	   (warn "~S already profiled, so unprofiling it first." name)
	   (unprofile-1-function name))
	 (multiple-value-bind (min-args optionals-p)
			      (required-arguments name)
	   (funcall (or (gethash (cons min-args optionals-p)
				 *existing-encapsulations*)
			(setf (gethash (cons min-args optionals-p)
				       *existing-encapsulations*)
			      (compile nil (make-profile-encapsulation
					    min-args optionals-p))))
		    name)))
	(t
	 (warn "Ignoring undefined function ~S." name))))


;;; PROFILE  --  Public
;;;
(defmacro profile (&rest names)
  "PROFILE Name*
  Wraps profiling code around the named functions.  As in TRACE, the names are
  not evaluated.  If a function is already profiled, then unprofile and
  reprofile (useful to notice function redefinition.)  If a name is undefined,
  then we give a warning and ignore it.  See also UNPROFILE, REPORT-TIME and
  RESET-TIME."
  `(progn
     ,@(mapcar #'(lambda (name)
		   `(profile-1-function ',name))
	       names)
     (values)))


;;; UNPROFILE  --  Public
;;;
(defmacro unprofile (&rest names)
  "Unwraps the profiling code around the named functions.  Names defaults to
  the list of all currently profiled functions."
  `(dolist (name ,(if names `',names '*timed-functions*) (values))
     (unprofile-1-function name)))


;;; UNPROFILE-1-FUNCTION  --  Internal
;;;
(defun unprofile-1-function (name)
  (let ((info (profile-info-or-lose name)))
    (remhash name *profile-info*)
    (setq *timed-functions*
	  (delete name *timed-functions*
		  :test #'equal))
    (if (eq (fdefinition name) (profile-info-new-definition info))
	(setf (fdefinition name) (profile-info-old-definition info))
	(warn "Preserving current definition of redefined function ~S."
	      name))))


(defmacro report-time (&rest names)
  "Reports the time spent in the named functions.  Names defaults to the list of
  all currently profiled functions."
  `(%report-times ,(if names `',names '*timed-functions*)))


(defstruct (time-info
	    (:constructor make-time-info (name calls time consing)))
  name
  calls
  time
  consing)


;;; COMPENSATE-TIME  --  Internal
;;;
;;;    Return our best guess for the run time in a function, subtracting out
;;; factors for profiling overhead.  We subtract out the internal overhead for
;;; each call to this function, since the internal overhead is the part of the
;;; profiling overhead for a function that is charged to that function.
;;;
;;;    We also subtract out a factor for each call to a profiled function
;;; within this profiled function.  This factor is the total profiling overhead
;;; *minus the internal overhead*.  We don't subtract out the internal
;;; overhead, since it was already subtracted when the nested profiled
;;; functions subtracted their running time from the time for the enclosing
;;; function.
;;;
(defun compensate-time (calls time profile)
  (let ((compensated
	 (- (/ (float time) (float quick-time-units-per-second))
	    (* *internal-profile-overhead* (float calls))
	    (* (- *total-profile-overhead* *internal-profile-overhead*)
	       (float profile)))))
    (if (minusp compensated) 0.0 compensated)))


(defun %report-times (names)
  (unless (boundp '*call-overhead*)
    (compute-time-overhead))
  (let ((info ())
	(no-call ()))
    (dolist (name names)
      (let ((pinfo (profile-info-or-lose name)))
	(unless (eq (fdefinition name)
		    (profile-info-new-definition pinfo))
	  (warn "Function ~S has been redefined, so times may be inaccurate.~@
	         PROFILE it again to record calls to the new definition."
		name))
	(multiple-value-bind
	    (calls time consing profile)
	    (funcall (profile-info-read-time pinfo))
	  (if (zerop calls)
	      (push name no-call)
	      (push (make-time-info name calls
				    (compensate-time calls time profile)
				    consing)
		    info)))))
    
    (setq info (sort info #'>= :key #'time-info-time))

    (format *trace-output*
	    "~&  Seconds  |  Consed   |  Calls  |  Sec/Call  |  Name:~@
	       ------------------------------------------------------~%")

    (let ((total-time 0.0)
	  (total-consed 0)
	  (total-calls 0))
      (dolist (time info)
	(incf total-time (time-info-time time))
	(incf total-calls (time-info-calls time))
	(incf total-consed (time-info-consing time))
	(format *trace-output*
		"~10,3F | ~9:D | ~7:D | ~10,5F | ~S~%"
		(time-info-time time)
		(time-info-consing time)
		(time-info-calls time)
		(/ (time-info-time time) (float (time-info-calls time)))
		(time-info-name time)))
      (format *trace-output*
	      "------------------------------------------------------~@
	      ~10,3F | ~9:D | ~7:D |            | Total~%"
	      total-time total-consed total-calls)

      (format *trace-output*
	      "~%Estimated total profiling overhead: ~4,2F seconds~%"
	      (* *total-profile-overhead* (float total-calls))))

    (when no-call
      (format *trace-output*
	      "~%These functions were not called:~%~{~<~%~:; ~S~>~}~%"
	      (sort no-call #'string< :key #'symbol-name)))
    (values)))


(defmacro reset-time (&rest names)
  "Resets the time counter for the named functions.  Names defaults to the list
  of all currently profiled functions."
  `(%reset-time ,(if names `',names '*timed-functions*)))

(defun %reset-time (names)
  (dolist (name names)
    (funcall (profile-info-reset-time (profile-info-or-lose name))))
  (values))


;;;; Overhead computation.

;;; We average the timing overhead over this many iterations.
;;;
(defconstant timer-overhead-iterations 5000)


;;; COMPUTE-TIME-OVERHEAD-AUX  --  Internal
;;;
;;;    Dummy function we profile to find profiling overhead.
;;;
(proclaim '(notinline compute-time-overhead-aux))
(locally (declare (optimize (debug-info 2))) ; Make sure we have arglist info...
  (defun compute-time-overhead-aux (x)
    (declare (ignore x))))


;;; COMPUTE-TIME-OVERHEAD  --  Internal
;;;
;;;    Initialize the profiling overhead variables.
;;;
(defun compute-time-overhead ()
  (macrolet ((frob (var)
	       `(let ((start (quickly-get-time))
		      (fun (symbol-function 'compute-time-overhead-aux)))
		  (dotimes (i timer-overhead-iterations)
		    (funcall fun fun))
		  (setq ,var
			(/ (float (- (quickly-get-time) start))
			   (float quick-time-units-per-second)
			   (float timer-overhead-iterations))))))
    (frob *call-overhead*)
    
    (unwind-protect
	(progn
	  (profile compute-time-overhead-aux)
	  (frob *total-profile-overhead*)
	  (decf *total-profile-overhead* *call-overhead*)
	  (let ((pinfo (profile-info-or-lose 'compute-time-overhead-aux)))
	    (multiple-value-bind (calls time)
				 (funcall (profile-info-read-time pinfo))
	      (declare (ignore calls))
	      (setq *internal-profile-overhead*
		    (/ (float time)
		       (float quick-time-units-per-second)
		       (float timer-overhead-iterations))))))
      (unprofile compute-time-overhead-aux))))

#+cmu
(pushnew #'(lambda ()
	     (makunbound '*call-overhead*))
	 ext:*before-save-initializations*)
