(import
 (snail core base))
(define (read-x (record T)) (→ I64) (∀ T) (⊨ (::x T I64))
  (● record x))
