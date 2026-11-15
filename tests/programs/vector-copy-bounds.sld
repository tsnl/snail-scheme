(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! mut output-port)
  (let ((items (make-vector 1 1)))
    (write-line "before")
    (vector-copy! items 1 items 0 1)))
