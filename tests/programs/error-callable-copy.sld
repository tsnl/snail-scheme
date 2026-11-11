(import
 (snail core base))

(define (duplicate (function F)) (→ (Pair F F)) (∀ F) (⊨ (Fn F I64 → I64))
  (Pair function function))
