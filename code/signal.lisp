;;; -*- Log: code.log; Package: MACH -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/signal.lisp,v 1.5 1990/09/09 20:36:24 wlott Exp $
;;;
;;; Code for handling UNIX signals.
;;; 
;;; Written by William Lott.
;;;

(in-package "MACH")

(export '(unix-signal-name unix-signal-description unix-signal-number
	  sigcontext sigmask unix-sigblock unix-sigpause
	  unix-sigsetmask unix-kill unix-getpid))

(export 'kernel::signal-init (find-package "KERNEL"))

;;; These should probably be somewhere, but I don't know where.
;;; 
(defconstant sig_dfl 0)
(defconstant sig_ign 1)



;;;; Utilities for dealing with signal names and numbers.

(defstruct (unix-signal
	    (:constructor make-unix-signal (%name %number %description)))
  %name				; Signal keyword
  (%number :type integer)       ; UNIX signal number
  (%description :type string))  ; Documentation

(defvar *unix-signals* nil
  "A list of unix signal structures.")

(eval-when (compile eval)
(defmacro def-unix-signal (name number description)
  (let ((mach-symbol (intern (symbol-name name))))
    `(progn
       (push (make-unix-signal ,name ,number ,description) *unix-signals*)
       ;; 
       ;; This is to make the new signal lookup stuff compatible with
       ;; old code which expects the symbol with the same print name as
       ;; our keywords to be a constant with a value equal to the signal
       ;; number.
       (defconstant ,mach-symbol ,number ,description)
       (export ',mach-symbol))))
) ;eval-when

(defun unix-signal-or-lose (arg)
  (let ((signal (find arg *unix-signals*
		      :key (etypecase arg
			     (symbol #'unix-signal-%name)
			     (number #'unix-signal-%number)))))
    (unless signal
      (error "~S is not a valid signal name or number." arg))
    signal))

(defun unix-signal-name (signal)
  "Return the name of the signal as a string.  Signal should be a valid
  signal number or a keyword of the standard UNIX signal name."
  (symbol-name (unix-signal-%name (unix-signal-or-lose signal))))

(defun unix-signal-description (signal)
  "Return a string describing signal.  Signal should be a valid signal
  number or a keyword of the standard UNIX signal name."
  (unix-signal-%description (unix-signal-or-lose signal)))

(defun unix-signal-number (signal)
  "Return the number of the given signal.  Signal should be a valid
  signal number or a keyword of the standard UNIX signal name."
  (unix-signal-%number (unix-signal-or-lose signal)))

;;; Known signals
;;; 
(def-unix-signal :CHECK 0 "Check")
(def-unix-signal :SIGHUP 1 "Hangup")
(def-unix-signal :SIGINT 2 "Interrupt")
(def-unix-signal :SIGQUIT 3 "Quit")
(def-unix-signal :SIGILL 4 "Illegal instruction")
(def-unix-signal :SIGTRAP 5 "Trace trap")
(def-unix-signal :SIGIOT 6 "Iot instruction")
(def-unix-signal :SIGEMT 7 "Emt instruction")
(def-unix-signal :SIGFPE 8 "Floating point exception")
(def-unix-signal :SIGKILL 9 "Kill")
(def-unix-signal :SIGBUS 10 "Bus error")
(def-unix-signal :SIGSEGV 11 "Segmentation violation")
(def-unix-signal :SIGSYS 12 "Bad argument to system call")
(def-unix-signal :SIGPIPE 13 "Write on a pipe with no one to read it")
(def-unix-signal :SIGALRM 14 "Alarm clock")
(def-unix-signal :SIGTERM 15 "Software termination signal")
(def-unix-signal :SIGURG 16 "Urgent condition present on socket")
(def-unix-signal :SIGSTOP 17 "Stop")
(def-unix-signal :SIGTSTP 18 "Stop signal generated from keyboard")
(def-unix-signal :SIGCONT 19 "Continue after stop")
(def-unix-signal :SIGCHLD 20 "Child status has changed")
(def-unix-signal :SIGTTIN 21 "Background read attempted from control terminal")
(def-unix-signal :SIGTTOU 22 "Background write attempted to control terminal")
(def-unix-signal :SIGIO 23 "I/O is possible on a descriptor")
(def-unix-signal :SIGXCPU 24 "Cpu time limit exceeded")
(def-unix-signal :SIGXFSZ 25 "File size limit exceeded")
(def-unix-signal :SIGVTALRM 26 "Virtual time alarm")
(def-unix-signal :SIGPROF 27 "Profiling timer alarm")
(def-unix-signal :SIGWINCH 28 "Window size change")
(def-unix-signal :SIGUSR1 30 "User defined signal 1")
(def-unix-signal :SIGUSR2 31 "User defined signal 2")
;;; 
;;; These are Mach Specific
(def-unix-signal :SIGEMSG 30 "Mach Emergency message")
(def-unix-signal :SIGMSG 31 "Mach message")

;;; SIGMASK -- Public
;;;
(defmacro sigmask (&rest signals)
  "Returns a mask given a set of signals."
  (apply #'logior
	 (mapcar #'(lambda (signal)
		     (ash 1 (1- (unix-signal-number signal))))
		 signals)))


;;;; System calls that deal with signals.

(proclaim '(inline real-unix-kill))

(def-c-routine ("kill" real-unix-kill) (int)
  (pid int)
  (signal int))

(defun unix-kill (pid signal)
  "Unix-kill sends the signal signal to the process with process 
   id pid.  Signal should be a valid signal number or a keyword of the
   standard UNIX signal name."
  (real-unix-kill pid (unix-signal-number signal)))


(proclaim '(inline real-unix-killpg))

(def-c-routine ("killpg" real-unix-killpg) (int)
  (pgrp int)
  (signal int))

(defun unix-killpg (pgrp signal)
  "Unix-killpg sends the signal signal to the all the process in process
  group PGRP.  Signal should be a valid signal number or a keyword of
  the standard UNIX signal name."
  (real-unix-killpg pgrp (unix-signal-number signal)))


(def-c-routine ("sigblock" unix-sigblock) (unsigned-long)
  "Unix-sigblock cause the signals specified in mask to be
   added to the set of signals currently being blocked from
   delivery.  The macro sigmask is provided to create masks."
  (mask unsigned-long))


(def-c-routine ("sigpause" unix-sigpause) (void)
  "Unix-sigpause sets the set of masked signals to its argument
   and then waits for a signal to arrive, restoring the previous
   mask upon its return."
  (mask unsigned-long))


(def-c-routine ("sigsetmask" unix-sigsetmask) (unsigned-long)
  "Unix-sigsetmask sets the current set of masked signals (those
   begin blocked from delivery) to the argument.  The macro sigmask
   can be used to create the mask.  The previous value of the signal
   mask is returned."
  (mask unsigned-long))



;;;; C routines that actually do all the work of establishing signal handlers.

(def-c-routine ("install_handler" install-handler)
	       (unsigned-long)
  (signal int)
  (handler unsigned-long))




;;;; Interface to enabling and disabling signal handlers.

(defun enable-interrupt (signal handler)
  (declare (type (or function (member :default :ignore)) handler))
  (without-gcing
   (let ((result (install-handler (unix-signal-number signal)
				  (case handler
				    (:default sig_dfl)
				    (:ignore sig_ign)
				    (t (di::get-lisp-obj-address handler))))))
     (cond ((= result sig_dfl) :default)
	   ((= result sig_ign) :ignore)
	   (t (the function (di::make-lisp-obj result)))))))

(defun default-interrupt (signal)
  (enable-interrupt signal :ignore))

(defun ignore-interrupt (signal)
  (enable-interrupt signal :default))



;;;; Default LISP signal handlers.

;;; Most of these just call ERROR to report the presence of the signal.

(defmacro define-signal-handler (name what &optional (function 'error))
  `(defun ,name (signal code scp)
     (declare (ignore signal code))
     (alien-bind ((sc
		   (make-alien 'mach:sigcontext
			       #.(c-sizeof 'mach:sigcontext)
			       scp)
		   mach:sigcontext
		   t))
       (,function ,(concatenate 'simple-string what " at #x~x.")
		  (sap-int
		   (alien-access (mach:sigcontext-pc (alien-value sc))))))))

(define-signal-handler sigint-handler "Interrupted" break)
(define-signal-handler sigill-handler "Illegal Instruction")
(define-signal-handler sigiot-handler "SIGIOT")
(define-signal-handler sigemt-handler "SIGEMT")
(define-signal-handler sigfpe-handler "SIGFPE")
(define-signal-handler sigbus-handler "Bus Error")
(define-signal-handler sigsegv-handler "Segmentation Violation")
(define-signal-handler sigsys-handler "Bad Argument to a System Call")
(define-signal-handler sigpipe-handler "SIGPIPE")
(define-signal-handler sigalrm-handler "SIGALRM")

(defun sigquit-handler (signal code scp)
  (declare (ignore signal code scp))
  (throw 'lisp::top-level-catcher nil))

(defun signal-init ()
  "Enable all the default signals that Lisp knows how to deal with."
  #+nil (enable-interrupt :sigint #'sigint-handler)
  (enable-interrupt :sigquit #'sigquit-handler)
  (enable-interrupt :sigill #'sigill-handler)
  (enable-interrupt :sigtrap #'kernel::internal-error)
  (enable-interrupt :sigiot #'sigiot-handler)
  (enable-interrupt :sigemt #'sigemt-handler)
  #+nil (enable-interrupt :sigfpe #'sigfpe-handler)
  (enable-interrupt :sigbus #'sigbus-handler)
  (enable-interrupt :sigsegv #'sigsegv-handler)
  (enable-interrupt :sigsys #'sigsys-handler)
  (enable-interrupt :sigpipe #'sigpipe-handler)
  (enable-interrupt :sigalrm #'sigalrm-handler)
  nil)



;;;; Macros for dynamically enabling and disabling signal handling.

;;; Notes on how the without-interrupts/with-interrupts stuff works.
;;;
;;; Before invoking the supplied handler for any of the signals that can be
;;; blocked, the C interrupt support code checks to see if *interrupts-enabled*
;;; has been bound to NIL.  If so, it saves the signal number and the value of
;;; the signal mask (from the sigcontext), sets the signal mask to block all
;;; blockable signals, sets *interrupt-pending* and returns without handling
;;; the signal.
;;;
;;; When we drop out the without interrupts, we check to see if
;;; *interrupt-pending* has been set.  If so, we call do-pending-interrupt,
;;; which generates a SIGTRAP.  The C code invokes the handler for the saved
;;; signal instead of the SIGTRAP after replacing the signal mask in the
;;; sigcontext with the saved value.  When that hander returns, the original
;;; signal mask is installed, allowing any other pending signals to be handled.
;;;
;;; This means that the cost of without-interrupts is just a special binding in
;;; the case when no signals are delivered (the normal case).  It's only when
;;; a signal is actually delivered that we use any system calls, and by then
;;; the cost of the extra system calls are lost in the noise when compared
;;; with the cost of delivering the signal in the first place.
;;;

(defvar *interrupts-enabled* t)
(defvar *interrupt-pending* nil)

;;; DO-PENDING-INTERRUPT  --  internal
;;;
;;; Magically converted by the compiler into a break instruction.
;;; 
(defun do-pending-interrupt ()
  (do-pending-interrupt))

;;; WITHOUT-INTERRUPTS  --  puiblic
;;; 
(defmacro without-interrupts (&body body)
  "Execute BODY in a context impervious to interrupts."
  (let ((name (gensym)))
    `(flet ((,name () ,@body))
       (if *interrupts-enabled*
	   (unwind-protect
	       (let ((*interrupts-enabled* nil))
		 (,name))
	     (when *interrupt-pending*
	       (do-pending-interrupt)))
	   (,name)))))

;;; WITH-INTERRUPTS  --  puiblic
;;;
(defmacro with-interrupts (&body body)
  "Allow interrupts while executing BODY.  As interrupts are normally allowed,
  this is only useful inside a WITHOUT-INTERRUPTS."
  (let ((name (gensym)))
    `(flet ((,name () ,@body))
       (if *interrupts-enabled*
	   (,name)
	   (let ((*interrupts-enabled* t))
	     (when *interrupt-pending*
	       (do-pending-interrupt))
	     (,name))))))

