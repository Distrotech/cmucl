;;; -*- Mode: Lisp; Package: Extensions; Log: code.log -*-

;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/code/format-time.lisp,v 1.3 1991/02/08 13:32:55 ram Exp $")
;;;
;;; **********************************************************************

;;; Really slick time printing routines built upon the Common Lisp
;;; format function.

;;; Written by Jim Healy, September 1987. 

;;; **********************************************************************

(in-package "EXTENSIONS" :use '("LISP"))

(export '(format-universal-time format-decoded-time))

(defconstant abbrev-weekday-table
  '#("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))

(defconstant long-weekday-table
  '#("Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"
     "Sunday"))

(defconstant abbrev-month-table
  '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov"
     "Dec"))

(defconstant long-month-table
  '#("January" "February" "March" "April" "May" "June" "July" "August"
     "September" "October" "November" "December"))

;;; The timezone-table is incomplete but workable.

(defconstant timezone-table
  '#("GMT" "" "" "" "" "EST" "CST" "MST" "PST"))

;;; Valid-Destination-P ensures the destination stream is okay
;;; for the Format function.

(defun valid-destination-p (destination)
  (or (not destination)
      (eq destination 't)
      (streamp destination)
      (and (stringp destination)
	   (array-has-fill-pointer-p destination))))

;;; Format-Universal-Time - External.

(defun format-universal-time (destination universal-time
					  &key (timezone nil)
					  (style :short)
					  (date-first t)
					  (print-seconds t)
					  (print-meridian t)
					  (print-timezone t)
					  (print-weekday t))
  "Format-Universal-Time formats a string containing the time and date
   given by universal-time in a common manner.  The destination is any
   destination which can be accepted by the Format function.  The
   timezone keyword is an integer specifying hours west of Greenwich.
   The style keyword can be :short (numeric date), :long (months and
   weekdays expressed as words), :abbreviated (like :long but words are
   abbreviated), or :government (of the form \"XX Mon XX XX:XX:XX\")
   The keyword date-first, if nil, will print the time first instead
   of the date (the default).  The print- keywords, if nil, inhibit
   the printing of the obvious part of the time/date."
  (unless (valid-destination-p destination)
    (error "~A: Not a valid format destination." destination))
  (unless (integerp universal-time)
    (error "~A: Universal-Time should be an integer." universal-time))
  (when timezone
    (unless (and (rationalp timezone) (<= -24 timezone 24))
      (error "~A: Timezone should be a rational between -24 and 24." timezone))
    (unless (zerop (rem timezone 1/3600))
      (error "~A: Timezone is not a second (1/3600) multiple." timezone)))

  (multiple-value-bind (secs mins hours day month year dow dst tz)
		       (if timezone
			   (decode-universal-time universal-time timezone)
			   (decode-universal-time universal-time))
    (declare (ignore dst) (fixnum secs mins hours day month year dow))
    (let ((time-string "~2,'0D:~2,'0D")
	  (date-string
	   (case style
	     (:short "~D/~D/~2,'0D")             ;;  MM/DD/YY
	     ((:abbreviated :long) "~A ~D, ~D")  ;;  Month DD, YYYY
	     (:government "~2,'0D ~:@(~A~) ~D")      ;;  DD MON YY
	     (t
	      (error "~A: Unrecognized :style keyword value." style))))
	  (time-args
	   (list mins (max (mod hours 12) (1+ (mod (1- hours) 12)))))
	  (date-args (case style
		       (:short
			(list month day (mod year 100)))
		       (:abbreviated
			(list (svref abbrev-month-table (1- month)) day year))
		       (:long
			(list (svref long-month-table (1- month)) day year))
		       (:government
			(list day (svref abbrev-month-table (1- month))
			      (mod year 100))))))
      (declare (simple-string time-string date-string))
      (when print-weekday
	(push (case style
		((:short :long) (svref long-weekday-table dow))
		(:abbreviated (svref abbrev-weekday-table dow))
		(:government (svref abbrev-weekday-table dow)))
	      date-args)
	(setq date-string
	      (concatenate 'simple-string "~A, " date-string)))
      (when (or print-seconds (eq style :government))
	(push secs time-args)
	(setq time-string
	      (concatenate 'simple-string time-string ":~2,'0D")))
      (when print-meridian
	(push (signum (floor hours 12)) time-args)
	(setq time-string
	      (concatenate 'simple-string time-string " ~[am~;pm~]")))
      (apply #'format destination
	     (if date-first
		 (concatenate 'simple-string date-string " " time-string
			      (if print-timezone " ~A"))
		 (concatenate 'simple-string time-string " " date-string
			      (if print-timezone " ~A")))
	     (if date-first
		 (nconc date-args (nreverse time-args)
			(if print-timezone
			    (list
			     (let ((which-zone (or timezone tz)))
			       (if (or (= 0 which-zone) (<= 5 which-zone 8))
				   (svref timezone-table which-zone)
				   (format nil "[~D]" which-zone))))))
		 (nconc (nreverse time-args) date-args
			(if print-timezone
			    (list
			     (let ((which-zone (or timezone tz)))
			       (if (or (= 0 which-zone) (< 5 which-zone 8))
				   (svref timezone-table which-zone)
				   (format nil "[~D]" which-zone)))))))))))

;;; Format-Decoded-Time - External.

(defun format-decoded-time (destination seconds minutes hours
					  day month year
					  &key (timezone nil)
					  (style :short)
					  (date-first t)
					  (print-seconds t)
					  (print-meridian t)
					  (print-timezone t)
					  (print-weekday t))
  "Format-Decoded-Time formats a string containing decoded-time
   expressed in a humanly-readable manner.  The destination is any
   destination which can be accepted by the Format function.  The
   timezone keyword is an integer specifying hours west of Greenwich.
   The style keyword can be :short (numeric date), :long (months and
   weekdays expressed as words), or :abbreviated (like :long but words are
   abbreviated).  The keyword date-first, if nil, will cause the time
   to be printed first instead of the date (the default).  The print-
   keywords, if nil, inhibit the printing of certain semi-obvious
   parts of the string."
  (unless (valid-destination-p destination)
    (error "~A: Not a valid format destination." destination))
  (unless (and (integerp seconds) (<= 0 seconds 59))
    (error "~A: Seconds should be an integer between 0 and 59." seconds))
  (unless (and (integerp minutes) (<= 0 minutes 59))
    (error "~A: Minutes should be an integer between 0 and 59." minutes))
  (unless (and (integerp hours) (<= 0 hours 23))
    (error "~A: Hours should be an integer between 0 and 23." hours))
  (unless (and (integerp day) (<= 1 day 31))
    (error "~A: Day should be an integer between 1 and 31." day))
  (unless (and (integerp month) (<= 1 month 12))
    (error "~A: Month should be an integer between 1 and 12." month))
  (unless (and (integerp year) (plusp year))
    (error "~A: Hours should be an non-negative integer." year))
  (when timezone
    (unless (and (integerp timezone) (<= 0 timezone 32))
      (error "~A: Timezone should be an integer between 0 and 32."
	     timezone)))
  (format-universal-time destination
   (encode-universal-time seconds minutes hours day month year)
   :timezone timezone :style style :date-first date-first
   :print-seconds print-seconds :print-meridian print-meridian
   :print-timezone print-timezone :print-weekday print-weekday))


