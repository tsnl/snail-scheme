(import
 (snail core base))

(define (repeated (function (Fn I64 → I64)))
      (→ I64)
      (function (function 1)))

(repeated (once (lambda (value) (+ value 1))))
