(define-library (associated-policy)
  (export
   Combine
   Combine.Output
   combine
   addition
   description
   generic
   make-adder)
  (import
   (snail core base))
  (begin
    (typeclass (Combine A B)
      (type Output)
      (: combine (impl (Fn A B → Output))))
    (define-instance-set addition
      (instance (Combine I64 I64)
        (type Output I64)
        (define combine (lambda (a b) (+ a b)))))
    (define-instance-set description
      (instance (Combine I64 I64)
        (type Output String)
        (define combine (lambda (a b) (string-append (show a) ":" (show b))))))

    (define (generic (a A) (b B)) (→ (Combine.Output A B)) (∀ A B) (⊨ (Combine A B)) (combine a b))

    (with-instances (addition)
                    (define (make-adder (a I64))
                      (→ (dyn (Fn I64 → I64)))
                      (lambda (b) (generic a b))))))
