(import
 (snail core base))

(struct Counter
  ((value I64)))
(define counter (→ Counter) (Counter 0))
(define (next) (→ I64) (! mut)
  (set! (● counter value) (+ 1 (● counter value)))
  (● counter value))
(expose next "next")
