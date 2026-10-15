(import (snail strict))
(define (sum n result)
  (if (= n 0) result (sum (- n 1) (+ result n))))
(sum 100000 0)
