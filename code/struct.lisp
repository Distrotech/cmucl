;;; -*- Log: code.log; Package: Lisp -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/struct.lisp,v 1.12 1991/12/14 08:55:21 wlott Exp $")
;;;
;;; **********************************************************************
;;;
;;;    This file contains structure definitions that need to be compiled early
;;; for bootstrapping reasons.
;;;
(in-package 'lisp)

;;;; Defstruct structures:

(in-package 'c)

(defstruct (defstruct-description
             (:conc-name dd-)
             (:print-function print-defstruct-description)
	     (:make-load-form-fun :just-dump-it-normally))
  name				; name of the structure
  doc				; documentation on the structure
  slots				; list of slots
  conc-name			; prefix for slot names
  (constructors ())		; list of standard constructor function names
  boa-constructors		; BOA constructors (cdr of option).
  copier			; name of copying function
  predicate			; name of type predictate
  include			; name of included structure
  (includes ())			; names of all structures included by this one
  (included-by ())		; names of all strctures that include this one 
  print-function		; function used to print it
  type				; type specified, Structure if no type specified.
  lisp-type			; actual type used for implementation.
  named				; T if named, Nil otherwise
  offset			; first slot's offset into implementation sequence
  (length nil :type (or fixnum null)) ; total length of the thing
  make-load-form-fun)		; make-load-form function.


(defstruct (defstruct-slot-description
             (:conc-name dsd-)
             (:print-function print-defstruct-slot-description)
	     (:make-load-form-fun :just-dump-it-normally))
  %name				; string name of slot
  (index (required-argument) :type fixnum) ; its position in the implementation sequence
  accessor			; name of it accessor function
  default			; default value
  type				; declared type
  read-only)			; T if there's to be no setter for it


(in-package 'lisp)

;;;; The stream structure:

(defconstant in-buffer-length 100 "The size of a stream in-buffer.")

(defstruct (stream (:predicate streamp) (:print-function %print-stream))
  ;;
  ;; Buffered input.
  (in-buffer nil :type (or (simple-array * (*)) null))
  (in-index in-buffer-length :type index)	; Index into in-buffer
  (in #'ill-in :type function)			; Read-Char function
  (bin #'ill-bin :type function)		; Byte input function
  (n-bin #'ill-bin :type function)		; N-Byte input function
  (out #'ill-out :type function)		; Write-Char function
  (bout #'ill-bout :type function)		; Byte output function
  (sout #'ill-out :type function)		; String output function
  (misc #'do-nothing :type function))		; Less used methods


;;;; Alien structures:
 
(defstruct (alien-value
	    (:constructor make-alien-value (sap offset size type))
	    (:print-function %print-alien-value))
  "This structure represents an Alien value."
  sap
  offset
  size
  type)

(defstruct (ct-a-val
	    (:print-function
	     (lambda (s stream d)
	       (declare (ignore s d))
	       (write-string "#<Alien compiler info>" stream))))
  type		; Type of expression, NIL if unknown.
  size		; Expression for the size of the alien.
  sap		; Expression for SAP.
  offset	; Expression for bit offset.
  alien)	; Expression for alien-value or NIL.


(defstruct (alien-info
	    (:print-function %print-alien-info)
	    (:constructor
	     make-alien-info (function num-args arg-types result-type)))
  function	; The function the definition was made into.
  num-args	; The total number of arguments.
  arg-types	; Alist of arg numbers to types of Alien args.
  result-type)	; The type of the resulting Alien.


(defstruct (stack-info
	    (:print-function
	     (lambda (s stream d)
	       (declare (ignore s d))
	       (format stream "#<Alien stack info>"))))
  type
  size)


(defstruct enumeration-info
  signed	; True if minimum value negative.
  size		; Minimum number of bits needed to hold value.
  from		; Symbol holding alist from keywords to integers.
  to		; Symbol holding alist or vector from integers to keywords.
  kind		; Kind of from mapping, :vector or :alist.
  offset)	; Offset to add to value for :vector from mapping.


;;; Condition structures:

(in-package "CONDITIONS")

(defstruct (condition (:constructor |constructor for condition|)
                      (:predicate nil)
                      (:print-function condition-print))
  )
