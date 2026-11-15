(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (let ((items (ann (array) (Array I64))))
    (write-line "before")
    (write (array-ref items 0))))
