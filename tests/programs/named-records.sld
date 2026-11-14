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
   (job (FnOnce → Unit ! output-port))))

(record Empty
  ())

(define (marked (label String) (value I64)) (→ I64) (! output-port)
  (write-line label)
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

(define (main) (→ Unit) (! output-port)
  (let ((point (new Point (y (marked "y first" 20)) (x (marked "x second" 10)))))
    (write-line (i64->string (● point x)))
    (write-line (i64->string (● point y))))
  (let ((value (runner))) (write-line (i64->string ((● value run) (● value value)))))
  (write-line (i64->string (inferred)))
  (write-line (● (new Duo (second 1) (first "renamed")) first))
  (write-line (i64->string (● (at-origin) x)))
  (match (new Empty) ((Empty) (write-line "empty")))
  (match (new Work
           (job (once (lambda () (write-line "ran once"))))
           (label "linear"))
    ((Work label job) (write-line label) (call-once job))))
