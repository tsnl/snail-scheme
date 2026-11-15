(import
 (snail core base))

;; Reject the library definition even if it is never instantiated.
(define (memoize (f (Fn I64 → I64 ! E))) (→ (Fn I64 → I64 ! E)) (∀ (E))
  (cache f))
(define (main) (→ Unit) (unit))
