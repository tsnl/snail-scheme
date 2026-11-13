(import
 (snail core base)
 (snail core table)
 (snail shell compiler read)
 (snail shell compiler core)
 (snail shell compiler specialize)
 (snail shell compiler reference-counting))

;; Exercise concrete lowering with nested owners leaving at the same result.
;; Timed work includes input construction and counting output nodes, but no
;; parsing, checking, specialization or Wasm emission.
(define (location) (→ Loc) (Loc "reference-counting-benchmark" 0 0))
(define (scalar) (→ Type) (TCon "I64" (Nil)))
(define (counted) (→ Type) (TCon "Rc" (list (scalar))))
(define (declarations) (→ Declarations) (Declarations (empty-program) (None) (Nil) (empty-table)))

(define (nested (depth I64)) (→ Expr)
  (if (= depth 0) (Expr (Lit (DInt 0)) (scalar) (location))
      (Expr (Let (string-append "owner." (i64->string depth))
                 (Expr (Var "input" (Nil) (Nil)) (counted) (location))
                 (nested (- depth 1))) (scalar) (location))))

(define (source (depth I64)) (→ Item)
  (Define "benchmark"
    (Expr (Lambda (list "input") (nested depth))
          (TFun (list (counted)) (scalar) (empty-row)) (location))))

(define (nodes (value Expr)) (→ I64)
  (+ 1 (fold-left (lambda (total child) (+ total (nodes child))) 0 (expr-children value))))

(define (lowered-size (value Item)) (→ I64)
  (match (lower-reference-counting (declarations) value)
    ((Define _ body) (nodes body))
    (_ (panic "expected a definition"))))

(define (measure (depth I64) (iterations I64)) (→ I64)
  (let ((value (source depth)))
    (let loop ((left iterations) (total 0))
      (if (= left 0) total
          (loop (- left 1) (+ total (lowered-size value)))))))

(expose measure "measure")
(define (main) (→ Unit) (unit))
