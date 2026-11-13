(define-library (associated-policy)
  (export
   Combine
   Combine.Output
   combine
   generic
   make-adder)
  (import
   (snail core base))
  (begin
    (typeclass (Combine A B)
      (type Output)
      (declare (combine (left A) (right B)) (→ Output)))
    (instance (Combine I64 I64)
      (type Output I64)
      (define (combine (a I64) (b I64)) (→ I64)
        (+ a b)))
    (instance (Combine String String)
      (type Output String)
      (define (combine (a String) (b String)) (→ String)
        (string-append a ":" b)))

    (define (generic (a A) (b B))
      (→ (Combine.Output A B))
      (∀ (A B))
      (⊨ (Combine A B))
      (combine a b))

    (define (make-adder (a I64)) (→ (Fn I64 → I64))
      (lambda (b) (generic a b)))))
