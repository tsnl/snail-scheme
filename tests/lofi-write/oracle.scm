(import (chezscheme))

;; ---- Independent native Scheme graphs use the same observable storage ----

(define (output-line value) (write value) (newline))
(let ((pair (list 'a)))
  (output-line (vector pair pair))
  (set-cdr! pair pair) (output-line pair)
  (set-car! pair pair) (output-line pair)
  ;; Strict cyclic display deliberately uses finite graph notation. Chez's
  ;; display diverges here, so its write supplies the structural oracle only.
  (output-line pair))
(let ((value (vector 'a #f)))
  (vector-set! value 1 value) (output-line value))
(let* ((pair (list 'a)) (text (string-copy "s")) (bytes (u8-list->bytevector '(1 2)))
       (value (vector pair pair text text bytes bytes #f)))
  (vector-set! value 6 value)
  (output-line value) (output-line value))
(let* ((tail (list 'b 'c)) (value (vector (cons 'a tail) tail #f)))
  (vector-set! value 2 value) (output-line value))
