(in-package "USER")

#+bootstrap
(unless (find-package "OLD-XLIB")
  (when (find-package "XLIB")
    (rename-package (find-package "XLIB") "OLD-XLIB"))
  
  (make-package "XLIB" :use '("LISP")))

(with-compiler-log-file
    ("target:compile-clx.log"
     :optimize
     '(optimize (debug-info #-small 2 #+small .5) 
		(speed 2) (inhibit-warnings 2)
		(safety #-small 1 #+small 0))
     :optimize-interface
     '(optimize-interface (debug-info .5))
     :context-declarations
     '(((:and :external :global)
	(declare (optimize-interface (safety 2) (debug-info 1))))
       ((:and :external :macro)
	(declare (optimize (safety 2))))))
  (let ((c::*suppress-values-declaration* t))
    (comf "target:clx/package" :load t)
    (comf "target:clx/defsystem" :load t)
    (comf "target:clx/depdefs" :load t)
    (comf "target:clx/clx" :load t)
    (comf "target:clx/dependent" :load t)
    (comf "target:clx/macros")	; these are just macros
    (load "target:clx/macros")
    (comf "target:clx/bufmac")	; these are just macros
    (load "target:clx/bufmac")
    (comf "target:clx/buffer" :load t)
    (comf "target:clx/display" :load t)
    (comf "target:clx/gcontext" :load t)
    (comf "target:clx/input" :load t)
    (comf "target:clx/requests" :load t)
    (comf "target:clx/fonts" :load t)
    (comf "target:clx/graphics" :load t)
    (comf "target:clx/text" :load t)
    (comf "target:clx/attributes" :load t)
    (comf "target:clx/translate" :load t)
    (comf "target:clx/keysyms" :load t)
    (comf "target:clx/manager" :load t)
    (comf "target:clx/image" :load t)
    (comf "target:clx/resource" :load t))
  (comf "target:code/clx-ext")
  (comf "target:hemlock/charmacs" :load t)
  (comf "target:hemlock/key-event" :load t)
  (comf "target:hemlock/keysym-defs" :load t)

  #-no-pcl
  (comf "target:code/inspect"))

(ext:run-program
 "cat"
 (mapcar #'(lambda (x)
	     (namestring
	      (truename
	       (make-pathname
		:defaults x
		:type (c:backend-fasl-file-type c:*target-backend*)))))
	 '(
	   "target:clx/package"
	   "target:clx/depdefs"
	   "target:clx/clx"
	   "target:clx/dependent"
	   "target:clx/macros"
	   "target:clx/bufmac"
	   "target:clx/buffer"
	   "target:clx/display"
	   "target:clx/gcontext"
	   "target:clx/input"
	   "target:clx/requests"
	   "target:clx/fonts"
	   "target:clx/graphics"
	   "target:clx/text"
	   "target:clx/attributes"
	   "target:clx/translate"
	   "target:clx/keysyms"
	   "target:clx/manager"
	   "target:clx/image"
	   "target:clx/resource"
	   "target:code/clx-ext"
	   "target:hemlock/charmacs"
	   "target:hemlock/key-event"
	   "target:hemlock/keysym-defs"
	   #-no-pcl "target:code/inspect"))
 :if-output-exists :supersede
 :output (make-pathname :defaults "target:clx/clx-library"
			:type (c:backend-fasl-file-type c:*target-backend*)))
