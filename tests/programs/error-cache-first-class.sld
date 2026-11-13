(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! mut output-port)
  (vector-set! (make-vector 1 0) 0 1)
  (let* ((wrap cache)
         (memo (wrap (lambda () (rc 42)))))
    (write-line (show (rc-get (memo))))
    (unit)))
