;; Build a module through the public LLVM API, then execute it on both targets.
(import (scheme base) (prefix (snail-scheme llvmlite) ir:))

(define (word value) (ir:integer ir:i32 value))

;; The block and value references precede every definition, including the
;; phi's backedge values. This builds a cyclic CFG without mutating a node.
(define (sum-definition function)
  (let* ((entry (ir:block function "entry")) (loop (ir:block function "loop"))
         (work (ir:block function "work")) (done (ir:block function "done"))
         (index (ir:local function ir:i32 "index")) (sum (ir:local function ir:i32 "sum"))
         (next (ir:local function ir:i32 "next")) (total (ir:local function ir:i32 "total"))
         (more (ir:local function ir:i1 "more")))
    (ir:define-function
     function 'internal '(alwaysinline)
     (list (ir:block-body entry '() (ir:br loop))
           (ir:block-body loop
                          (list (ir:phi index (list (cons (word 10) entry) (cons next work)))
                                (ir:phi sum (list (cons (word 0) entry) (cons total work)))
                                (ir:icmp more 'sgt index (word 0))) (ir:cbr more work done))
           (ir:block-body work (list (ir:binop total 'add sum index)
                                     (ir:binop next 'sub index (word 1))) (ir:br loop))
           (ir:block-body done '() (ir:ret sum))))))

(define (count-definition name value)
  (let* ((function (ir:function name ir:i32 '())) (entry (ir:block function "entry")))
    (ir:define-function function 'external '() (list (ir:block-body entry '() (ir:ret (word value)))))))

(define (fixture-program sum-function array halt invalid)
  (let* ((function (ir:function "snail_program" ir:void (list (cons ir:ptr "vm"))))
         (vm (ir:parameter function 0)) (entry (ir:block function "entry"))
         (pass (ir:block function "pass")) (fail (ir:block function "fail"))
         (sum (ir:local function ir:i32 "sum")) (offset (ir:local function ir:i32 "offset"))
         (answer (ir:local function ir:i32 "answer")))
    (ir:define-function
     function 'external '()
     (list (ir:block-body entry
                          (list (ir:call sum sum-function '()) (ir:load offset array)
                                (ir:binop answer 'add sum offset))
                          (ir:switch answer fail (list (cons (word 62) pass))))
           (ir:block-body pass (list (ir:call #f halt (list vm))) (ir:ret #f))
           (ir:block-body fail (list (ir:call #f invalid (list vm answer))) (ir:ret #f))))))

(define (llvmlite-fixture)
  (let* ((sum (ir:function "sum λ" ir:i32 '()))
         (array (ir:global-array "offset" ir:i32 (list (word 7) (word 9)) 4))
         (halt (ir:function "snail_halt" ir:void (list (cons ir:ptr "vm"))))
         (invalid (ir:function "snail_invalid_pc" ir:void
                               (list (cons ir:ptr "vm") (cons ir:i32 "pc")))))
    (ir:module (list (count-definition "snail_program_abi" 1)
                     (count-definition "snail_global_count" 0)
                     (count-definition "snail_constant_count" 0)
                     (ir:declare halt) (ir:declare invalid)
                     (ir:global-bytes "bytes" '(0 34 92 255))
                     (ir:global-bytes "empty" '()) array
                     (sum-definition sum) (fixture-program sum array halt invalid)))))

(ir:write-module (llvmlite-fixture) (current-output-port))
