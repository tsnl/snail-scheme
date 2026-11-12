(import
 (snail core base)
 (snail core io))

(define unused (→ I64) (loop))

(define (loop) (→ I64) unused)

(define (main) (→ Unit) (! output-port)
  (display 42)
  (newline)
  (unit))
