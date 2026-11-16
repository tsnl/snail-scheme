(import
 (snail core base)
 (snail core io))

;; A `set!` writes a record field; a local variable is not a place.
(define (main) (→ Unit) (! mut)
  (let ((x 1))
    (set! x 2)
    (unit)))
