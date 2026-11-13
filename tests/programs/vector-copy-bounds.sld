(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! mut output-port)
  (let ((items (vector)))
    (vector-push! items 1)
    (write-line "before")
    (vector-copy! items 1 items 0 1)))
