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
(define (location) (→ Loc) (new Loc (file "reference-counting-benchmark") (line 0) (column 0)))
(define (scalar) (→ Type) (TCon "I64" (Nil)))
(define (counted) (→ Type) (TCon "Rc" (list (scalar))))
(define (declarations)
  (→ Declarations)
  (new Declarations
    (program (empty-program))
    (owner (None))
    (control (Nil))
    (bindings (empty-table))))

(define (nested (depth I64)) (→ Expr)
  (if (= depth 0) (new Expr (term (Lit (DInt 0))) (type (scalar)) (loc (location)))
      (new Expr (term (Let (string-append "owner." (i64->string depth))
                           (new Expr
                             (term (Var "input" (Nil) (Nil)))
                             (type (counted))
                             (loc (location)))
                           (nested (- depth 1)))) (type (scalar)) (loc (location)))))

(define (source (depth I64)) (→ Item)
  (Define "benchmark"
    (new Expr (term (Lambda (list "input") (nested depth)))
         (type (TFun (list (counted)) (scalar) (empty-row))) (loc (location)))))

(define (nodes (value Expr)) (→ I64)
  (+ 1 (fold-left (lambda (total child) (+ total (nodes child))) 0 (expr-children value))))

(define (lowered-size (value Item)) (→ I64)
  (match (lower-reference-counting (declarations) (list value))
    ((Cons (Define _ body) (Nil)) (nodes body))
    (_ (panic "expected a definition"))))

(define (measure (depth I64) (iterations I64)) (→ I64)
  (let ((value (source depth)))
    (let loop ((left iterations) (total 0))
      (if (= left 0) total
          (loop (- left 1) (+ total (lowered-size value)))))))

(expose measure "measure")
(define (main) (→ Unit) (unit))
