;;; -*- Package: conditions; Log: code.log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/error.lisp,v 1.15 1992/03/10 18:33:53 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; This is a condition system for CMU Common Lisp.
;;; It was originally taken from some prototyping code written by KMP@Symbolics
;;; and massaged for our uses.
;;;

(in-package "CONDITIONS")
(use-package "EXTENSIONS")

(in-package "LISP")
(export '(break error warn cerror
	  ;;
	  ;; The following are found in Macros.Lisp:
	  check-type assert etypecase ctypecase ecase ccase
	  ;;
	  ;; These are all the new things to export from "LISP" now that this
	  ;; proposal has been accepted.
	  *break-on-signals* *debugger-hook* signal handler-case handler-bind
	  ignore-errors define-condition make-condition with-simple-restart
	  restart-case restart-bind restart-name restart-name find-restart
	  compute-restarts invoke-restart invoke-restart-interactively abort
	  continue muffle-warning store-value use-value invoke-debugger restart
	  condition warning serious-condition simple-condition simple-warning
	  simple-error simple-condition-format-string
	  simple-condition-format-arguments storage-condition stack-overflow
	  storage-exhausted type-error type-error-datum
	  type-error-expected-type simple-type-error program-error
	  control-error stream-error stream-error-stream end-of-file file-error
	  file-error-pathname cell-error unbound-variable undefined-function
	  arithmetic-error arithmetic-error-operation arithmetic-error-operands
	  package-error package-error-package division-by-zero
	  floating-point-overflow floating-point-underflow))

(in-package "EXTENSIONS")
(export '(floating-point-inexact floating-point-invalid))

(in-package "CONDITIONS")

;;;; Keyword utilities.

(eval-when (eval compile load)

(defun parse-keyword-pairs (list keys)
  (do ((l list (cddr l))
       (k '() (list* (cadr l) (car l) k)))
      ((or (null l) (not (member (car l) keys)))
       (values (nreverse k) l))))

(defmacro with-keyword-pairs ((names expression &optional keywords-var)
			      &body forms)
  (let ((temp (member '&rest names)))
    (unless (= (length temp) 2)
      (error "&rest keyword is ~:[missing~;misplaced~]." temp))
    (let ((key-vars (ldiff names temp))
          (key-var (or keywords-var (gensym)))
          (rest-var (cadr temp)))
      (let ((keywords (mapcar #'(lambda (x)
				  (intern (string x) ext:*keyword-package*))
			      key-vars)))
        `(multiple-value-bind (,key-var ,rest-var)
             (parse-keyword-pairs ,expression ',keywords)
           (let ,(mapcar #'(lambda (var keyword)
			     `(,var (getf ,key-var ,keyword)))
			 key-vars keywords)
	     ,@forms))))))

) ;eval-when



;;;; Restarts.

(defvar *restart-clusters* '())

(defun compute-restarts ()
  "Return a list of all the currently active restarts ordered from most
   recently established to less recently established."
  (copy-list (apply #'append *restart-clusters*)))

(defun restart-print (restart stream depth)
  (declare (ignore depth))
  (if *print-escape*
      (format stream "#<~S.~X>"
	      (type-of restart) (system:%primitive lisp::make-fixnum restart))
      (restart-report restart stream)))

(defstruct (restart (:print-function restart-print))
  name
  function
  report-function
  interactive-function)

(setf (documentation 'restart-name 'function)
      "Returns the name of the given restart object.")

(defun restart-report (restart stream)
  (funcall (or (restart-report-function restart)
               (let ((name (restart-name restart)))
		 #'(lambda (stream)
		     (if name (format stream "~S" name)
			      (format stream "~S" restart)))))
           stream))

(defmacro restart-bind (bindings &body forms)
  "Executes forms in a dynamic context where the given restart bindings are
   in effect.  Users probably want to use RESTART-CASE.  When clauses contain
   the same restart name, FIND-RESTART will find the first such clause."
  `(let ((*restart-clusters*
	  (cons (list
		 ,@(mapcar #'(lambda (binding)
			       (unless (or (car binding)
					   (member :report-function
						   binding :test #'eq))
				 (warn "Unnamed restart does not have a ~
					report function -- ~S"
				       binding))
			       `(make-restart
				 :name ',(car binding)
				 :function ,(cadr binding)
				 ,@(cddr binding)))
			       bindings))
		*restart-clusters*)))
     ,@forms))

