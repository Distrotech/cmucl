;;; -*- Package: Hemlock; Log: hemlock.log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/hemlock/ts-stream.lisp,v 1.1.1.7 1991/05/27 13:49:02 chiles Exp $")
;;;
;;; **********************************************************************
;;;
;;; This file implements typescript streams.
;;;
;;; Written by William Lott.
;;;

(in-package "HEMLOCK")



;;;; Public interface from "EXTENSIONS" package.

(in-package "EXT")

(export '(get-stream-command stream-command stream-command-p stream-command-name
	  stream-command-args make-stream-command))

(defstruct (stream-command (:print-function print-stream-command)
			   (:constructor make-stream-command
					 (name &optional args)))
  (name nil :type symbol)
  (args nil :type list))

(defun print-stream-command (obj str n)
  (declare (ignore n))
  (format str "#<Stream-Cmd ~S>" (stream-command-name obj)))


;;; GET-STREAM-COMMAND -- Public.
;;;
;;; We can't simply call the stream's misc method because because nil is an
;;; ambiguous return value: does it mean text arrived, or does it mean the
;;; stream's misc method had no :get-command implementation.  We can't return
;;; nil until there is text input.  We don't need to loop because any stream
;;; implementing :get-command would wait until it had some input.  If the
;;; LISTEN fails, then we have some random stream we must wait on.
;;;
(defun get-stream-command (stream)
  "This takes a stream and waits for text or a command to appear on it.  If
   text appears before a command, this returns nil, and otherwise it returns
   a command."
  (let ((cmdp (funcall (lisp::stream-misc stream) stream :get-command)))
    (cond (cmdp)
	  ((listen stream)
	   nil)
	  (t
	   ;; This waits for input and returns nil when it arrives.
	   (unread-char (read-char stream) stream)))))



;;;; Package for rest of file.

(in-package "HEMLOCK")



;;;; Ts-streams.

(defconstant ts-stream-output-buffer-size 512)

