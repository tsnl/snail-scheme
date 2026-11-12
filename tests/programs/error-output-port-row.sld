(import
 (snail core base)
 (snail core io))

(define (prompt) (→ (Option Char)) (! input-port)
  (write-string "> ")
  (read-char))
