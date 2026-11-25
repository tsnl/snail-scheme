(import
 (snail core base)
 (snail core io))

(define asking (→ (Prompt I64 I64)) (make-prompt))

(define (ask (n I64)) (→ I64)
  (suspend asking n))

(define (read-then-ask (x (Ref I64))) (→ I64)
  (let ((saved (ref-get x)))
    (+ saved (ask saved))))

(define (work) (→ I64)
  (let ((x (ref-local 21)))
    (+ 1 (read-then-ask (ref x)))))

(define stopped (→ (Prompt I64 Never)) (make-prompt))

(define (checked (x (Ref I64)) (stop? Bool)) (→ I64)
  (when stop? (absurd (suspend stopped 10)))
  (ref-get x))

(define (attempt (stop? Bool)) (→ I64)
  (with-prompt stopped
               (lambda ()
                 (let ((x (ref-local 20)))
                   (+ 1 (checked (ref x) stop?))))
               (lambda (n resume) n)))

(define (main (out OutputPort)) (→ Unit)
  (write-line out (show (with-prompt asking work (lambda (n resume) (resume n)))))
  (write-line out (show (attempt #f)))
  (write-line out (show (attempt #t))))
