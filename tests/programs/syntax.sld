(import
 (snail core base)
 (snail core io))

(define-syntax my-or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e r ...) (let ((t e)) (if t t (my-or r ...))))))

(define-syntax while
  (syntax-rules ()
    ((_ test body ...) (let loop () (when test body ... (loop))))))

(define (t) (→ Bool) #t)

(record Counter
  ((count I64)))

(define (f (x I64)) (→ I64)
  (define y (* x 2))
  (define g (lambda (z) (+ y z)))
  (g 1))

(define (main (mut Mut) (out OutputPort)) (→ Unit)

  (let ((counter (new Counter (count 0))))
    (display out (my-or #f (t)))
    (newline out)
    (while (< (● counter count) 5) (set! mut (● counter count) (+ (● counter count) 1)))
    (display out (● counter count))
    (newline out)
    (display out (case (* 2 3) ((2 3 5 7) "prime") ((1 4 6 8 9) "composite") (else "other")))
    (newline out)
    (display out (cond ((> 1 2) "a") ((> 2 1) "b") (else "c")))
    (newline out)
    (display out (do ((i 0 (+ i 1)) (total 0 (+ total i))) ((= i 5) total)))
    (newline out)
    (display out (let* ((x 1) (y (+ x 1))) (* x y)))
    (newline out)
    (display out (f 10))
    (newline out)
    (unit)))
