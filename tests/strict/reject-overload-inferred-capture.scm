(import (snail strict))
(define storage (empty-vector))
(define-overload get-storage (lambda () storage))
;; A later caller must not choose this row's captured element type.
(ann (get-storage) (Vector I64))
42
