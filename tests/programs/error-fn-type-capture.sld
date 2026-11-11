(import
 (snail core base))

;; A lambda may capture, so it is not code alone.
(: run (impl (Fn (fn I64 -> I64) -> I64)))
(define (run f)
  (f 1))

(: offset (impl (Fn I64 -> I64)))
(define (offset by)
  (run (lambda (x) (+ x by))))
