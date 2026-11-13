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

(define t #t)

(struct Counter
  ((count I64)))

(define f
  (lambda (x) (define y (* x 2))
          (define g (lambda (z) (+ y z)))
          (g 1)))

(define main
  (lambda ()
    (let ((counter (Counter 0)))
      (display (my-or #f t))
      (newline)
      (while (< (● counter count) 5) (set! (● counter count) (+ (● counter count) 1)))
      (display (● counter count))
      (newline)
      (display (case (* 2 3) ((2 3 5 7) "prime") ((1 4 6 8 9) "composite") (else "other")))
      (newline)
      (display (cond ((> 1 2) "a") ((> 2 1) "b") (else "c")))
      (newline)
      (display (do ((i 0 (+ i 1)) (total 0 (+ total i))) ((= i 5) total)))
      (newline)
      (display (let* ((x 1) (y (+ x 1))) (* x y)))
      (newline)
      (display (f 10))
      (newline)
      (unit))))
