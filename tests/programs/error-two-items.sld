(import
 (snail core base))

;; Each definition that caches a function of unknown signature is
;; reported, in source order: one walk after checking finds every item's
;; first failure.
(define (first-memo (f F)) (→ F) (∀ (F)) (cache f))

(define (second-memo (f F)) (→ F) (∀ (F)) (cache f))

(define (main) (→ Unit)
  (unit))
