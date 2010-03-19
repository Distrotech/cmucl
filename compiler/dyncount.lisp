;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/dyncount.lisp,v 1.11 2010/03/19 15:19:00 rtoy Rel $")
;;;
;;; **********************************************************************
;;;
;;; This file contains support for collecting dynamic vop statistics.
;;; 
(in-package "C")
(intl:textdomain "cmucl")

(export '(*collect-dynamic-statistics*
	  dyncount-info-counts dyncount-info-costs dyncount-info
	  dyncount-info-p count-me))

(defvar *collect-dynamic-statistics* nil
  "When T, emit extra code to collect dynamic statistics about vop usages.")

(defvar *dynamic-counts-tn* nil
  "Holds the TN for the counts vector.")


(defstruct (dyncount-info
	    (:print-function %print-dyncount-info)
	    (:make-load-form-fun :just-dump-it-normally))
  for
  (costs (required-argument) :type (simple-array (unsigned-byte 32) (*)))
  (counts (required-argument) :type (simple-array (unsigned-byte 32) (*))))

(defprinter dyncount-info
  for
  costs
  counts)
