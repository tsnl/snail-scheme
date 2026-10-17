(define-library (consumer app)
  (import (consumer left) (consumer right) (only (lofi primitive) i32-add))
  (export main)
  (begin (def main (-> I32) (lambda () (i32-add (left) (right))))))
