(import
 (snail core base)
 (snail core io))

(define (prompt) (→ (Option Char)) (! mut)
  (write-string "> ")
  (read-char))
