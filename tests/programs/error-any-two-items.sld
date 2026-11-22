(import
 (snail core base)
 (snail core io))

;; Each definition that boxes a function performing effects is reported,
;; in source order: one walk after checking finds every item's first
;; failure.
(define (noisy (out OutputPort)) (→ Unit) (! mut) (write-line out "noisy"))

(define (first-box) (→ Any) (Any noisy))

(define (second-box) (→ Any) (Any noisy))

(define (main) (→ Unit)
  (first-box)
  (second-box)
  (unit))
