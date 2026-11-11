(import
 (snail core base))

;; A lambda may capture, so it is not code alone.
(define (run (f (fn I64 → I64))) (→ I64)
  (f 1))

(define (offset (by I64)) (→ I64)
  (run (lambda (x) (+ x by))))
