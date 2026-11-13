(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! mut output-port)
  (let ((items (vector)))
    (vector-push! items 1)
    (match (vector-pop! items) ((Some value) (unit)) ((None) (panic "missing element")))
    (write-line "before")
    (write (vector-ref items 0))))
