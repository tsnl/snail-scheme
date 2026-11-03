(import
 (snail core base)
 (snail core io))

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
                (: add-here (-> I64 I64 I64))
                (define (add-here a b) (generic a b)))

(with-instances (description)
                (display (generic (ann 2 I64) (ann 3 I64)))
                (newline)
                (display (add-here 2 3))
                (newline))

(display (with-instances (addition) (generic (ann 7 I64) (ann 8 I64))))
(newline)
