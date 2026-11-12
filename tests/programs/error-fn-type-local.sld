(import
 (snail core base))

;; A local bound to a function is a closure, whatever it holds.
(define (run (f (fn I64 → I64))) (→ I64)
  (f 1))

(define (indirect) (→ I64)
  (let ((g (fn (x) → (* x 3))))
    (run g)))
