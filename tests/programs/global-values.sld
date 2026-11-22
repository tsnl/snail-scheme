(import
 (snail core base)
 (snail core io)
 (sample settings))

(record Counter
  ((value I64)))

;; ANCHOR: values
;; A value's initializer runs at most once, on the first read, and every
;; read shares the result.
(define counter (new Counter (value 0)))

(define (tick) (→ I64)
  (set! (● counter value) (+ 1 (● counter value)))
  (● counter value))

;; Values are read in expression order, whatever their source order.
(define total (→ I64) (+ later later))
(define later (tick))
(define unused (→ I64) (panic "an unused initializer ran"))

;; A value may be a function: this one keeps the results of its calls.
(define square (cache (lambda ((n I64)) (→ I64) (begin (tick) (* n n)))))
;; ANCHOR_END: values

(define (identity (n I64)) (→ I64) n)
(define alias identity)

(define (main (out OutputPort)) (→ Unit)
  (write-line out (show (● counter value)))
  (write-line out (show total))
  (write-line out (show total))
  (write-line out (show (● counter value)))
  (write-line out (show (+ (square 9) (square 9))))
  (write-line out (show (● counter value)))
  (write-line out (show (alias 7)))
  (write-line out (● settings name))
  (write-line out (show port))
  (visits)
  (write-line out (show (+ (visits) (● settings visits)))))
