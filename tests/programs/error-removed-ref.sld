(import
 (snail core base))

;; The old shareable heap cell had a value constructor named Ref.
(define (heap-cell (value I64)) (→ (Ref I64)) (Ref value))
