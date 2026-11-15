(import
 (snail core base)
 (snail core io))

(define (prompt) (→ (Option Char)) (! Input-port)
  (write-string "> ")
  (read-char))
