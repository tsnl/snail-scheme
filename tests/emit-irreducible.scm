;; Deliberately malformed backend control flow: two entries to the same cycle.
;; The WASI ordinary-object build must reject it before bypassing LLVM's repair.
(import (scheme base) (prefix (snail-scheme llvmlite) ir:))

(define procedure (ir:function "snail_program" ir:void (list (cons ir:ptr "vm"))))
(define probe (ir:function "opaque_probe" ir:i1 (list (cons ir:ptr "vm"))))
(define entry (ir:block procedure "entry"))
(define left (ir:block procedure "left"))
(define right (ir:block procedure "right"))
(define done (ir:block procedure "done"))
(define condition (ir:local procedure ir:i1 "condition"))
(define left-condition (ir:local procedure ir:i1 "left_condition"))
(define right-condition (ir:local procedure ir:i1 "right_condition"))

(ir:write-definition (ir:declare probe) (current-output-port))
(ir:write-definition
 (ir:define-function
  procedure 'external '()
  (list
   (ir:block-body entry (list (ir:call condition probe (list (ir:parameter procedure 0))))
                  (ir:cbr condition left right))
   (ir:block-body left (list (ir:call left-condition probe (list (ir:parameter procedure 0))))
                  (ir:cbr left-condition right done))
   (ir:block-body right (list (ir:call right-condition probe (list (ir:parameter procedure 0))))
                  (ir:cbr right-condition left done))
   (ir:block-body done '() (ir:ret #f))))
 (current-output-port))
