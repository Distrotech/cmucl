;;; -*- Package: HEMLOCK -*-
;;;
;;; **********************************************************************
;;; Copyright (c) 1993 Carnegie Mellon University, all rights reserved.
;;; 
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/hemlock/dylan.lisp,v 1.2 1994/08/21 15:17:15 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains a minimal dylan mode.
;;;
(in-package "HEMLOCK")

;;; hack ..

(setf (getstring "dylan" *mode-names*) nil)


(defmode "Dylan" :major-p t)
(defcommand "Dylan Mode" (p)
  "Put the current buffer into \"Dylan\" mode."
  "Put the current buffer into \"Dylan\" mode."
  (declare (ignore p))
  (setf (buffer-major-mode (current-buffer)) "Dylan"))

(define-file-type-hook ("dylan") (buffer type)
  (declare (ignore type))
  (setf (buffer-major-mode buffer) "Dylan"))

(defhvar "Indent Function"
  "Indentation function which is invoked by \"Indent\" command.
   It must take one argument that is the prefix argument."
  :value #'generic-indent
  :mode "Dylan")

(defhvar "Auto Fill Space Indent"
  "When non-nil, uses \"Indent New Comment Line\" to break lines instead of
   \"New Line\"."
  :mode "Dylan" :value t)

(defhvar "Comment Start"
  "String that indicates the start of a comment."
  :mode "Dylan" :value "//")

(defhvar "Comment End"
  "String that ends comments.  Nil indicates #\newline termination."
  :mode "Dylan" :value nil)

(defhvar "Comment Begin"
  "String that is inserted to begin a comment."
  :mode "Dylan" :value "// ")

(bind-key "Delete Previous Character Expanding Tabs" #k"backspace"
	  :mode "Dylan")
(bind-key "Delete Previous Character Expanding Tabs" #k"delete" :mode "Dylan")

;;; hacks...

(shadow-attribute :scribe-syntax #\< nil "Dylan")
(shadow-attribute :scribe-syntax #\> nil "Dylan")
(bind-key "Self Insert" #k"\>" :mode "Dylan")
(bind-key "Scribe Insert Bracket" #k")" :mode "Dylan")
(bind-key "Scribe Insert Bracket" #k"]" :mode "Dylan")
(bind-key "Scribe Insert Bracket" #k"}" :mode "Dylan")
