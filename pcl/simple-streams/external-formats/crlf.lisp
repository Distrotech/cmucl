;;; -*- Mode: LISP; Syntax: ANSI-Common-Lisp; Package: STREAM -*-
;;;
;;; **********************************************************************
;;; This code was written by Paul Foley and has been placed in the public
;;; domain.
;;;
(ext:file-comment "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/pcl/simple-streams/external-formats/crlf.lisp,v 1.4 2010/07/12 13:58:42 rtoy Exp $")

(in-package "STREAM")

;; Convert DOS cr/lf end-of-line sequence to/from #\newline
(define-composing-external-format :crlf (:max 2 :documentation
"CRLF is a composing external format that converts CR/LF (carriage
return/linefeed) to a Lisp newline character.  This is the Windoes
end-of-line character sequence.")
  (input (state input unput tmp1 tmp2 tmp3 tmp4)
    `(multiple-value-bind (,tmp1 ,tmp2) 
	 ,input
       (when (= ,tmp1 (char-code #\return))
	 (multiple-value-bind (,tmp3 ,tmp4)
	     ,input
	   ;; @@ tmp3 may be NIL, if file ends in LF
	   (if (= ,tmp3 (char-code #\newline))
	       (setq ,tmp1 ,tmp3
		     ,tmp2 (+ ,tmp2 ,tmp4))
	       (,unput ,tmp4))))
       (values ,tmp1 ,tmp2)))
  (output (code state output)
    `(progn
       (when (= ,code (char-code #\newline))
	 (,output (char-code #\return)))
       (,output ,code))))
