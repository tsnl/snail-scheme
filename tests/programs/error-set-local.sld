(import
 (snail core base)
 (snail core io))

;; A `set!` writes a record field; a local variable is not a place.
(define (main (mut Mut)) (→ Unit)
  (let ((x 1))
    (set! mut x 2)
    (unit)))
