;;; -*- Package: EXTENSIONS -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/final.lisp,v 1.1 1991/11/16 01:59:18 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; Finalization based on weak pointers.  Written by William Lott, but
;;; the idea really was Chris Hoover's.
;;;

(in-package "EXTENSIONS")

(export '(finalize cancel-finalization))

(defvar *objects-pending-finalization* nil)

(defun finalize (object function)
  "Arrage for FUNCTION to be called when there are no more references to
   OBJECT."
  (declare (type function function))
  (system:without-gcing
   (push (cons (make-weak-pointer object) function)
	 *objects-pending-finalization*))
  object)

(defun cancel-finalization (object)
  "Cancel any finalization registers for OBJECT."
  (when object
    ;; We check to make sure object isn't nil because if there are any
    ;; broken weak pointers, their value will show up as nil.  Therefore,
    ;; they would be deleted from the list, but not finalized.  Broken
    ;; weak pointers shouldn't be left in the list, but why take chances?
    (system:without-gcing
     (setf *objects-pending-finalization*
	   (delete object *objects-pending-finalization*
		   :key #'(lambda (pair)
			    (values (weak-pointer-value (car pair))))))))
  nil)

(defun finalize-corpses ()
  (setf *objects-pending-finalization*
	(delete-if #'(lambda (pair)
		       (multiple-value-bind
			   (object valid)
			   (weak-pointer-value (car pair))
			 (declare (ignore object))
			 (unless valid
			   (funcall (cdr pair))
			   t)))
		   *objects-pending-finalization*))
  nil)

(pushnew 'finalize-corpses *after-gc-hooks*)
