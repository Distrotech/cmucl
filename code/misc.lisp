;;; -*- Mode: Lisp; Package: Lisp; Log: code.log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/misc.lisp,v 1.8 1991/02/08 13:34:17 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/misc.lisp,v 1.8 1991/02/08 13:34:17 ram Exp $
;;;
;;; Assorted miscellaneous functions for Spice Lisp.
;;;
;;; Written and maintained mostly by Skef Wholey and Rob MacLachlan.
;;; Scott Fahlman, Dan Aronson, and Steve Handerson did stuff here, too.
;;;
(in-package "LISP")
(export '(documentation *features* common variable room
	  lisp-implementation-type lisp-implementation-version machine-type
	  machine-version machine-instance software-type software-version
	  short-site-name long-site-name dribble))


(defun documentation (name doc-type)
  "Returns the documentation string of Doc-Type for Name, or NIL if
  none exists.  System doc-types are VARIABLE, FUNCTION, STRUCTURE, TYPE,
  and SETF."
  (case doc-type
    (variable (info variable documentation name))
    (function (info function documentation name))
    (structure
     (when (eq (info type kind name) :structure)
       (info type documentation name)))
    (type
     (info type documentation name))
    (setf (info setf documentation name))
    (t
     (cdr (assoc doc-type (info random-documentation stuff name))))))

(defun %set-documentation (name doc-type string)
  (case doc-type
    (variable (setf (info variable documentation name) string))
    (function (setf (info function documentation name) string))
    (structure
     (unless (eq (info type kind name) :structure)
       (error "~S is not the name of a structure type." name))
     (setf (info type documentation name) string))
    (type (setf (info type documentation name) string))
    (setf (setf (info setf documentation name) string))
    (t
     (let ((pair (assoc doc-type (info random-documentation stuff name))))
       (if pair
	   (setf (cdr pair) string)
	   (push (cons doc-type string)
		 (info random-documentation stuff name))))))
  string)

(defvar *features* '(:common :cmu :mach :new-compiler)
  "Holds a list of symbols that describe features provided by the
   implementation.")

(defun featurep (x)
  "If X is an atom, see if it is present in *FEATURES*.  Also
  handle arbitrary combinations of atoms using NOT, AND, OR."
  (cond ((atom x) (memq x *features*))
	((eq (car x) ':not) (not (featurep (cadr x))))
	((eq (car x) ':and)
	 (every #'featurep (cdr x)))
	((eq (car x) ':or)
	 (some #'featurep (cdr x)))
	(t nil)))



;;; Other Environment Inquiries.

(defun lisp-implementation-type ()
  "Returns a string describing the implementation type."
  "CMU Common Lisp")

(defun lisp-implementation-version ()
  "Returns a string describing the implementation version."
  *lisp-implementation-version*)

(defun machine-instance ()
  "Returns a string giving the name of the local machine."
  (mach::unix-gethostname))

(defun software-type ()
  "Returns a string describing the supporting software."
  "MACH/4.3BSD")

(defun software-version ()
  "Returns a string describing version of the supporting software."
  (string-trim
   '(#\newline)
   (with-output-to-string (stream)
     (run-program "/usr/cs/etc/version" nil :output stream))))

(defun short-site-name ()
  "Returns a string with the abbreviated site name."
  "CMU-SCS")

(defun long-site-name ()
  "Returns a string with the long form of the site name."
  "Carnegie-Mellon University School of Computer Science")



;;;; Dribble stuff:

;;; Each time we start dribbling to a new stream, we put it in
;;; *dribble-stream*, and push a list of *dribble-stream*,
;;; *standard-input*, and *standard-output* in *previous-streams*.
;;; *standard-output* is changed to a broadcast stream that broadcasts
;;; to *dribble-stream* and to the old value of *standard-output*.
;;; *standard-input* is changed to an echo stream that echos input from
;;; the old value of standard input to *dribble-stream*.
;;;
;;; When dribble is called with no arguments, *dribble-stream* is closed,
;;; and the values of *dribble-stream*, *standard-input*, and
;;; *standard-output* are poped from *previous-streams*.

(defvar *previous-streams* nil)
(defvar *dribble-stream* nil)

(defun dribble (&optional pathname &key (if-exists :append))
  "With a file name as an argument, dribble opens the file and
   sends a record of further I/O to that file.  Without an
   argument, it closes the dribble file, and quits logging."
  (cond (pathname
	 (let* ((new-dribble-stream
		 (open pathname :direction :output :if-exists if-exists
		       :if-does-not-exist :create))
		(new-standard-output
		 (make-broadcast-stream *standard-output* new-dribble-stream))
		(new-standard-input
		 (make-echo-stream *standard-input* new-dribble-stream)))
	   (push (list *dribble-stream* *standard-input* *standard-output*)
		 *previous-streams*)
	   (setf *dribble-stream* new-dribble-stream)
	   (setf *standard-input* new-standard-input)
	   (setf *standard-output* new-standard-output)))
	((null *dribble-stream*)
	 (error "Not currently dribbling."))
	(t
	 (let ((old-streams (pop *previous-streams*)))
	   (close *dribble-stream*)
	   (setf *dribble-stream* (first old-streams))
	   (setf *standard-input* (second old-streams))
	   (setf *standard-output* (third old-streams)))))
  (values))