(defun find-restart (name)
  "Returns the first restart named name.  If name is a restart, it is returned
   if it is currently active.  If no such restart is found, nil is returned.
   It is an error to supply nil as a name."
  (dolist (restart-cluster *restart-clusters*)
    (dolist (restart restart-cluster)
      (when (or (eq restart name) (eq (restart-name restart) name))
	(return-from find-restart restart)))))
  

(defun invoke-restart (restart &rest values)
  "Calls the function associated with the given restart, passing any given
   arguments.  If the argument restart is not a restart or a currently active
   non-nil restart name, then a control-error is signalled."
  (let ((real-restart (find-restart restart)))
    (unless real-restart
      (error 'control-error
	     :format-string "Restart ~S is not active."
	     :format-arguments (list restart)))
    (apply (restart-function real-restart) values)))

(defun invoke-restart-interactively (restart)
  "Calls the function associated with the given restart, prompting for any
   necessary arguments.  If the argument restart is not a restart or a
   currently active non-nil restart name, then a control-error is signalled."
  (let ((real-restart (find-restart restart)))
    (unless real-restart
      (error 'control-error
	     :format-string "Restart ~S is not active."
	     :format-arguments (list restart)))
    (apply (restart-function real-restart)
	   (let ((interactive-function
		  (restart-interactive-function real-restart)))
	     (if interactive-function
		 (funcall interactive-function)
		 '())))))


(defmacro restart-case (expression &body clauses)
  "(RESTART-CASE form
   {(case-name arg-list {keyword value}* body)}*)
   The form is evaluated in a dynamic context where the clauses have special
   meanings as points to which control may be transferred (see INVOKE-RESTART).
   When clauses contain the same case-name, FIND-RESTART will find the first
   such clause."
  (flet ((transform-keywords (&key report interactive)
	   (let ((result '()))
	     (when report
	       (setq result (list* (if (stringp report)
				       `#'(lambda (stream)
					    (write-string ,report stream))
				       `#',report)
				   :report-function
				   result)))
	     (when interactive
	       (setq result (list* `#',interactive
				   :interactive-function
				   result)))
	     (nreverse result))))
    (let ((temp-var (gensym))
	  (outer-tag (gensym))
	  (inner-tag (gensym))
	  (tag-var (gensym))
	  (data
	    (mapcar #'(lambda (clause)
			(with-keyword-pairs ((report interactive &rest forms)
					     (cddr clause))
			  (list (car clause)			   ;name=0
				(gensym)			   ;tag=1
				(transform-keywords :report report ;keywords=2
						    :interactive interactive)
				(cadr clause)			   ;bvl=3
				forms)))			   ;body=4
		    clauses)))
      `(let ((,outer-tag (cons nil nil))
	     (,inner-tag (cons nil nil))
	     ,temp-var ,tag-var)
	 (catch ,outer-tag
	   (catch ,inner-tag
	     (throw ,outer-tag
		    (restart-bind
			,(mapcar #'(lambda (datum)
				     (let ((name (nth 0 datum))
					   (tag  (nth 1 datum))
					   (keys (nth 2 datum)))
				       `(,name #'(lambda (&rest temp)
						   (setf ,temp-var temp)
						   (setf ,tag-var ',tag)
						   (throw ,inner-tag nil))
					       ,@keys)))
				 data)
		      ,expression)))
	   (case ,tag-var
	     ,@(mapcar #'(lambda (datum)
			   (let ((tag  (nth 1 datum))
				 (bvl  (nth 3 datum))
				 (body (nth 4 datum)))
			     `(,tag
			       (apply #'(lambda ,bvl ,@body) ,temp-var))))
		       data)))))))
#|
This macro doesn't work in our system due to lossage in closing over tags.
The previous version is uglier, but it sets up unique run-time tags.

(defmacro restart-case (expression &body clauses)
  "(RESTART-CASE form
   {(case-name arg-list {keyword value}* body)}*)
   The form is evaluated in a dynamic context where the clauses have special
   meanings as points to which control may be transferred (see INVOKE-RESTART).
   When clauses contain the same case-name, FIND-RESTART will find the first
   such clause."
  (flet ((transform-keywords (&key report interactive)
	   (let ((result '()))
	     (when report
	       (setq result (list* (if (stringp report)
				       `#'(lambda (stream)
					    (write-string ,report stream))
				       `#',report)
				   :report-function
				   result)))
	     (when interactive
	       (setq result (list* `#',interactive
				   :interactive-function
				   result)))
	     (nreverse result))))
    (let ((block-tag (gensym))
	  (temp-var  (gensym))
	  (data
	    (mapcar #'(lambda (clause)
			(with-keyword-pairs ((report interactive &rest forms)
					     (cddr clause))
			  (list (car clause)			   ;name=0
				(gensym)			   ;tag=1
				(transform-keywords :report report ;keywords=2
						    :interactive interactive)
				(cadr clause)			   ;bvl=3
				forms)))			   ;body=4
		    clauses)))
      `(block ,block-tag
	 (let ((,temp-var nil))
	   (tagbody
	     (restart-bind
	       ,(mapcar #'(lambda (datum)
			    (let ((name (nth 0 datum))
				  (tag  (nth 1 datum))
				  (keys (nth 2 datum)))
			      `(,name #'(lambda (&rest temp)
					  (setq ,temp-var temp)
					  (go ,tag))
				,@keys)))
			data)
	       (return-from ,block-tag ,expression))
	     ,@(mapcan #'(lambda (datum)
			   (let ((tag  (nth 1 datum))
				 (bvl  (nth 3 datum))
				 (body (nth 4 datum)))
			     (list tag
				   `(return-from ,block-tag
				      (apply #'(lambda ,bvl ,@body)
					     ,temp-var)))))
		       data)))))))
|#

(defmacro with-simple-restart ((restart-name format-string
					     &rest format-arguments)
			       &body forms)
  "(WITH-SIMPLE-RESTART (restart-name format-string format-arguments)
   body)
   If restart-name is not invoked, then all values returned by forms are
   returned.  If control is transferred to this restart, it immediately
   returns the values nil and t."
  `(restart-case (progn ,@forms)
     (,restart-name ()
        :report (lambda (stream)
		  (format stream ,format-string ,@format-arguments))
      (values nil t))))



;;;; Conditions.

(defun condition-print (condition stream depth)
  (declare (ignore depth))
  (if *print-escape*
      (print-unreadable-object (condition stream :identity t)
	(prin1 (type-of condition) stream))
      (handler-case
	  (condition-report condition stream)
	(error () (format stream "...~2%; Error reporting condition: ~S.~%"
			  condition)))))

(eval-when (eval compile load)

(defmacro parent-type     (condition-type) `(get ,condition-type 'parent-type))
(defmacro slots           (condition-type) `(get ,condition-type 'slots))
(defmacro conc-name       (condition-type) `(get ,condition-type 'conc-name))
(defmacro report-function (condition-type)
  `(get ,condition-type 'report-function))
(defmacro make-function   (condition-type) `(get ,condition-type 'make-function))

) ;eval-when

(defun condition-report (condition stream)
  (do ((type (type-of condition) (parent-type type)))
      ((not type)
       (format stream "The condition ~A occurred." (type-of condition)))
    (let ((reporter (report-function type)))
      (when reporter
        (funcall reporter condition stream)
        (return nil)))))

(setf (make-function   'condition) '|constructor for condition|)

(defun make-condition (type &rest slot-initializations)
  "Makes a condition of type type using slot-initializations as initial values
   for the slots."
  (let ((fn (make-function type)))
    (cond ((not fn) (error 'simple-type-error
			   :datum type
			   :expected-type '(satisfies make-function)
			   :format-string "Not a condition type: ~S"
			   :format-arguments (list type)))
          (t (apply fn slot-initializations)))))


;;; Some utilities used at macro expansion time.
;;;
(eval-when (eval compile load)

(defmacro resolve-function (function expression resolver)
  `(cond ((and ,function ,expression)
          (cerror "Use only the :~A information."
                  "Only one of :~A and :~A is allowed."
                  ',function ',expression))
         (,expression (setq ,function ,resolver))))
         
(defun parse-new-and-used-slots (slots parent-type)
  (let ((new '()) (used '()))
    (dolist (slot slots)
      (if (slot-used-p (car slot) parent-type)
          (push slot used)
          (push slot new)))
    (values new used)))

(defun slot-used-p (slot-name type)
  (cond ((eq type 'condition) nil)
        ((not type) (error "The type ~S does not inherit from condition." type))
        ((assoc slot-name (slots type)))
        (t (slot-used-p slot-name (parent-type type)))))

) ;eval-when

(defmacro define-condition (name (parent-type) &optional slot-specs
				 &rest options)
  "(DEFINE-CONDITION name (parent-type)
   ( {slot-name | (slot-name) | (slot-name default-value)}*)
   options)"
  (let ((constructor (let ((*package* (find-package "CONDITIONS")))
		       ;; Bind for the INTERN and the FORMAT.
		       (intern (format nil "Constructor for ~S" name)))))
    (let ((slots (mapcar #'(lambda (slot-spec)
			     (if (atom slot-spec) (list slot-spec) slot-spec))
			 slot-specs)))
      (multiple-value-bind (new-slots used-slots)
          (parse-new-and-used-slots slots parent-type)
	(let ((conc-name-p     nil)
	      (conc-name       nil)
	      (report-function nil)
	      (documentation   nil))
	  (do ((o options (cdr o)))
	      ((null o))
	    (let ((option (car o)))
	      (case (car option) ;should be ecase
		(:conc-name
		 (setq conc-name-p t)
		 (setq conc-name (cadr option)))
		(:report
		 (setq report-function
		       (if (stringp (cadr option))
			   `(lambda (stream)
			      (write-string ,(cadr option) stream))
			   (cadr option))))
		(:documentation (setq documentation (cadr option)))
		(otherwise
		 (cerror "Ignore this DEFINE-CONDITION option."
			 "Invalid DEFINE-CONDITION option: ~S" option)))))
	  (unless conc-name-p
	    (setq conc-name
		  (intern (concatenate 'simple-string (symbol-name name)
				       "-")
			  *package*)))
	  ;; The following three forms are compile-time side-effects.  For now,
	  ;; they affect the global environment, but with modified abstractions
	  ;; for parent-type, slots, and conc-name, the compiler could easily
	  ;; make them local.
	  (setf (parent-type name) parent-type)
          (setf (slots name)       slots)
          (setf (conc-name name)   conc-name)
          ;; finally, the expansion ...
	  `(progn
	     (defstruct (,name
			 (:constructor ,constructor)
			 (:predicate nil)
			 (:copier nil)
			 (:print-function condition-print)
			 (:include ,parent-type ,@used-slots)
			 (:conc-name ,conc-name))
	       ,@new-slots)
	     (setf (documentation ',name 'type) ',documentation)
	     (setf (parent-type ',name) ',parent-type)
	     (setf (slots ',name) ',slots)
	     (setf (conc-name ',name) ',conc-name)
	     (setf (report-function ',name)
		   ,(if report-function `#',report-function))
	     (setf (make-function ',name) ',constructor)
	     ',name))))))



;;;; HANDLER-BIND and SIGNAL.

(defvar *handler-clusters* nil)

(defmacro handler-bind (bindings &body forms)
  "(HANDLER-BIND ( {(type handler)}* )  body)
   Executes body in a dynamic context where the given handler bindings are
   in effect.  Each handler must take the condition being signalled as an
   argument.  The bindings are searched first to last in the event of a
   signalled condition."
  (unless (every #'(lambda (x) (and (listp x) (= (length x) 2))) bindings)
    (error "Ill-formed handler bindings."))
  `(let ((*handler-clusters*
	  (cons (list ,@(mapcar #'(lambda (x) `(cons ',(car x) ,(cadr x)))
				bindings))
		*handler-clusters*)))
     ,@forms))

(defvar *break-on-signals* nil
  "When (typep condition *break-on-signals*) is true, then calls to SIGNAL will
   enter the debugger prior to signalling that condition.")

(defun signal (datum &rest arguments)
  "Invokes the signal facility on a condition formed from datum and arguments.
   If the condition is not handled, nil is returned.  If
   (TYPEP condition *BREAK-ON-SIGNALS*) is true, the debugger is invoked before
   any signalling is done."
  (let ((condition (coerce-to-condition datum arguments
					'simple-condition 'signal))
        (*handler-clusters* *handler-clusters*))
    (when (typep condition *break-on-signals*)
      (break "~A~%Break entered because of *break-on-signals*."
	     condition))
    (loop
      (unless *handler-clusters* (return))
      (let ((cluster (pop *handler-clusters*)))
	(dolist (handler cluster)
	  (when (typep condition (car handler))
	    (funcall (cdr handler) condition)))))
    nil))

;;; COERCE-TO-CONDITION is used in SIGNAL, ERROR, CERROR, WARN, and
;;; INVOKE-DEBUGGER for parsing the hairy argument conventions into a single
;;; argument that's directly usable by all the other routines.
;;;
(defun coerce-to-condition (datum arguments default-type function-name)
  (cond ((typep datum 'condition)
	 (if arguments
	     (cerror "Ignore the additional arguments."
		     'simple-type-error
		     :datum arguments
		     :expected-type 'null
		     :format-string "You may not supply additional arguments ~
				     when giving ~S to ~S."
		     :format-arguments (list datum function-name)))
	 datum)
        ((symbolp datum) ;Roughly, (subtypep datum 'condition).
         (apply #'make-condition datum arguments))
        ((or (stringp datum) (functionp datum))
	 (make-condition default-type
                         :format-string datum
                         :format-arguments arguments))
        (t
         (error 'simple-type-error
		:datum datum
		:expected-type '(or symbol string)
		:format-string "Bad argument to ~S: ~S"
		:format-arguments (list function-name datum)))))



;;;; ERROR, CERROR, BREAK, WARN.

(define-condition serious-condition (condition) ())

(define-condition error (serious-condition)
  ((function-name nil)))

(defun error (datum &rest arguments)
  "Invokes the signal facility on a condition formed from datum and arguments.
   If the condition is not handled, the debugger is invoked."
  (kernel:infinite-error-protect
    (let ((condition (coerce-to-condition datum arguments
					  'simple-error 'error))
	  (debug:*stack-top-hint* debug:*stack-top-hint*))
      (unless (and (error-function-name condition) debug:*stack-top-hint*)
	(multiple-value-bind
	    (name frame)
	    (kernel:find-caller-name)
	  (unless (error-function-name condition)
	    (setf (error-function-name condition) name))
	  (unless debug:*stack-top-hint*
	    (setf debug:*stack-top-hint* frame))))
      (let ((debug:*stack-top-hint* nil))
	(signal condition))
      (invoke-debugger condition))))

;;; CERROR must take care to not use arguments when datum is already a
;;; condition object.
;;;
(defun cerror (continue-string datum &rest arguments)
  (kernel:infinite-error-protect
    (with-simple-restart
	(continue "~A" (apply #'format nil continue-string arguments))
      (let ((condition (if (typep datum 'condition)
			   datum
			   (coerce-to-condition datum arguments
						'simple-error 'error)))
	    (debug:*stack-top-hint* debug:*stack-top-hint*))
	(unless (and (error-function-name condition) debug:*stack-top-hint*)
	  (multiple-value-bind
	      (name frame)
	      (kernel:find-caller-name)
	    (unless (error-function-name condition)
	      (setf (error-function-name condition) name))
	    (unless debug:*stack-top-hint*
	      (setf debug:*stack-top-hint* frame))))
	(let ((debug:*stack-top-hint* nil))
	  (signal condition))
	(invoke-debugger condition))))
  nil)

(defun break (&optional (format-string "Break") &rest format-arguments)
  "Prints a message and invokes the debugger without allowing any possibility
   of condition handling occurring."
  (kernel:infinite-error-protect
    (with-simple-restart (continue "Return from BREAK.")
      (let ((debug:*stack-top-hint*
	     (or debug:*stack-top-hint*
		 (nth-value 1 (kernel:find-caller-name)))))
	(invoke-debugger
	 (make-condition 'simple-condition
			 :format-string format-string
			 :format-arguments format-arguments)))))
  nil)

(define-condition warning (condition) ())

(defvar *break-on-warnings* ()
  "If non-NIL, then WARN will enter a break loop before returning.")

(defun warn (datum &rest arguments)
  "Warns about a situation by signalling a condition formed by datum and
   arguments.  Before signalling, if *break-on-warnings* is set, then BREAK
   is called.  While the condition is being signaled, a muffle-warning restart
   exists that causes WARN to immediately return nil."
  (kernel:infinite-error-protect
    (let ((condition (coerce-to-condition datum arguments
					  'simple-warning 'warn)))
      (check-type condition warning "a warning condition")
      (if *break-on-warnings*
	  (break "~A~%Break entered because of *break-on-warnings*."
		 condition))
      (restart-case (signal condition)
	(muffle-warning ()
	  :report "Skip warning."
	  (return-from warn nil)))
      (format *error-output* "~&~@<Warning:  ~3i~:_~A~:>~%" condition)))
  nil)


;;;; Condition definitions.

;;; Serious-condition and error are defined on the previous page, so ERROR and
;;; CERROR can SETF a slot in the error condition object.
;;;


(defun simple-condition-printer (condition stream)
  (apply #'format stream (simple-condition-format-string condition)
	 		 (simple-condition-format-arguments condition)))

;;; The simple-condition type has a conc-name, so SIMPLE-CONDITION-FORMAT-STRING
;;; and SIMPLE-CONDITION-FORMAT-ARGUMENTS could be written to handle the
;;; simple-condition, simple-warning, simple-type-error, and simple-error types.
;;; This seems to create some kind of bogus multiple inheritance that the user
;;; sees.
;;;
(define-condition simple-condition (condition)
  (format-string
   (format-arguments '()))
  (:conc-name internal-simple-condition-)
  (:report simple-condition-printer))

;;; The simple-warning type has a conc-name, so SIMPLE-CONDITION-FORMAT-STRING
;;; and SIMPLE-CONDITION-FORMAT-ARGUMENTS could be written to handle the
;;; simple-condition, simple-warning, simple-type-error, and simple-error types.
;;; This seems to create some kind of bogus multiple inheritance that the user
;;; sees.
;;;
(define-condition simple-warning (warning)
  (format-string
   (format-arguments '()))
  (:conc-name internal-simple-warning-)
  (:report simple-condition-printer))


(defun print-simple-error (condition stream)
  (format stream "~&~@<Error in function ~S:  ~3i~:_~?~:>"
	  (internal-simple-error-function-name condition)
	  (internal-simple-error-format-string condition)
	  (internal-simple-error-format-arguments condition)))

;;; The simple-error type has a conc-name, so SIMPLE-CONDITION-FORMAT-STRING
;;; and SIMPLE-CONDITION-FORMAT-ARGUMENTS could be written to handle the
;;; simple-condition, simple-warning, simple-type-error, and simple-error types.
;;; This seems to create some kind of bogus multiple inheritance that the user
;;; sees.
;;;
(define-condition simple-error (error)
  (format-string
   (format-arguments '()))
  (:conc-name internal-simple-error-)
  (:report print-simple-error))


(define-condition storage-condition (serious-condition) ())

(define-condition stack-overflow    (storage-condition) ())
(define-condition storage-exhausted (storage-condition) ())

(define-condition type-error (error)
  (datum
   expected-type)
  (:report
   (lambda (condition stream)
     (format stream "~@<Type-error in ~S:  ~3i~:_~S is not of type ~S~:>"
	     (type-error-function-name condition)
	     (type-error-datum condition)
	     (type-error-expected-type condition)))))

;;; The simple-type-error type has a conc-name, so
;;; SIMPLE-CONDITION-FORMAT-STRING and SIMPLE-CONDITION-FORMAT-ARGUMENTS could
;;; be written to handle the simple-condition, simple-warning,
;;; simple-type-error, and simple-error types.  This seems to create some kind
;;; of bogus multiple inheritance that the user sees.
;;;
(define-condition simple-type-error (type-error)
  (format-string
   (format-arguments '()))
  (:conc-name internal-simple-type-error-)
  (:report simple-condition-printer))

(define-condition case-failure (type-error)
  (name
   possibilities)
  (:report
    (lambda (condition stream)
      (format stream "~@<~S fell through ~S expression.  ~:_Wanted one of ~:S.~:>"
	      (type-error-datum condition)
	      (case-failure-name condition)
	      (case-failure-possibilities condition)))))


;;; SIMPLE-CONDITION-FORMAT-STRING and SIMPLE-CONDITION-FORMAT-ARGUMENTS.
;;; These exist for the obvious types to seemingly give the impression of
;;; multiple inheritance.  That is, the last three types inherit from warning,
;;; type-error, and error while inheriting from simple-condition also.
;;;
(defun simple-condition-format-string (condition)
  (etypecase condition
    (simple-condition  (internal-simple-condition-format-string  condition))
    (simple-warning    (internal-simple-warning-format-string    condition))
    (simple-type-error (internal-simple-type-error-format-string condition))
    (simple-error      (internal-simple-error-format-string      condition))))
;;;
(defun simple-condition-format-arguments (condition)
  (etypecase condition
    (simple-condition  (internal-simple-condition-format-arguments  condition))
    (simple-warning    (internal-simple-warning-format-arguments    condition))
    (simple-type-error (internal-simple-type-error-format-arguments condition))
    (simple-error      (internal-simple-error-format-arguments      condition))))


(define-condition program-error (error) ())


(defun print-control-error (condition stream)
  (format stream "~&~@<Error in function ~S:  ~3i~:_~?~:>"
	  (control-error-function-name condition)
	  (control-error-format-string condition)
	  (control-error-format-arguments condition)))

(define-condition control-error (error)
  (format-string
   (format-arguments nil))
  (:report print-control-error))


(define-condition stream-error (error) (stream))

(define-condition end-of-file (stream-error) ())

(define-condition file-error (error) (pathname))

(define-condition package-error (error) (pathname))

(define-condition cell-error (error) (name))

(define-condition unbound-variable (cell-error) ()
  (:report
   (lambda (condition stream)
     (format stream
	     "Error in ~S:  the variable ~S is unbound."
	     (cell-error-function-name condition)
	     (cell-error-name condition)))))
  
(define-condition undefined-function (cell-error) ()
  (:report
   (lambda (condition stream)
     (format stream
	     "Error in ~S:  the function ~S is undefined."
	     (cell-error-function-name condition)
	     (cell-error-name condition)))))

(define-condition arithmetic-error (error) (operation operands)
  (:report (lambda (condition stream)
	     (format stream "Arithmetic error ~S signalled."
		     (type-of condition))
	     (when (arithmetic-error-operation condition)
	       (format stream "~%Operation was ~S, operands ~S."
		       (arithmetic-error-operation condition)
		       (arithmetic-error-operands condition))))))

(define-condition division-by-zero         (arithmetic-error) ())
(define-condition floating-point-overflow  (arithmetic-error) ())
(define-condition floating-point-underflow (arithmetic-error) ())
(define-condition floating-point-inexact   (arithmetic-error) ())
(define-condition floating-point-invalid   (arithmetic-error) ())


;;;; HANDLER-CASE and IGNORE-ERRORS.

(defmacro handler-case (form &rest cases)
  "(HANDLER-CASE form
   { (type ([var]) body) }* )
   Executes form in a context with handlers established for the condition
   types.  A peculiar property allows type to be :no-error.  If such a clause
   occurs, and form returns normally, all its values are passed to this clause
   as if by MULTIPLE-VALUE-CALL.  The :no-error clause accepts more than one
   var specification."
  (let ((no-error-clause (assoc ':no-error cases)))
    (if no-error-clause
	(let ((normal-return (make-symbol "normal-return"))
	      (error-return  (make-symbol "error-return")))
	  `(block ,error-return
	     (multiple-value-call #'(lambda ,@(cdr no-error-clause))
	       (block ,normal-return
		 (return-from ,error-return
		   (handler-case (return-from ,normal-return ,form)
		     ,@(remove no-error-clause cases)))))))
	(let ((var (gensym))
	      (outer-tag (gensym))
	      (inner-tag (gensym))
	      (tag-var (gensym))
	      (annotated-cases (mapcar #'(lambda (case) (cons (gensym) case))
				       cases)))
	  `(let ((,outer-tag (cons nil nil))
		 (,inner-tag (cons nil nil))
		 ,var ,tag-var)
	     ,var			;ignoreable
	     (catch ,outer-tag
	       (catch ,inner-tag
		 (throw ,outer-tag
			(handler-bind
			    ,(mapcar #'(lambda (annotated-case)
					 `(,(cadr annotated-case)
					   #'(lambda (temp)
					       ,(if (caddr annotated-case)
						    `(setq ,var temp)
						    '(declare (ignore temp)))
					       (setf ,tag-var
						     ',(car annotated-case))
					       (throw ,inner-tag nil))))
				     annotated-cases)
			  ,form)))
	       (case ,tag-var
		 ,@(mapcar #'(lambda (annotated-case)
			       (let ((body (cdddr annotated-case))
				     (varp (caddr annotated-case)))
				 `(,(car annotated-case)
				   ,@(if varp
					 `((let ((,(car varp) ,var))
					     ,@body))
					 body))))
			   annotated-cases))))))))
#|
This macro doesn't work in our system due to lossage in closing over tags.
The previous version sets up unique run-time tags.

(defmacro handler-case (form &rest cases)
  "(HANDLER-CASE form
   { (type ([var]) body) }* )
   Executes form in a context with handlers established for the condition
   types.  A peculiar property allows type to be :no-error.  If such a clause
   occurs, and form returns normally, all its values are passed to this clause
   as if by MULTIPLE-VALUE-CALL.  The :no-error clause accepts more than one
   var specification."
  (let ((no-error-clause (assoc ':no-error cases)))
    (if no-error-clause
	(let ((normal-return (make-symbol "normal-return"))
	      (error-return  (make-symbol "error-return")))
	  `(block ,error-return
	     (multiple-value-call #'(lambda ,@(cdr no-error-clause))
	       (block ,normal-return
		 (return-from ,error-return
		   (handler-case (return-from ,normal-return ,form)
		     ,@(remove no-error-clause cases)))))))
	(let ((tag (gensym))
	      (var (gensym))
	      (annotated-cases (mapcar #'(lambda (case) (cons (gensym) case))
				       cases)))
	  `(block ,tag
	     (let ((,var nil))
	       ,var				;ignorable
	       (tagbody
		 (handler-bind
		  ,(mapcar #'(lambda (annotated-case)
			       (list (cadr annotated-case)
				     `#'(lambda (temp)
					  ,(if (caddr annotated-case)
					       `(setq ,var temp)
					       '(declare (ignore temp)))
					  (go ,(car annotated-case)))))
			   annotated-cases)
			       (return-from ,tag ,form))
		 ,@(mapcan
		    #'(lambda (annotated-case)
			(list (car annotated-case)
			      (let ((body (cdddr annotated-case)))
				`(return-from
				  ,tag
				  ,(cond ((caddr annotated-case)
					  `(let ((,(caaddr annotated-case)
						  ,var))
					     ,@body))
					 ((not (cdr body))
					  (car body))
					 (t
					  `(progn ,@body)))))))
			   annotated-cases))))))))
|#

(defmacro ignore-errors (&rest forms)
  "Executes forms after establishing a handler for all error conditions that
   returns from this form nil and the condition signalled."
  `(handler-case (progn ,@forms)
     (error (condition) (values nil condition))))



;;;; Restart definitions.

(define-condition abort-failure (control-error) ()
  (:report
   "Found an \"abort\" restart that failed to transfer control dynamically."))

;;; ABORT signals an error in case there was a restart named abort that did
;;; not tranfer control dynamically.  This could happen with RESTART-BIND.
;;;
(defun abort ()
  "Transfers control to a restart named abort, signalling a control-error if
   none exists."
  (invoke-restart 'abort)
  (error 'abort-failure))


(defun muffle-warning ()
  "Transfers control to a restart named muffle-warning, signalling a
   control-error if none exists."
  (invoke-restart 'muffle-warning))


;;; DEFINE-NIL-RETURNING-RESTART finds the restart before invoking it to keep
;;; INVOKE-RESTART from signalling a control-error condition.
;;;
(defmacro define-nil-returning-restart (name args doc)
  `(defun ,name ,args
     ,doc
     (if (find-restart ',name) (invoke-restart ',name ,@args))))

(define-nil-returning-restart continue ()
  "Transfer control to a restart named continue, returning nil if none exists.")

(define-nil-returning-restart store-value (value)
  "Transfer control and value to a restart named store-value, returning nil if
   none exists.")

(define-nil-returning-restart use-value (value)
  "Transfer control and value to a restart named use-value, returning nil if
   none exists.")