(defstruct (ts-stream
	    (:include stream
		      (in #'%ts-stream-in)
		      (out #'%ts-stream-out)
		      (sout #'%ts-stream-sout)
		      (misc #'%ts-stream-misc))
	    (:print-function %ts-stream-print)
	    (:constructor make-ts-stream (wire typescript)))
  wire
  typescript
  (output-buffer (make-string ts-stream-output-buffer-size)
		 :type simple-string)
  (output-buffer-index 0 :type fixnum)
  ;;
  ;; The current output character position on the line, returned by the
  ;; :CHARPOS method.
  (char-pos 0 :type fixnum)
  ;;
  ;; The current length of a line of output.  Returned by the :LINE-LENGTH
  ;; method.
  (line-length 80)
  ;;
  ;; This is a list of strings and stream-commands whose order manifests the
  ;; input provided by remote procedure calls into the slave of
  ;; TS-STREAM-ACCEPT-INPUT.
  (current-input nil :type list)
  (input-read-index 0 :type fixnum))

(defun %ts-stream-print (ts stream depth)
  (declare (ignore ts depth))
  (write-string "#<TS Stream>" stream))



;;;; Conditions.

(define-condition unexpected-stream-command (error)
  ;; Context is a string to be plugged into the report text.
  ((context))
  (:report (lambda (condition stream)
	     (format stream "~&Unexpected stream-command while ~A."
		     (unexpected-stream-command-context condition)))))



;;;; Editor remote calls into slave.

;;; TS-STREAM-ACCEPT-INPUT -- Internal Interface.
;;;
;;; The editor calls this remotely in the slave to indicate that the user has
;;; provided input.  Input is a string, symbol, or list.  If it is a list, the
;;; the CAR names the command, and the CDR is the arguments.
;;;
(defun ts-stream-accept-input (remote input)
  (let ((stream (wire:remote-object-value remote)))
    (system:without-interrupts
     (system:without-gcing
      (setf (ts-stream-current-input stream)
	    (nconc (ts-stream-current-input stream)
		   (list (etypecase input
			   (string input)
			   (cons
			    (ext:make-stream-command (car input)
						     (cdr input)))
			   (symbol
			    (ext:make-stream-command input)))))))))
  nil)

;;; TS-STREAM-SET-LINE-LENGTH -- Internal Interface.
;;;
;;; This function is called by the editor to indicate that the line-length for
;;; a TS stream should now be Length.
;;;
(defun ts-stream-set-line-length (remote length)
  (let ((stream (wire:remote-object-value remote)))
    (setf (ts-stream-line-length stream) length)))



;;;; Stream methods.

;;; %TS-STREAM-LISTEN -- Internal.
;;;
;;; Determine if there is any input available.  If we don't think so, process
;;; all pending events, and look again.
;;; 
(defun %ts-stream-listen (stream)
  (flet ((check ()
	   (system:without-interrupts
	    (system:without-gcing
	     (loop
	       (let* ((current (ts-stream-current-input stream))
		      (first (first current)))
		 (cond ((null current)
			(return nil))
		       ((ext:stream-command-p first)
			(return t))
		       ((>= (ts-stream-input-read-index stream)
			    (length (the simple-string first)))
			(pop (ts-stream-current-input stream))
			(setf (ts-stream-input-read-index stream) 0))
		       (t
			(return t)))))))))
    (or (check)
	(progn
	  (system:serve-all-events 0)
	  (check)))))

;;; %TS-STREAM-IN -- Internal.
;;;
;;; The READ-CHAR stream method.
;;; 
(defun %ts-stream-in (stream &optional eoferr eofval)
  (declare (ignore eoferr eofval)) ; EOF's are impossible.
  (wait-for-typescript-input stream)
  (system:without-interrupts
   (system:without-gcing
    (let ((first (first (ts-stream-current-input stream))))
      (etypecase first
	(string
	 (prog1 (schar first (ts-stream-input-read-index stream))
	   (incf (ts-stream-input-read-index stream))))
	(ext:stream-command
	 (error 'unexpected-stream-command
		:context "in the READ-CHAR method")))))))

;;; %TS-STREAM-READ-LINE -- Internal.
;;;
;;; The READ-LINE stream method.  Note: here we take advantage of the fact that
;;; newlines will only appear at the end of strings.
;;; 
(defun %ts-stream-read-line (stream eoferr eofval)
  (declare (ignore eoferr eofval))
  (macrolet
      ((next-str ()
	 '(progn
	    (wait-for-typescript-input stream)
	    (system:without-interrupts
	     (system:without-gcing
	      (let ((first (first (ts-stream-current-input stream))))
		(etypecase first
		  (string
		   (prog1 (if (zerop (ts-stream-input-read-index stream))
			      (pop (ts-stream-current-input stream))
			      (subseq (pop (ts-stream-current-input stream))
				      (ts-stream-input-read-index stream)))
		     (setf (ts-stream-input-read-index stream) 0)))
		  (ext:stream-command
		   (error 'unexpected-stream-command
			  :context "in the READ-CHAR method")))))))))
    (do ((result (next-str) (concatenate 'simple-string result (next-str))))
	((char= (schar result (1- (length result))) #\newline)
	 (values (subseq result 0 (1- (length result)))
		 nil))
      (declare (simple-string result)))))

;;; WAIT-FOR-TYPESCRIPT-INPUT -- Internal.
;;;
;;; Keep calling server until some input shows up.
;;; 
(defun wait-for-typescript-input (stream)
  (unless (%ts-stream-listen stream)
    (let ((wire (ts-stream-wire stream))
	  (ts (ts-stream-typescript stream)))
      (system:without-interrupts
       (system:without-gcing
	(wire:remote wire (ts-buffer-ask-for-input ts))
	(wire:wire-force-output wire)))
      (loop
	(system:serve-all-events)
	(when (%ts-stream-listen stream)
	  (return))))))

;;; %TS-STREAM-FLSBUF --- internal.
;;;
;;; Flush the output buffer associated with stream.  This should only be used
;;; inside a without-interrupts and without-gcing.
;;; 
(defun %ts-stream-flsbuf (stream)
  (when (and (ts-stream-wire stream)
	     (ts-stream-output-buffer stream)
	     (not (zerop (ts-stream-output-buffer-index stream))))
    (wire:remote (ts-stream-wire stream)
      (ts-buffer-output-string
       (ts-stream-typescript stream)
       (subseq (the simple-string (ts-stream-output-buffer stream))
	       0
	       (ts-stream-output-buffer-index stream))))
    (setf (ts-stream-output-buffer-index stream) 0)))

;;; %TS-STREAM-OUT --- internal.
;;;
;;; Output a single character to stream.
;;;
(defun %ts-stream-out (stream char)
  (declare (base-character char))
  (system:without-interrupts
   (system:without-gcing
    (when (= (ts-stream-output-buffer-index stream)
	     ts-stream-output-buffer-size)
      (%ts-stream-flsbuf stream))
    (setf (schar (ts-stream-output-buffer stream)
		 (ts-stream-output-buffer-index stream))
	  char)
    (incf (ts-stream-output-buffer-index stream))
    (incf (ts-stream-char-pos stream))
    (when (= (char-code char)
	     (char-code #\Newline))
      (%ts-stream-flsbuf stream)
      (setf (ts-stream-char-pos stream) 0)
      (wire:wire-force-output (ts-stream-wire stream)))
    char)))

;;; %TS-STREAM-SOUT --- internal.
;;;
;;; Output a string to stream.
;;; 
(defun %ts-stream-sout (stream string start end)
  (declare (simple-string string))
  (declare (fixnum start end))
  (let ((wire (ts-stream-wire stream))
	(newline (position #\Newline string :start start :end end :from-end t))
	(length (- end start)))
    (when wire
      (system:without-interrupts
       (system:without-gcing
	(let ((index (ts-stream-output-buffer-index stream)))
	  (cond ((> (+ index length)
		    ts-stream-output-buffer-size)
		 (%ts-stream-flsbuf stream)
		 (wire:remote wire
		   (ts-buffer-output-string (ts-stream-typescript stream)
					    (subseq string start end)))
		 (when newline
		   (wire:wire-force-output wire)))
		(t
		 (replace (the simple-string (ts-stream-output-buffer stream))
			  string
			  :start1 index
			  :end1 (+ index length)
			  :start2 start
			  :end2 end)
		 (incf (ts-stream-output-buffer-index stream)
		       length)
		 (when newline
		   (%ts-stream-flsbuf stream)
		   (wire:wire-force-output wire)))))
	(setf (ts-stream-char-pos stream)
	      (if newline
		  (- end newline 1)
		  (+ (ts-stream-char-pos stream)
		     length))))))))

;;; %TS-STREAM-UNREAD -- Internal.
;;;
;;; Unread a single character.
;;; 
(defun %ts-stream-unread (stream char)
  (system:without-interrupts
   (system:without-gcing
    (let ((first (first (ts-stream-current-input stream))))
      (cond ((and (stringp first)
		  (> (ts-stream-input-read-index stream) 0))
	     (setf (schar first (decf (ts-stream-input-read-index stream)))
		   char))
	    (t
	     (push (string char) (ts-stream-current-input stream))
	     (setf (ts-stream-input-read-index stream) 0)))))))

;;; %TS-STREAM-CLOSE --- internal.
;;;
;;; Can't do much, 'cause the wire is shared.
;;; 
(defun %ts-stream-close (stream abort)
  (unless abort
    (force-output stream))
  (lisp::set-closed-flame stream))

;;; %TS-STREAM-CLEAR-INPUT -- Internal.
;;;
;;; Pass the request to the editor and clear any buffered input.
;;;
(defun %ts-stream-clear-input (stream)
  (system:without-interrupts
   (system:without-gcing
    (when (ts-stream-wire stream)
      (wire:remote-value (ts-stream-wire stream)
	(ts-buffer-clear-input (ts-stream-typescript stream))))
    (setf (ts-stream-current-input stream) nil
	  (ts-stream-input-read-index stream) 0))))

;;; %TS-STREAM-MISC -- Internal.
;;;
;;; The misc stream method.
;;; 
(defun %ts-stream-misc (stream operation &optional arg1 arg2)
  (case operation
    (:read-line
     (%ts-stream-read-line stream arg1 arg2))
    (:listen
     (%ts-stream-listen stream))
    (:unread
     (%ts-stream-unread stream arg1))
    (:get-command
     (wait-for-typescript-input stream)
     (system:without-interrupts
      (system:without-gcing
       (etypecase (first (ts-stream-current-input stream))
	 (stream-command
	  (setf (ts-stream-input-read-index stream) 0)
	  (pop (ts-stream-current-input stream)))
	 (string nil)))))
    (:close
     (%ts-stream-close stream arg1))
    (:clear-input
     (%ts-stream-clear-input stream)
     t)
    (:finish-output
     (when (ts-stream-wire stream)
       (system:without-interrupts
	(system:without-gcing
	 (%ts-stream-flsbuf stream)
	 ;; Note: for the return value to come back,
	 ;; all pending RPCs must have completed.
	 ;; Therefore, we know it has synced.
	 (wire:remote-value (ts-stream-wire stream)
	   (ts-buffer-finish-output (ts-stream-typescript stream))))))
     t)
    (:force-output
     (when (ts-stream-wire stream)
       (system:without-interrupts
	(system:without-gcing
	 (%ts-stream-flsbuf stream)
	 (wire:wire-force-output (ts-stream-wire stream)))))
     t)
    (:clear-output
     (setf (ts-stream-output-buffer-index stream) 0)
     t)
    (:element-type
     'base-character)
    (:charpos
     (ts-stream-char-pos stream))
    (:line-length
     (ts-stream-line-length stream))))
