;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/loadcom.lisp,v 1.36 1992/02/24 05:51:52 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;; Load up the compiler.
;;;
(in-package "C")

(load "c:backend")
(load "c:macros")
(load "c:sset")
(load "c:node")
(load "c:alloc")
(load "c:ctype")
(load "c:knownfun")
(load "c:fndb")
(load "c:ir1util")
(load "c:ir1tran")
(load "c:ir1final")
(load "c:srctran")
(load "c:array-tran")
(load "c:seqtran")
(load "c:typetran")
(load "c:float-tran")
(load "c:saptran")
(load "c:locall")
(load "c:dfo")
(load "c:ir1opt")
;(load "c:loop")
(load "c:checkgen")
(load "c:constraint")
(load "c:envanal")
(load "c:vop")
(load "c:tn")
(load "c:bit-util")
(load "c:life")
(load "c:vmdef")
(load "c:gtn")
(load "c:ltn")
(load "c:stack")
(load "c:control")
(load "c:entry")
(load "c:ir2tran")
(load "c:pack")
(load "c:dyncount")
(load "c:statcount")
(load "c:codegen")
(load "c:main")
(load "c:disassem")
(load "c:assembler")
(load "c:assem-opt")
(load "assem:assemfile")
(load "c:aliencomp")
(load "c:ltv")
(load "c:debug-dump")

(load "c:dump")
(load "c:debug")
(load "c:assem-check")
(load "c:copyprop")
(load "c:represent")

(load "c:eval-comp")
(load "c:eval")
