(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit)
  (let ((items (ann (array) (Array I64))))
    (write-line out "before")
    (write out (array-ref items 0))))
