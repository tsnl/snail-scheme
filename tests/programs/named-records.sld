(import
 (rename (snail core base) (Pair Duo))
 (snail core io))

(record Point
  ((x I64)
   (y I64)))

(record (Runner T)
  ((value T)
   (run (Fn T → I64))))

(record Work
  ((label String)
   (job (Fn → Unit))))

(record Empty
  ())

(define (marked (out OutputPort) (label String) (value I64)) (→ I64)
  (write-line out label)
  value)

;; The expected result constrains a callback before its body is checked.
(define (runner) (→ (Runner Point))
  (new Runner
    (run (lambda (point) (● point x)))
    (value (new Point (y 2) (x 42)))))

;; The later field can also establish the generic callback's receiver.
(define (inferred) (→ I64)
  (let ((value (new Runner
                 (run (lambda (point) (● point y)))
                 (value (new Point (x 7) (y 8))))))
    ((● value run) (● value value))))

(define-syntax at-origin
  (syntax-rules ()
    ((_) (new Point (y 0) (x 0)))))

(define (main (out OutputPort)) (→ Unit)
  (let ((point (new Point (y (marked out "y first" 20)) (x (marked out "x second" 10)))))
    (write-line out (i64->string (● point x)))
    (write-line out (i64->string (● point y))))
  (let ((value (runner))) (write-line out (i64->string ((● value run) (● value value)))))
  (write-line out (i64->string (inferred)))
  (write-line out (● (new Duo (second 1) (first "renamed")) first))
  (write-line out (i64->string (● (at-origin) x)))
  (match (new Empty) ((Empty) (write-line out "empty")))
  (match (new Work
           (job (lambda () (write-line out "ran the job")))
           (label "work"))
    ((Work label job) (write-line out label) (job))))
