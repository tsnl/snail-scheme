(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit)
  (write-line out "before")
  (write out (array-ref (make-array 1 1) 4294967296)))
