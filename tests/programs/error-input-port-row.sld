(import
 (snail core base)
 (snail core io))

(define (prompt) (→ (Option Char)) (! output-port)
  (write-string "> ")
  (read-char))
