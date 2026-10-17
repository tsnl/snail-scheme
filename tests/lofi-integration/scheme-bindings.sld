(import (scheme base))
(define (identity x) x)
(let ((x 40)) (let* ((x (+ x 1)) (y (+ x 1))) (identity y)))
