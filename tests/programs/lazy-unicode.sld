(import
 (snail core base)
 (snail shell text))

(define invalid (→ Char) (char-upcase (i32->char 55296)))

(define (main) (→ Unit)
  invalid
  (unit))
