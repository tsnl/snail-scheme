(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (let ((items (ann (vector) (Vector I64))))
    (write-line "before")
    (write (vector-ref items 0))))
