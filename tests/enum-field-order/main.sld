(import
 (snail core base)
 (snail core io))
(enum Shape (Circle ((radius I64))) (Empty))
(define (main) (→ Unit) (! mut output-port)
  (Circle-radius-set! (Empty) (begin (write-line "incoming") 1)))
