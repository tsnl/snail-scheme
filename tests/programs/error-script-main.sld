(import
 (snail core base)
 (snail core io))

(write-line "a statement")

(define (main) (→ Unit) (! output-port) (write-line "and a main"))
