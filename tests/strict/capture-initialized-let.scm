(import (snail strict))

(define (make-probe start)
  (let ((value (+ start 1))
        (items (vector start (+ start 2)))
        (shared (ref start)))
    (define (advance delta)
      (ref-set! shared (+ (ref-get shared) delta))
      (+ value (+ (vector-ref items 1) (ref-get shared))))
    (lambda (delta) (advance delta))))

(define first (make-probe 10))
(define second (make-probe 20))
(+ (first 1) (+ (first 2) (second 3)))
