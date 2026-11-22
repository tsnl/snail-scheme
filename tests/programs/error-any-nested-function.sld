(import
 (snail core base)
 (snail core io))

;; A TypeId drops rows at every depth, so a list of functions that write
;; is refused as such a function is.
(define (noisy (out OutputPort)) (→ Unit) (! mut)
  (write-line out "noisy"))

(define (boxed) (→ Any) (Any (list noisy)))
