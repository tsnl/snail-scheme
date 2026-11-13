(import
 (snail core base)
 (snail core io))

(enum Choice
  (Left ((value I64)))
  (Right ((value I64))))

(define (main) (→ Unit) (! mut output-port)
  ;; Both operands run before the case check, even with identical layouts.
  (Left-value-set! (Right 3) (begin (write-line "incoming") 4)))
