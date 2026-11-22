(import
 (snail core base)
 (snail core io))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let ((items (make-array 1 1)))
    (write-line out "before")
    (array-copy! mut items 1 items 0 1)))
