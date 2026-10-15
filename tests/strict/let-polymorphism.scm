(import (snail strict))
(let ((identity (lambda (x) x)))
  (if (identity #t) (+ (identity 40) (identity 2)) 0))
