;; Matched callers for Rust and llvmlite implementations of checked fixnum add.
;; This probe's i64 result/status ABI deliberately avoids choosing a boxed layout.
(import (scheme base) (prefix (snail-scheme llvmlite) ir:))

;; ---- Function references ----

(define (kernel name)
  (ir:function name ir:i64 (list (cons ir:i32 "a") (cons ir:i32 "b"))))

(define (word n) (ir:integer ir:i32 n))
(define (wide n) (ir:integer ir:i64 n))

(define (caller name callee)
  (let* ((f (kernel name)) (entry (ir:block f "entry"))
         (result (ir:local f ir:i64 "result")))
    (ir:define-function
     f 'external '(noinline)
     (list (ir:block-body entry
                          (list (ir:call result callee (list (ir:parameter f 0) (ir:parameter f 1))))
                          (ir:ret result))))))

;; ---- Checked addition ----

(define (decode word extended shifted decoded)
  (list (ir:zext extended word)
        (ir:binop shifted 'shl extended (wide 32))
        (ir:binop decoded 'ashr shifted (wide 33))))

(define (llvm-add f)
  (let* ((entry (ir:block f "entry")) (add (ir:block f "add"))
         (success (ir:block f "success")) (fail (ir:block f "fail"))
         (a (ir:parameter f 0)) (b (ir:parameter f 1))
         (tags (ir:local f ir:i32 "tags")) (tag (ir:local f ir:i32 "tag"))
         (valid (ir:local f ir:i1 "valid"))
         (ax (ir:local f ir:i64 "ax")) (as (ir:local f ir:i64 "as"))
         (av (ir:local f ir:i64 "av")) (bx (ir:local f ir:i64 "bx"))
         (bs (ir:local f ir:i64 "bs")) (bv (ir:local f ir:i64 "bv"))
         (sum (ir:local f ir:i64 "sum")) (lower (ir:local f ir:i1 "lower"))
         (upper (ir:local f ir:i1 "upper")) (fits (ir:local f ir:i1 "fits")))
    (ir:define-function
     f 'internal '()
     (list
      (ir:block-body entry
                     (list (ir:binop tags 'and a b) (ir:binop tag 'and tags (word 1))
                           (ir:icmp valid 'eq tag (word 1))) (ir:cbr valid add fail))
      (ir:block-body add
                     (append (decode a ax as av) (decode b bx bs bv)
                             (list (ir:binop sum 'add av bv)
                                   (ir:icmp lower 'sge sum (wide -1073741824))
                                   (ir:icmp upper 'sle sum (wide 1073741823))
                                   (ir:binop fits 'and lower upper))) (ir:cbr fits success fail))
      (ir:block-body success '() (ir:ret sum))
      (ir:block-body fail '() (ir:ret (wide (- (expt 2 63)))))))))

;; ---- Module emission ----

(let ((rust (kernel "probe_rust_add")) (llvm (kernel "probe_llvm_add")))
  (ir:write-module
   (ir:module (list (ir:declare rust) (llvm-add llvm)
                    (caller "probe_via_rust" rust) (caller "probe_via_llvm" llvm)))
   (current-output-port)))
