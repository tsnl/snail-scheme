(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (let ((items (make-array 1 1)))
    (write-line out "before")
    (array-copy! items 1 items 0 1)))
