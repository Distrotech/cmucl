;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;;    Structures for the second (virtual machine) intermediate representation
;;; in the compiler, IR2.
;;;
;;; Written by Rob MacLachlan
;;;
(in-package 'c)

(proclaim '(special *sc-numbers*))

(eval-when (compile load eval)

;;;
;;; The largest number of TNs whose liveness changes that we can have in any
;;; block.
(defconstant local-tn-limit 64)

(deftype local-tn-number () `(integer 0 (,local-tn-limit)))
(deftype local-tn-count () `(integer 0 ,local-tn-limit)) 
(deftype local-tn-vector () `(simple-vector ,local-tn-limit))
(deftype local-tn-bit-vector () `(simple-bit-vector ,local-tn-limit))

;;; Type of an SC number.
(deftype sc-number () `(integer 0 (,sc-number-limit)))

;;; Types for vectors indexed by SC numbers.
(deftype sc-vector () `(simple-vector ,sc-number-limit))
(deftype sc-bit-vector () `(simple-bit-vector ,sc-number-limit))

;;; The different policies we can use to determine the coding strategy.
;;;
(deftype policies ()
  '(member :safe :small :fast :fast-safe))

); Eval-When (Compile Load Eval)


;;;; Primitive types:
;;;
;;;    The primitive type is used to represent the aspects of type interesting
;;; to the VM.  Selection of IR2 translation templates is done on the basis of
;;; the primitive types of the operands, and the primitive type of a value
;;; is used to constrain the possible representations of that value.
;;;
(defstruct (primitive-type (:print-function %print-primitive-type))
  ;;
  ;; The name of this primitive-type.
  (name nil :type symbol)
  ;;
  ;; A list the SC numbers for all the SCs that a TN of this type can be
  ;; allocated in.
  (scs nil :type list)
  ;;
  ;; The Lisp type equivalent to this type.  If this type could never be
  ;; returned by Primitive-Type, then this is the NIL (or empty) type.
  (type nil :type ctype)
  ;;
  ;; These slots tell how to do implicit representation conversions and moves.
  ;; If null, then the operation can be done using the standard Move
  ;; VOP, otherwise the value is a template that is emitted to do the move or
  ;; coercion.
  ;;
  ;; Coerce-To-T and Coerce-From-T convert objects of this type to and from the
  ;; default descriptor (boxed) representation.  The Move slot is used to
  ;; determine whether a special move operation is needed to do moves between
  ;; TNs of this primitive type.  Since primitive types are disjoint except for
  ;; their overlap with T, these are all the coercions that we need.
  (coerce-to-t nil :type (or template null))
  (coerce-from-t nil :type (or template null))
  (move nil :type (or template null))
  ;;
  ;; The template used to check that an object is of this type.  This is
  ;; a template of one argument and one result, both of primitive-type T.  If
  ;; the argument is of the correct type, then it is delivered into the result.
  ;; If the type is incorrect, then an error is signalled.
  (check nil :type (or template null)))

(defprinter primitive-type
  name
  (type :test (not (eq (type-specifier type)
		       (primitive-type-name structure)))
	:prin1 (type-specifier type)))


;;;; IR1 annotations used for IR2 conversion:
;;;
;;; Block-Info
;;;    Holds the IR2-Block structure.  If there are overflow blocks, then this
;;;    points to the first IR2-Block.  The Block-Info of the dummy component
;;;    head and tail are dummy IR2 blocks that begin and end the emission order
;;;    thread.
;;;
;;; Component-Info
;;;    Holds the IR2-Component structure.
;;;
;;; Continuation-Info
;;;    Holds the IR2-Continuation structure.  Continuations whose values aren't
;;;    used won't have any.
;;;
;;; Cleanup-Info
;;;    If non-null, then a TN in which the affected dynamic environment pointer
;;;    should be saved after the binding is instantiated.
;;;
;;; Environment-Info
;;;    Holds the IR2-Environment structure.
;;;
;;; Tail-Set-Info
;;;    Holds the Return-Info structure.
;;;
;;; NLX-Info-Info
;;;    Holds the IR2-NLX-Info structure.
;;;
;;; Leaf-Info
;;;    If a non-set lexical variable, the TN that holds the value in the home
;;;    environment.  If a constant, then the corresponding constant TN.
;;;    If an XEP lambda, then the corresponding Entry-Info structure.
;;;
;;; Basic-Combination-Info
;;;    The Template chosen for this call by LTN, null if the call has an
;;;    IR2-Convert method, or if it isn't special-cased at all.
;;;    

;;; The IR2-Block structure holds information about a block that is used during
;;; and after IR2 conversion.  It is stored in the Block-Info slot for the
;;; associated block.
;;;
(defstruct (ir2-block
	    (:constructor make-ir2-block (block))
	    (:print-function %print-ir2-block))
  ;;
  ;; The IR2-Block's number, which differs from Block's Block-Number if any
  ;; blocks are split.  This is assigned by lifetime analysis.
  (number nil :type (or unsigned-byte null))
  ;;
  ;; The IR1 block that this block is in the Info for.  
  (block nil :type cblock)
  ;;
  ;; The next and previous block in emission order (not DFO).  This determines
  ;; which block we drop though to, and also used to chain together overflow
  ;; blocks that result from splitting of IR2 blocks in lifetime analysis.
  (next nil :type (or ir2-block null))
  (prev nil :type (or ir2-block null))
  ;;
  ;; A thread running through all IR2 blocks in this environment, in no
  ;; particular order.
  (environment-next nil :type (or ir2-block null))
  ;;
  ;; Information about unknown-values continuations that is used by stack
  ;; analysis to do stack simulation.  A unknown-values continuation is Pushed
  ;; if it's Dest is in another block.  Similarly, a continuation is Popped if
  ;; its Dest is in this block but has its uses elsewhere.  The continuations
  ;; are in the order that are pushed/popped in the block.  Note that the args
  ;; to a single MV-Combination appear reversed in Popped, since we must
  ;; effectively pop the last argument first.  All pops must come before all
  ;; pushes (although internal MV uses may be interleaved.)  Popped is computed
  ;; by LTN, and Pushed is computed by stack analysis.
  (pushed () :type list)
  (popped () :type list)
  ;;
  ;; The result of stack analysis: lists of all the unknown-values
  ;; continuations on the stack at the block start and end, topmost
  ;; continuation first.
  (start-stack () :type list)
  (end-stack () :type list)
  ;;
  ;; The first and last VOP in this block.  If there are none, both slots are
  ;; null.
  (start-vop nil (or vop null))
  (last-vop nil (or vop null))
  ;;
  ;; Number of local TNs actually allocated.
  (local-tn-count 0 :type local-tn-count)
  ;;
  ;; A vector that maps local TN numbers to TNs.  Some entries may be NIL,
  ;; indicating that that number is unused.  (This allows us to delete local
  ;; conflict information without compressing the LTN numbers.)
  ;;
  ;; If an entry is :More, then this block contains only a single VOP.  This
  ;; VOP has so many more arguments and/or results that they cannot all be
  ;; assigned distinct LTN numbers.  In this case, we assign all the more args
  ;; one LTN number, and all the more results another LTN number.  We can do
  ;; this, since more operands are referenced simultaneously as far as conflict
  ;; analysis is concerned.  Note that all these :More TNs will be global TNs.
  (local-tns (make-array local-tn-limit) :type local-tn-vector)
  ;;
  ;; Bit-vectors used during lifetime analysis to keep track of references to
  ;; local TNs.  When indexed by the LTN number, the index for a TN is non-zero
  ;; in Written if it is ever written in the block, and in Live-Out if
  ;; the first reference is a read.
  (written (make-array local-tn-limit :element-type 'bit
		       :initial-element 0)
	   :type local-tn-bit-vector)
  (live-out (make-array local-tn-limit :element-type 'bit)
	    :type local-tn-bit-vector)
  ;;
  ;; Similar to the above, but is updated by lifetime flow analysis to have a 1
  ;; for LTN numbers of TNs live at the end of the block.  This takes into
  ;; account all TNs that aren't :Live.
  (live-in (make-array local-tn-limit :element-type 'bit
		       :initial-element 0)
	   :type local-tn-bit-vector)
  ;;
  ;; A thread running through the global-conflicts structures for this block,
  ;; sorted by TN number.
  (global-tns nil :type (or global-conflicts null))
  ;;
  ;; The assembler label that points to the beginning of the code for this
  ;; block.  Null when we haven't assigned a label yet.
  (%label nil)
  ;;
  ;; List of Location-Info structures describing all the interesting (to the
  ;; debugger) locations in this block.
  (locations nil :type list))


(defprinter ir2-block
  (pushed :test pushed)
  (popped :test popped)
  (start-vop :test start-vop)
  (last-vop :test last-vop)
  (local-tn-count :test (not (zerop local-tn-count)))
  (%label :test %label))


;;; The IR2-Continuation structure is used to annotate continuations that are
;;; used as a function result continuation or that receive MVs.
;;;
(defstruct (ir2-continuation
	    (:constructor make-ir2-continuation (primitive-type))
	    (:print-function %print-ir2-continuation))
  ;;
  ;; If this is :Delayed, then this is a single value continuation for which
  ;; the evaluation of the use is to be postponed until the evaluation of
  ;; destination.  This can be done for ref nodes or predicates whose
  ;; destination is an IF.
  ;;
  ;; If this is :Fixed, then this continuation has a fixed number of values,
  ;; with the TNs in Locs.
  ;;
  ;; If this is :Unknown, then this is an unknown-values continuation, using
  ;; the passing locations in Locs.
  ;;
  ;; If this is :Unused, then this continuation should never actually be used
  ;; as the destination of a value: it is only used tail-recursively.
  (kind :fixed :type (member :delayed :fixed :unknown :unused))
  ;;
  ;; The primitive-type of the first value of this continuation.  This is
  ;; primarily for internal use during LTN, but it also records the type
  ;; restriction on delayed references.  In multiple-value contexts, this is
  ;; null to indicate that it is meaningless.
  (primitive-type nil :type (or primitive-type null))
  ;;
  ;; Locations used to hold the values of the continuation.  If the number
  ;; of values if fixed, then there is one TN per value.  If the number of
  ;; values is unknown, then this is a two-list of TNs holding the start of the
  ;; values glob and the number of values.
  (locs nil :type list))

(defprinter ir2-continuation
  kind
  primitive-type
  locs)


;;; The IR2-Component serves mostly to accumulate non-code information about
;;; the component being compiled.
;;;;
(defstruct ir2-component
  ;;
  ;; The counter used to allocate global TN numbers.
  (global-tn-counter 0 :type unsigned-byte)
  ;;
  ;; Normal-TNs is the head of the list of all the normal TNs that need to be
  ;; packed, linked through the Next slot.  We place TNs on this list when we
  ;; allocate them so that Pack can find them.
  ;;
  ;; Restricted-TNs are TNs that must be packed within a finite SC.  We pack
  ;; these TNs first to ensure that the restrictions will be satisfied (if
  ;; possible).
  ;;
  ;; Wired-TNs are TNs that must be packed at a specific location.  The SC
  ;; and Offset are already filled in.
  ;;
  ;; Constant-TNs are non-packed TNs that represent constants.  :Constant TNs
  ;; may eventually be converted to :Cached-Constant normal TNs.
  (normal-tns nil :type (or tn null))
  (restricted-tns nil :type (or tn null))
  (wired-tns nil :type (or tn null))
  (constant-tns nil :type (or tn null))
  ;;
  ;; A list of all the pre-packed save TNs, so that they can have their
  ;; lifetime info fixed up by conflicts analysis.
  (pre-packed-save-tns nil :type list)
  ;;
  ;; Values-Generators is a list of all the blocks whose ir2-block has a
  ;; non-null value for Popped.  Values-Generators is a list of all blocks that
  ;; contain a use of a continuation that is in some block's Popped.  These
  ;; slots are initialized by LTN-Analyze as an input to Stack-Analyze. 
  (values-receivers nil :type list)
  (values-generators nil :type list)
  ;;
  ;; A list of all the Exit nodes for non-local exits.
  (exits nil :type list)
  ;;
  ;; An adjustable vector that records all the constants in the constant pool.
  ;; A non-immediate :Constant TN with offset 0 refers to the constant in
  ;; element 0, etc.  Normal constants are represented by the placing the
  ;; Constant leaf in this vector.  A load-time constant is distinguished by
  ;; being a cons (Kind . What).  Kind is a keyword indicating how the constant
  ;; is computed, and What is some context.
  ;; 
  ;; These load-time constants are recognized:
  ;; 
  ;; (:entry . <function>)
  ;;    Is replaced by the code pointer for the specified function.  This is
  ;; 	how compiled code (including DEFUN) gets its hands on a function.
  ;; 	<function> is the XEP lambda for the called function; it's Leaf-Info
  ;; 	should be an Entry-Info structure.
  ;;
  ;; (:label . <label>)
  ;;    Is replaced with the byte offset of that label from the start of the
  ;;    code vector (including the header length.)
  ;;
  ;; A null entry in this vector is a placeholder for implementation overhead
  ;; that is eventually stuffed in somehow.
  ;;
  (constants (make-array 10 :fill-pointer 0 :adjustable t) :type vector)
  ;;
  ;; Some kind of info about the component's run-time representation.  This is
  ;; filled in by the VM supplied Select-Component-Format function.
  format
  ;;
  ;; A list of the Entry-Info structures describing all of the entries into
  ;; this component.  Filled in by entry analysis.
  (entries nil :type list))


;;; The Entry-Info structure condenses all the information that the dumper
;;; needs to create each XEP's function entry data structure.
;;;
(defstruct entry-info
  ;;
  ;; True if this function has a non-null closure environment.
  (closure-p nil :type boolean)
  ;;
  ;; A label pointing to the entry vector for this function.
  (offset nil :type label)
  ;;
  ;; If this function was defined using DEFUN, then this is the name of the
  ;; function, a symbol or (SETF <symbol>).  Otherwise, this is some string
  ;; that is intended to be informative.
  (name nil :type (or simple-string list symbol))
  ;;
  ;; A string representing the argument list that the function was defined
  ;; with.
  (arguments nil :type simple-string)
  ;;
  ;; A function type specifier representing the arguments and results of this
  ;; function.
  (type nil :type list))


;;; The IR2-Environment is used to annotate non-let lambdas with their passing
;;; locations.  It is stored in the Environment-Info.
;;;
(defstruct (ir2-environment
	    (:print-function %print-ir2-environment))
  ;;
  ;; A list of the argument passing TNs.  The explict arguments are first,
  ;; followed by the implict environment arguments.  In an XEP, there are no
  ;; arg TNs corresponding to any environment TNs, since the environment is
  ;; accessed from the closure.
  (arg-locs nil :type list)
  ;;
  ;; The TNs that hold the passed environment within the function.  This is an
  ;; alist translating from the NLX-Info or lambda-var to the TN that holds
  ;; the corresponding value within this function.  This list is in the same
  ;; order as the ENVIRONMENT-CLOSURE and environment passing locations in the
  ;; ARG-LOCS.
  (environment nil :type list)
  ;;
  ;; The TNs that hold the Old-Cont and Return-PC within the function.  We
  ;; always save these so that the debugger can do a backtrace, even if the
  ;; function has no return (and thus never uses them).  Null only temporarily.
  (old-cont nil :type (or tn null))
  (return-pc nil :type (or tn null))
  ;;
  ;; The passing locations for Old-Cont and Return-PC.
  (old-cont-pass nil :type tn)
  (return-pc-pass nil :type tn)
  ;;
  ;; The passing location for the pointer to any stack arguments.
  (argument-pointer nil :type tn)
  ;;
  ;; A list of all the :Environment TNs live in this environment.
  (live-tns nil :type list)
  ;;
  ;; A list of all the keep-around TNs live in this environment.
  (keep-around-tns nil :type list)
  ;;
  ;; A list of all the IR2-Blocks in this environment, threaded by
  ;; IR2-Block-Environment-Next.  This is filled in by control analysis.
  (blocks nil :type (or ir2-block null))
  ;;
  ;; A label that marks the start of elsewhere code for this function.  Null
  ;; until this label is assigned by codegen.  Used for maintaining the debug
  ;; source map.
  (elsewhere-start nil :type (or label null))
  ;;
  ;; A label that marks the first location in this function at which the
  ;; environment is properly initialized, i.e. arguments moved from their
  ;; passing locations, etc.  This is the start of the function as far as the
  ;; debugger is concerned.
  (environment-start nil :type (or label null)))

(defprinter ir2-environment
  arg-locs
  environment
  old-cont
  old-cont-pass
  return-pc
  return-pc-pass
  argument-pointer)


;;; The Return-Info structure is used by GTN to represent the return strategy
;;; and locations for all the functions in a given Tail-Set.  It is stored in
;;; the Tail-Set-Info.
;;;
(defstruct (return-info
	    (:print-function %print-return-info))
  ;;
  ;; The return convention used:
  ;; -- If :Unknown, we use the standard return convention.
  ;; -- If :Fixed, we use the known-values convention.
  (kind nil :type (member :fixed :unknown))
  ;;
  ;; The number of values returned, or :Unknown if we don't know.  Count may be
  ;; known when Kind is :Unknown, since we may choose the standard return
  ;; convention for other reasons.
  (count nil :type (or unsigned-byte (member :unknown)))
  ;;
  ;; If count isn't :Unknown, then this is a list of the primitive-types of
  ;; each value.
  (types () :type list)
  ;;
  ;; If kind is :Fixed, then this is the list of the TNs that we return the
  ;; values in. 
  (locations () :type list))


(defprinter return-info
  kind
  count
  types
  locations)


(defstruct (ir2-nlx-info (:print-function %print-ir2-nlx-info))
  ;;
  ;; If the kind is :Entry (a lexical exit), then in the home environment, this
  ;; holds a Value-Cell object containing the unwind block pointer.  In the
  ;; other cases nobody directly references the unwind-block, so we leave this
  ;; slot null.
  (home nil :type (or tn null))
  ;;
  ;; The saved control stack pointer.
  (save-sp nil :type tn)
  ;;
  ;; The list of dynamic state save TNs.
  (dynamic-state (make-dynamic-state-tns) :type list)
  ;;
  ;; The target label for NLX entry.
  (target (gen-label) :type label))


(defprinter ir2-nlx-info
  home
  save-sp
  dynamic-state)


#|
;;; The Loop structure holds information about a loop.
;;;
(defstruct (cloop (:print-function %print-loop)
		  (:conc-name loop-)
		  (:predicate loop-p)
		  (:constructor make-loop)
		  (:copier copy-loop))
  ;;
  ;; The kind of loop that this is.  These values are legal:
  ;;
  ;;    :Outer
  ;;        This is the outermost loop structure, and represents all the
  ;;        code in a component.
  ;;
  ;;    :Natural
  ;;        A normal loop with only one entry.
  ;;
  ;;    :Strange
  ;;        A segment of a "strange loop" in a non-reducible flow graph.
  ;;
  (kind nil :type (member :outer :natural :strange))
  ;;
  ;; The first and last blocks in the loop.  There may be more than one tail,
  ;; since there may be multiple back branches to the same head.
  (head nil :type (or cblock null))
  (tail nil :type list)
  ;;
  ;; A list of all the blocks in this loop or its inferiors that have a
  ;; successor outside of the loop.
  (exits nil :type list)
  ;;
  ;; The loop that this loop is nested within.  This is null in the outermost
  ;; loop structure.
  (superior nil :type (or cloop null))
  ;;
  ;; A list of the loops nested directly within this one.
  (inferiors nil :type list)
  ;;
  ;; The head of the list of blocks directly within this loop.  We must recurse
  ;; on Inferiors to find all the blocks.
  (blocks nil :type (or null cblock)))

(defprinter loop
  kind
  head
  tail
  exits)
|#


;;;; VOPs and Templates:

;;; A VOP is a Virtual Operation.  It represents an operation and the operands
;;; to the operation.
;;;
(defstruct (vop (:print-function %print-vop)
		(:constructor make-vop (block node info args results)))
  ;;
  ;; VOP-Info structure containing static info about the operation.
  (info nil :type (or vop-info null))
  ;;
  ;; The IR2-Block this VOP is in.
  (block nil :type ir2-block)
  ;;
  ;; VOPs evaluated after and before this one.  Null at the beginning/end of
  ;; the block, and temporarily during IR2 translation.
  (next nil :type (or vop null))
  (prev nil :type (or vop null))
  ;;
  ;; Heads of the TN-Ref lists for operand TNs, linked using the Across slot.
  (args nil :type (or tn-ref null))  
  (results nil :type (or tn-ref null))
  ;;
  ;; Head of the list of write refs for each explicitly allocated temporary,
  ;; linked together using the Across slot.
  (temps nil :type (or tn-ref null))
  ;;
  ;; Head of the list of all TN-refs for references in this VOP, linked by the
  ;; Next-Ref slot.  There will be one entry for each operand and two (a read
  ;; and a write) for each temporary.
  (refs nil :type (or tn-ref null))
  ;;
  ;; Stuff that is passed uninterpreted from IR2 conversion to codegen.  The
  ;; meaning of this slot is totally dependent on the VOP.
  codegen-info
  ;;
  ;; Node that generated this VOP, for keeping track of debug info.
  (node nil :type (or node null))
  ;;
  ;; Local-TN bit vector representing the set of TNs live after args are read
  ;; and before results are written.  This is only filled in when
  ;; VOP-INFO-SAVE-P is non-null.
  (save-set nil :type (or local-tn-bit-vector null)))

(defprinter vop
  (info :prin1 (vop-info-name info))
  args
  results
  (codegen-info :test codegen-info))


;;; The TN-Ref structure contains information about a particular reference to a
;;; TN.  The information in the TN-Refs largely determines how TNs are packed.
;;; 
(defstruct (tn-ref (:print-function %print-tn-ref)
		   (:constructor make-tn-ref (tn write-p)))
  ;;
  ;; The TN referenced.
  (tn nil :type tn)
  ;;
  ;; True if this is a write reference, false if a read.
  (write-p nil :type boolean)
  ;;
  ;; Thread running through all TN-Refs for this TN of the same kind (read or
  ;; write).
  (next nil :type (or tn-ref null))
  ;;
  ;; The VOP where the reference happens.  The this is null only temporarily.
  (vop nil :type (or vop null))
  ;;
  ;; Thread running through all TN-Refs in VOP, in reverse order of reference.
  (next-ref nil :type (or tn-ref null))
  ;;
  ;; Thread the TN-Refs in VOP of the same kind (argument, result, temp).
  (across nil :type (or tn-ref null))
  ;;
  ;; If true, this is a TN-Ref also in VOP whose TN we would like packed in the
  ;; same location as our TN.  Read and write refs are always paired: Target in
  ;; the read points to the write, and vice-versa.
  (target nil :type (or null tn-ref)))

(defprinter tn-ref
  tn
  write-p
  (vop :test vop :prin1 (vop-info-name (vop-info vop))))


;;; The Template represents a particular IR2 coding strategy for a known
;;; function.
;;;
(defstruct (template
	    (:print-function %print-template))
  ;;
  ;; The symbol name of this VOP.  This is used when printing the VOP and is
  ;; also used to provide a handle for definition and translation.
  (name nil :type symbol)
  ;;
  ;; A Function-Type describing the arg/result type restrictions.  We compute
  ;; this from the Primitive-Type restrictions to make life easier for IR1
  ;; phases that need to anticipate LTN's template selection.
  (type nil :type function-type)
  ;;
  ;; Lists of the primitive types for the fixed arguments and results.  A list
  ;; element may be *, indicating no restriction on that particular argument or
  ;; result.
  ;;
  ;; If Result-Types is :Conditional, then this is an IF-xxx style conditional
  ;; that yeilds its result as a control transfer.  The emit function takes some
  ;; kind of additional arguments describing where to go to in the true and
  ;; false cases.
  (arg-types nil :type list)
  (result-types nil :type (or list (member :conditional)))
  ;;
  ;; The primitive type restriction applied to each extra argument or result
  ;; following the fixed operands.  If *, then there is no restriction.  If
  ;; null, then extra operands are not allowed.
  (more-args-type nil :type (or (member nil *) primitive-type))
  (more-results-type nil :type (or (member nil *) primitive-type))
  ;;
  ;; If true, this is a function that is called with no arguments to see if
  ;; this template can be emitted.  This is used to conditionally compile for
  ;; different target hardware configuarations (e.g. FP hardware.)
  (guard nil :type (or function null))
  ;;
  ;; The policy under which this template is the best translation.  Note that
  ;; LTN might use this template under other policies if it can't figure our
  ;; anything better to do.
  (policy nil :type policies)
  ;;
  ;; The base cost for this template, given optimistic assumptions such as no
  ;; operand loading, etc.
  (cost nil :type unsigned-byte)
  ;;
  ;; If true, then a short noun-like phrase describing what this VOP "does",
  ;; i.e. the implementation strategy.  This is for use in efficiency notes.
  (note nil :type (or string null))
  ;;
  ;; The number of trailing arguments to VOP or %Primitive that we bundle into
  ;; a list and pass into the emit function.  This provides a way to pass
  ;; uninterpreted stuff directly to the code generator.
  (info-arg-count 0 :type unsigned-byte)
  ;;
  ;; A function that emits the VOPs for this template.  Arguments:
  ;;  1] Node for source context.
  ;;  2] IR2-Block that we place the VOP in.
  ;;  3] This structure.
  ;;  4] Head of argument TN-Ref list.
  ;;  5] Head of result TN-Ref list.
  ;;  6] If Info-Arg-Count is non-zero, then a list of the magic arguments.
  ;;
  ;; Two values are returned: the first and last VOP emitted.  This vop
  ;; sequence must be linked into the VOP Next/Prev chain for the block.  At
  ;; least one VOP is always emitted.
  (emit-function nil :type function))

(defprinter template
  name
  (arg-types :prin1 (mapcar #'primitive-type-name arg-types))
  (result-types :prin1 (if (listp result-types)
			   (mapcar #'primitive-type-name result-types)
			   result-types))
  (more-args-type :test more-args-type
		  :prin1 (primitive-type-name more-args-type))
  (more-results-type :test more-results-type
		     :prin1 (primitive-type-name more-results-type))
  policy
  cost
  (note :test note)
  (info-arg-count :test (not (zerop info-arg-count))))


;;; The VOP-Info structure holds the constant information for a given virtual
;;; operation.  We include Template so functions with a direct VOP equivalent
;;; can be translated easily.
;;;
(defstruct (vop-info
	    (:include template)
	    (:print-function %print-template))
  ;;
  ;; Side-effects of this VOP and side-effects that affect the value of this
  ;; VOP.
  (effects nil :type attributes)
  (affected nil :type attributes)
  ;;
  ;; If true, causes special casing of TNs live after this VOP that aren't
  ;; results:
  ;; -- If T, all such TNs that are allocated in a SC with a defined save-sc
  ;;    will be saved in a TN in the save SC before the VOP and restored after
  ;;    the VOP.  This is used by call VOPs.  A bit vector representing the
  ;;    live TNs is stored in the VOP-SAVE-SET.
  ;; -- If :Force-To-Stack, all such TNs will made into :Environment TNs and
  ;;    forced to be allocated in SCs without any save-sc.  This is used by NLX
  ;;    entry vops.
  ;; -- If :Compute-Only, just compute the save set, don't do any saving.  This
  ;;    is used to get the live variables for debug info.
  ;;
  (save-p nil :type (member t nil :force-to-stack :compute-only))
  ;;
  ;; A list of sc-vectors representing the loading costs of each fixed argument
  ;; and result.
  (arg-costs nil :type list)
  (result-costs nil :type list)
  ;;
  ;; If true, sc-vectors representing the loading costs for any more args and
  ;; results.
  (more-arg-costs nil :type (or sc-vector null))
  (more-result-costs nil :type (or sc-vector null))
  ;;
  ;; Lists of sc-bit-vectors representing the SC restrictions on each fixed
  ;; argument and result.
  (arg-restrictions nil :type list)
  (result-restrictions nil :type list)
  ;;
  ;; If true, a function that is called with the VOP to do operand targeting.
  ;; This is done by modifiying the TN-Ref-Target slots in the TN-Refs so that
  ;; they point to other TN-Refs in the same VOP.
  (target-function nil :type (or null function))
  ;;
  ;; A function that emits assembly code for a use of this VOP when it is
  ;; called with the VOP structure.  Null if this VOP has no specified
  ;; generator (i.e. it exists only to be inherited by other VOPs.)
  (generator-function nil :type (or function null))
  ;;
  ;; A list of things that are used to parameterize an inherited generator.
  ;; This allows the same generator function to be used for a group of VOPs
  ;; with similar implementations.
  (variant nil :type list))


;;;; SBs and SCs:

(eval-when (#-new-compiler compile load eval)

;;; The SB structure represents the global information associated with a
;;; storage base.
;;;
(defstruct (sb (:print-function %print-sb))
  ;;
  ;; Name, for printing and reference.
  (name nil :type symbol)
  ;;
  ;; The kind of storage base (which determines the packing algorithm).
  (kind :non-packed :type (member :finite :unbounded :non-packed))
  ;;
  ;; The number of elements in the SB.  If finite, this is the total size.  If
  ;; unbounded, this is the size that the SB is initially allocated at.
  (size 0 :type unsigned-byte))

(defprinter sb
  name)


;;; The Finite-SB structure holds information needed by the packing algorithm
;;; for finite SBs.
;;;
(defstruct (finite-sb (:include sb)
		      (:print-function %print-sb))
  ;;
  ;;
  ;; The number of locations currently allocated in this SB.
  (current-size 0 :type unsigned-byte)
  ;;
  ;; The last location packed in, used by pack to scatter TNs to prevent a few
  ;; locations from getting all the TNs, and thus getting overcrowded, reducing
  ;; the possiblilities for targeting.
  (last-offset 0 :type unsigned-byte)
  ;;
  ;; A vector containing, for each location in this SB, a vector indexed by IR2
  ;; block numbers, holding local conflict bit vectors.  A TN must not be
  ;; packed in a given location within a particular block if the LTN number for
  ;; that TN in that block corresponds to a set bit in the bit-vector.
  (conflicts '#() :type simple-vector)
  ;;
  ;; A vector containing, for each location in this SB, a bit-vector indexed by
  ;; IR2 block numbers.  If the bit corresponding to a block is set, then the
  ;; location is in use somewhere in the block, and thus has a conflict for
  ;; always-live TNs.
  (always-live '#() :type simple-vector)
  ;;
  ;; A vector containing the TN currently live in each location in the SB, or
  ;; NIL if the location is unused.  This is used during load-tn pack.
  (live-tns '#() :type simple-vector))


;;; the SC structure holds the storage base that storage is allocated in and
;;; information used to select locations within the SB.
;;;
(defstruct (sc (:print-function %print-sc))
  ;;
  ;; Name, for printing and reference.
  (name nil :type symbol)
  ;;
  ;; The number used to index SC cost vectors.
  (number 0 :type sc-number)
  ;;
  ;; The storage base that this SC allocates storage from.
  (sb nil :type (or sb null))
  ;;
  ;; The size of elements in this SC, in units of locations in the SB.
  (element-size 0 :type unsigned-byte)
  ;;
  ;; If our SB is finite, a list of the locations in this SC.
  (locations nil :type list))

(defprinter sc
  name)

); eval-when (compile load eval)
  

;;;; TNs:

(eval-when (#-new-compiler compile load eval)

(defstruct (tn (:include sset-element)
	       (:constructor make-random-tn)
	       (:constructor make-tn (number kind primitive-type sc))
	       (:print-function %print-tn))
  ;;
  ;; The kind of TN this is:
  ;;
  ;;   :Normal
  ;;        A normal, non-constant TN, representing a variable or temporary.
  ;;        Lifetime information is computed so that packing can be done.
  ;;
  ;;   :Environment
  ;;        A TN that has hidden references (debugger or NLX), and thus must be
  ;;        allocated for the duration of the environment it is referenced in.
  ;;        All references must be in the environment that was specified to
  ;;        Make-Environment-TN.  Conflicts are represented specially.  These
  ;;        TNs never appear in the IR2-Block-XXX-TNs.  Environment TNs never
  ;;        have Local or Local-Number.
  ;;
  ;;   :Save
  ;;   :Save-Once
  ;;        A TN used for saving a :Normal TN across function calls.  The
  ;;        lifetime information slots are unitialized: get the original TN our
  ;;        of the SAVE-TN slot and use it for conflicts. Save-Once is like
  ;;        :Save, except that it is only save once at the single writer of the
  ;;        original TN.
  ;;
  ;;   :Load
  ;;        A load-TN used to compute an argument or result that is restricted
  ;;        to some finite SB.  Load TNs don't have any conflict information.
  ;;        Load TN pack uses a special local conflict determination method.
  ;;
  ;;   :Constant
  ;;        Represents a constant, with TN-Leaf a Constant leaf.  Lifetime
  ;;        information isn't computed, since the value isn't allocated by
  ;;        pack, but is instead generated as a load at each use.  Since
  ;;        lifetime analysis isn't done on :Constant TNs, they don't have 
  ;;        Local-Numbers and similar stuff.
  ;;
  ;;   :Cached-Constant
  ;;        Represents a constant for which caching in a register would be
  ;;        desirable.  Lifetime information is computed so that the cached
  ;;        copies can be allocated.
  ;;
  (kind nil :type (member :normal :environment :save :save-once :load :constant
			  :cached-constant))
  ;;
  ;; The primitive-type for this TN's value.  Since the allocation costs for
  ;; VOP temporaries are explicitly specified, this slot is null in such TNs.
  (primitive-type nil :type (or primitive-type null))
  ;;
  ;; If this TN represents a variable or constant, then this is the
  ;; corresponding Leaf.
  (leaf nil :type (or leaf null))
  ;;
  ;; Thread that links TNs together so that we can find them.
  (next nil :type (or tn null))
  ;;
  ;; Head of TN-Ref lists for reads and writes of this TN.
  (reads nil :type (or tn-ref null))
  (writes nil :type (or tn-ref null))
  ;;
  ;; A link we use when building various temporary TN lists.
  (next* nil :type (or tn null))
  ;;
  ;; Some block that contains a reference to this TN, or Nil if we haven't seen
  ;; any reference yet.  If the TN is local, then this is the block it is local
  ;; to.
  (local nil :type (or ir2-block null))
  ;;
  ;; If a local TN, the block relative number for this TN.  Global TNs whose
  ;; liveness changes within a block are also assigned a local number during
  ;; the conflicts analysis of that block.  If the TN has no local number
  ;; within the block, then this is Nil.
  (local-number nil :type (or local-tn-number null))
  ;;
  ;; If a local TN, a bit-vector with 1 for the local-number of every TN that
  ;; we conflict with.
  (local-conflicts (make-array local-tn-limit :element-type 'bit
			       :initial-element 0)
		   :type local-tn-bit-vector)
  ;;
  ;; Head of the list of Global-Conflicts structures for a global TN.  This
  ;; list is sorted by block number (i.e. reverse DFO), allowing the
  ;; intersection between the lifetimes for two global TNs to be easily found.
  ;; If null, then this TN is a local TN.
  (global-conflicts nil :type (or global-conflicts null))
  ;;
  ;; During lifetime analysis, this is used as a pointer into the conflicts
  ;; chain, for scanning through blocks in reverse DFO.
  (current-conflict nil)
  ;;
  ;; In a :Save TN, this is the TN saved.  In a :Normal TN, this is the
  ;; associated save TN.  In TNs with no save TN, this is null.
  (save-tn nil :type (or tn null))
  ;;
  ;; This is a vector indexed by SC numbers with the cost for packing in that
  ;; SC.  If an entry for an SC is null, then it is not possible to pack in
  ;; that SC, either because it is illegal or because the SC is full.
  (costs (make-array sc-number-limit :initial-element nil)
	 :type sc-vector)
  ;;
  ;; The SC packed into, or NIL if not packed.
  (sc nil :type (or sc null))
  ;;
  ;; The offset within the SB that this TN is packed into.  This is what
  ;; indicates that the TN is packed.
  (offset nil :type (or unsigned-byte null)))

); Eval-When (Compile Load Eval)

(defun %print-tn (s stream d)
  (declare (ignore d))
  (write-string "#<TN " stream)
  (print-tn s stream)
  (write-char #\> stream))

#|
(defprinter tn
  (number :test (/= number 0) :prin1 (tn-id structure))
  kind
  (primitive-type :test primitive-type
		  :prin1 (primitive-type-name primitive-type))
  (leaf :test leaf)
  (sc :test sc :prin1 (sc-name sc))
  (offset :test offset))
|#

;;; The Global-Conflicts structure represents the conflicts for global TNs.
;;; Each global TN has a list of these structures, one for each block that it
;;; is live in.  In addition to repsenting the result of lifetime analysis, the
;;; global conflicts structure is used during lifetime analysis to represent
;;; the set of TNs live at the start of the IR2 block.
;;;
(defstruct (global-conflicts
	    (:constructor make-global-conflicts (kind tn block number))
	    (:print-function %print-global-conflicts))

  ;;
  ;; The IR2-Block that this structure represents the conflicts for.
  (block nil :type ir2-block)
  ;;
  ;; Thread running through all the Global-Conflict for Block.  This
  ;; thread is sorted by TN number.
  (next nil :type (or global-conflicts null))
  ;;
  ;; The way that TN is used by Block:
  ;;
  ;;    :Read
  ;;        The TN is read before it is written.  It starts the block live, but
  ;;        is written within the block.
  ;;
  ;;    :Write
  ;;        The TN is written before any read.  It starts the block dead, and
  ;;        need not have a read within the block.
  ;;
  ;;    :Read-Only
  ;;        The TN is read, but never written.  It starts the block live, and
  ;;        is not killed by the block.  Lifetime analysis will promote
  ;;        :Read-Only TNs to :Live if they are live at the block end.
  ;;
  ;;    :Live
  ;;        The TN is not referenced.  It is live everywhere in the block.
  ;;
  (kind :read-only :type (member :read :write :read-only :live))
  ;;
  ;; A local conflicts vector representing conflicts with TNs live in Block.
  ;; The index for the local TN number of each TN we conflict with in this
  ;; block is 1.  To find the full conflict set, the :Live TNs for Block must
  ;; also be included.  This slot is not meaningful when Kind is :Live. 
  (conflicts (make-array local-tn-limit
			 :element-type 'bit
			 :initial-element 0)
	     :type local-tn-bit-vector)
  ;;
  ;; The TN we are recording conflicts for.
  (tn nil :type tn)
  ;;
  ;; Thread through all the Global-Conflicts for TN.
  (tn-next nil :type (or global-conflicts null))
  ;;
  ;; TN's local TN number in Block.  :Live TNs don't have local numbers. 
  (number nil :type (or local-tn-number null)))

(defprinter global-conflicts
  tn
  block
  kind
  (number :test number))
