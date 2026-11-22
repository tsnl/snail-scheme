(import
 (snail core base)
 (snail core io))

(define (handlers) (→ (List (Fn I64 → I64)))
  (list (lambda (value) (+ value 1))
        (lambda (value) (* value 2))))

(define (code (value I64)) (→ I64)
  (+ value 10))

(define (consume (function (Fn I64 → I64)))
  (→ I64)
  (function 7))

(define (main (out OutputPort)) (→ Unit)

  (write-line out (repr (map (lambda (function) (function 5)) (handlers))))
  (let ((function (lambda (value) (code value))))
    (write-line out (show (function 5))))
  (write-line out (show (consume (lambda (value) (code value)))))
  ;; Procedures in a list are values like any other.
  (let ((jobs (ann (list (lambda (value) (+ value 2))
                         (lambda (value) (* value 3)))
                   (List (Fn I64 → I64)))))
    (match jobs
      ((Cons first (Cons second (Nil)))
       (write-line out (show (first 10)))
       (write-line out (show (second 10))))
      (other (panic "expected two jobs"))))
  (unit))
