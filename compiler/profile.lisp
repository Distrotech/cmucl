;;; -*- Package: C -*-
(in-package 'c)

(use-package "PROFILE")

(profile ir1-top-level
	 find-initial-dfo
	 find-dfo
	 local-call-analyze
	 delete-block
	 join-successor-if-possible
	 ir1-optimize-block
	 flush-dead-code
	 generate-type-checks
	 constraint-propagate
	 environment-analyze
	 gtn-analyze
	 control-analyze
	 ltn-analyze
	 stack-analyze
	 ir2-convert
	 lifetime-pre-pass
	 lifetime-flow-analysis
	 reset-current-conflict
	 lifetime-post-pass
	 delete-unreferenced-tns

;	 pack
	 compute-costs-and-target
	 pack-wired-tn
	 pack-tn
	 pack-targeting-tns
	 pack-load-tns
	 emit-saves

	 generate-code
	 fasl-dump-component
;	 check-life-consistency
;	 check-ir1-consistency
;	 check-ir2-consistency
	 )
