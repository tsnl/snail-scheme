;; Each spawned instance initializes this state once. Exports are its methods.
(define-library (examples counter)
  (export add value echo)
  (import (scheme base))
  (begin
    (define count 0)
    (define (add amount)
      (set! count (+ count amount))
      count)
    (define (value) count)
    (define (echo datum) datum)))
