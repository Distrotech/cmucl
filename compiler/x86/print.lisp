;;; -*- Mode: LISP; Syntax: Common-Lisp; Base: 10; Package: x86 -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
 "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/x86/print.lisp,v 1.1.2.1 1998/06/23 11:24:11 pw Exp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains the print VOP, which is used while booting the kernel
;;; core to keep the user entertained.
;;;
;;; Written by William Lott.
;;; Enhancements/debugging by Douglas T. Crosher 1996.
;;;
(in-package :x86)

(define-vop (print)
  (:args (object :scs (descriptor-reg any-reg)))
  (:temporary (:sc unsigned-reg :offset eax-offset :target result
		   :from :eval :to (:result 0))
	      eax)
  (:results (result :scs (descriptor-reg)))
  (:save-p t)
  (:generator 100
    (inst push object)
    (inst lea eax (make-fixup (extern-alien-name "debug_print") :foreign))
    (inst call (make-fixup (extern-alien-name "call_into_c") :foreign))
    (inst add esp-tn word-bytes)
    (move result eax)))
