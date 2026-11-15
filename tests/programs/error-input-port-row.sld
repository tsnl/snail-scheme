(import
 (snail core base)
 (snail core io))

(define (prompt) (→ (Option Char)) (! Output-port)
  (write-string "> ")
  (read-char))
