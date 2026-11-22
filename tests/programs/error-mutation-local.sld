(import
 (snail core base))

(record Counter
  ((value I64)))

;; A write to an object this function just made still takes a Mut.
(define (build) (→ Counter)
  (let ((counter (new Counter (value 0))))
    (set! mut (● counter value) 1)
    counter))
