(import
 (snail core base))

(define (stash (v T)) (→ Any) (∀ (T)) (Any v))
(define (bad (x (Ref I64))) (→ Any) (stash (ref x)))
(define (main) (→ Unit) (unit))
