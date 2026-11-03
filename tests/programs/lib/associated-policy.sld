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
      (: combine (-> A B Output)))
    (define-instance-set addition
      (instance (Combine I64 I64)
        (type Output I64)
        (define (combine a b) (+ a b))))
    (define-instance-set description
      (instance (Combine I64 I64)
        (type Output String)
        (define (combine a b) (string-append (show a) ":" (show b)))))

    (: generic
       (All (A B)
            (requires (Combine A B))
            (-> A B (Combine.Output A B))))
    (define (generic a b) (combine a b))

    (with-instances (addition)
                    (: make-adder (-> I64 (-> I64 I64)))
                    (define (make-adder a) (lambda (b) (generic a b))))))
