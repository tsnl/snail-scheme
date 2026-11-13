(import
 (snail core base)
 (snail core io))

;; Ordinary runtime allocations have no separate constant-evaluation budget.
(define items (→ (List I64)) (iota 20000))
(define buffer (→ (Vector I64)) (make-vector 1000001 4))
(define (main) (→ Unit) (! output-port)
  (write-line (show (length items)))
  (write-line (show (vector-length buffer)))
  (write-line (show (vector-ref buffer 1000000))))
