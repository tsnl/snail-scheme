(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! mut output-port)
  (let ((items (make-array 1 1)))
    (write-line "before")
    (array-copy! items 1 items 0 1)))
