(import
 (snail core base)
 (snail core io))

(typeclass (Combine A B)
  (type Output)
  (: combine (Fn A B → Output)))

(define-instance-set addition
  (instance (Combine I64 I64)
    (type Output I64)
    (define combine (lambda (a b) (+ a b)))))

(define-instance-set description
  (instance (Combine I64 I64)
    (type Output String)
    (define combine (lambda (a b) (string-append (show a) ":" (show b))))))

(define (generic (a A) (b B)) (→ (Combine.Output A B)) (∀ (A B)) (⊨ (Combine A B)) (combine a b))

(with-instances (addition)
                (define (add-here (a I64) (b I64)) (→ I64) (generic a b)))

(define main
  (lambda ()

    (with-instances (description)
                    (display (generic (ann 2 I64) (ann 3 I64)))
                    (newline)
                    (display (add-here 2 3))
                    (newline))
    (display (with-instances (addition) (generic (ann 7 I64) (ann 8 I64))))
    (newline)
    (unit)))
