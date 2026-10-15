(import (snail strict))

;; Literal payload knowledge must not initialize the source binding early.
(define (read-later) later)
(define early (read-later))
(define later 42)
early
