(import
 (snail core base))

(enum Shape (Circle ((radius I64))) (Empty))
(define (main) (→ Unit) (Circle-radius (Circle 1)) (unit))
