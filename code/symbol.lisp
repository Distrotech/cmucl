;;; -*- Log: code.log; Package: Lisp -*-
;;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;; Symbol manipulating functions for Spice Lisp.
;;;
;;; Written by Scott Fahlman.
;;; Hacked on and maintained by Skef Wholey.
;;;
;;; Many of these are trivial interpreter entries to functions
;;; open-coded by the compiler.
;;;
(in-package 'lisp)
(export '(get remprop symbol-plist getf get-properties symbol-name
	  make-symbol copy-symbol gensym gentemp *gensym-counter*
	  symbol-package keywordp makunbound symbol-value symbol-function
	  boundp set))

(defun set (variable new-value)
  "VARIABLE must evaluate to a symbol.  This symbol's special value cell is
  set to the specified new value."
  (set variable new-value))

(defun makunbound (variable)
  "VARIABLE must evaluate to a symbol.  This symbol is made unbound,
  removing any value it may currently have."
  (set variable
       (%primitive make-other-immediate-type
		   0
		   vm:unbound-marker-type))
  variable)

(defun symbol-value (variable)
  "VARIABLE must evaluate to a symbol.  This symbol's current special
  value is returned."
  (symbol-value variable))

(defun symbol-function (variable)
  "VARIABLE must evaluate to a symbol.  This symbol's current definition
  is returned."
  (symbol-function variable))

(defun %sp-set-definition (symbol new-value)
  (setf (symbol-function symbol) new-value))

(defun boundp (variable)
  "VARIABLE must evaluate to a symbol.  Return () if this symbol is
  unbound, T if it has a value."
  (boundp variable))

(defun symbol-plist (variable)
  "VARIABLE must evaluate to a symbol.  Return its property list."
  (symbol-plist variable))

(defun %sp-set-plist (symbol new-value)
  (setf (symbol-plist symbol) new-value))

(defun symbol-name (variable)
  "VARIABLE must evaluate to a symbol.  Return its print name."
  (symbol-name variable))

(defun symbol-package (variable)
  "VARIABLE must evaluate to a symbol.  Return its package."
  (symbol-package variable))

(defun make-symbol (string)
  "Make and return a new symbol with the STRING as its print name."
  (make-symbol string))

(defun get (symbol indicator &optional (default nil))
  "Look on the property list of SYMBOL for the specified INDICATOR.  If this
  is found, return the associated value, else return DEFAULT."
  (do ((pl (symbol-plist symbol) (cddr pl)))
      ((atom pl) default)
    (cond ((atom (cdr pl))
	   (error "~S has an odd number of items in its property list."
		   symbol))
	  ((eq (car pl) indicator)
	   (return (cadr pl))))))

(defun %put (symbol indicator value)
  "The VALUE is added as a property of SYMBOL under the specified INDICATOR.
  Returns VALUE."
  (do ((pl (symbol-plist symbol) (cddr pl)))
      ((endp pl)
       (setf (symbol-plist symbol)
	     (list* indicator value (symbol-plist symbol)))
       value)
    (cond ((endp (cdr pl))
	   (error "~S has an odd number of items in its property list."
		  symbol))
	  ((eq (car pl) indicator)
	   (rplaca (cdr pl) value)
	   (return value)))))

(defun remprop (symbol indicator)
  "Look on property list of SYMBOL for property with specified
  INDICATOR.  If found, splice this indicator and its value out of
  the plist, and return the tail of the original list starting with
  INDICATOR.  If not found, return () with no side effects."
  (do ((pl (symbol-plist symbol) (cddr pl))
       (prev nil pl))
      ((atom pl) nil)
    (cond ((atom (cdr pl))
	   (error "~S has an odd number of items in its property list."
		  symbol))
	  ((eq (car pl) indicator)
	   (cond (prev (rplacd (cdr prev) (cddr pl)))
		 (t
		  (setf (symbol-plist symbol) (cddr pl))))
	   (return pl)))))

(defun getf (place indicator &optional (default ()))
  "Searches the property list stored in Place for an indicator EQ to Indicator.
  If one is found, the corresponding value is returned, else the Default is
  returned."
  (do ((plist place (cddr plist)))
      ((null plist) default)
    (cond ((atom (cdr plist))
	   (error "~S is a malformed property list."
		  place))
	  ((eq (car plist) indicator)
	   (return (cadr plist))))))


(defun get-properties (place indicator-list)
  "Like GETF, except that Indicator-List is a list of indicators which will
  be looked for in the property list stored in Place.  Three values are
  returned, see manual for details."
  (do ((plist place (cddr plist)))
      ((null plist) (values nil nil nil))
    (cond ((atom (cdr plist))
	   (error "~S is a malformed proprty list."
		  place))
	  ((memq (car plist) indicator-list)
	   (return (values (car plist) (cadr plist) plist))))))

(defun copy-symbol (symbol &optional (copy-props nil) &aux new-symbol)
  "Make and return a new uninterned symbol with the same print name
  as SYMBOL.  If COPY-PROPS is null, the new symbol has no properties.
  Else, it has a copy of SYMBOL's property list."
  (setq new-symbol (make-symbol (symbol-name symbol)))
  (if copy-props
      (setf (symbol-plist new-symbol) (copy-list (symbol-plist symbol))))
  new-symbol)

(proclaim '(special *keyword-package*))

(defun keywordp (object)
  "Returns true if Object is a symbol in the keyword package."
  (and (symbolp object)
       (eq (symbol-package object) *keyword-package*)))


;;;; Gensym and friends.

(defvar *gensym-counter* 0
  "Counter for generating unique GENSYM symbols.")

(defun gensym (&optional string)
  "Creates a new uninterned symbol whose name is a prefix string (defaults
  to \"G\"), followed by a decimal number.  String, when supplied, will
  alter the prefix if it is a string, or the decimal number if it is a
  number, of this symbol.  The number, defaultly *gensym-counter*, is
  incremented by each call to GENSYM."
  (let* ((*print-base* 10)
	 (*print-radix* nil)
	 (*print-pretty* nil)
	 (prefix (if (stringp string) string "G"))
	 (number (prin1-to-string (if (numberp string)
				      string
				      (incf *gensym-counter*)))))
    (make-symbol (concatenate 'simple-string prefix number))))

(defun gentemp (&optional (prefix t) (package *package*))
  "Creates a new symbol interned in package Package with the given Prefix."
  (loop
    (let ((*print-base* 10)
	  (*print-radix* nil)
	  (*print-pretty* nil)
	  (new-pname (format nil "~A~D"
			     (string prefix) (incf *gensym-counter*))))
      (multiple-value-bind (symbol existsp)
			   (find-symbol new-pname package)
	(declare (ignore symbol))
	(unless existsp (return (values (intern new-pname package))))))))
