;;; -*- Package: HPPA -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/assembly/hppa/alloc.lisp,v 1.1 1992/06/12 04:00:00 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; Stuff to handle allocation of stuff we don't want to do inline.
;;;
;;; Written by William Lott.
;;;

(in-package "HPPA")

;;; Given that the pseudo-atomic sequence is so short, there is
;;; nothing that qualifies.  But we want to keep the file around
;;; in case we decide to add something later.

