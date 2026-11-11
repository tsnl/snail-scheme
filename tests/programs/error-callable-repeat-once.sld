(import
 (snail core base))

(define (repeated (function F)) (→ I64) (∀ F) (⊨ (Copy F) (Fn F I64 → I64))
  (function (function 1)))

(repeated (once (lambda (value) (+ value 1))))
