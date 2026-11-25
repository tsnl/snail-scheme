(import
 (snail core base))

(record Box
  ((n I64)))

;; `set!` writes a field where it is written; it is not a function to pass.
(define (main) (→ Unit)
  (let ((b (new Box (n 1)))
        (w set!))
    (w (● b n) 2)
    (unit)))
