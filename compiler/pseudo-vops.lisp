;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/pseudo-vops.lisp,v 1.6 1992/06/04 15:52:51 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;;    This file contains definitions of VOPs used as internal markers by the
;;; compiler.  Since they don't emit any code, they should be portable. 
;;;
;;; Written by Rob MacLachlan
;;;
(in-package 'c)


;;; Notes the place at which the environment is properly initialized, for
;;; debug-info purposes.
;;;
(define-vop (note-environment-start)
  (:info start-lab)
  (:vop-var vop)
  (:generator 0
    (emit-label start-lab)
    (note-debug-location vop start-lab :non-local-entry)))


;;; Call a move function.  Used for register save/restore and spilling.
;;;
(define-vop (move-operand)
  (:args (x))
  (:results (y))
  (:info name)
  (:vop-var vop)
  (:generator 0
    (funcall (symbol-function name) vop x y)))

