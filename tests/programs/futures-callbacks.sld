(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell future))

;; Every waker runs, in the order registered, and a ready future calls
;; its waker at once.
(define (main) (→ Unit) (! host mut output-port completion)
  (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
    ((Pair promise future)
     (on-ready future (lambda () (write-line "first waker runs")))
     (on-ready future (lambda () (write-line "second waker runs")))
     (write-line "fulfilling")
     (fulfill promise 42)
     (on-ready future (lambda () (write-line "a ready future wakes at once")))))
  (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
    ((Pair promise future)
     (on-ready future (lambda () (write-line "never woken")))))
  (write-line "done")
  (unit))
