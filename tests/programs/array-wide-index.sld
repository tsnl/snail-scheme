(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (write-line "before")
  (write (array-ref (make-array 1 1) 4294967296)))
