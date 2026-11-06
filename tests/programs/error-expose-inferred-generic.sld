(import
 (snail core base))

;; An inferred host entry closes its effects, not its unknown value types.
(define (identity value) value)
(expose identity "identity")
