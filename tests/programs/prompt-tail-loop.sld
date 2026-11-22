(import
 (snail core base)
 (snail core io))

;; A handler that resumes in tail position runs in constant stack, however
;; many times its body suspends: a hundred thousand suspensions grow
;; neither the loop's stack nor the handler's.
(define ticking (→ (Prompt I64 I64)) (make-prompt))

(define (count-down (n I64) (total I64)) (→ I64)
  (if (= n 0) total (count-down (- n 1) (+ total (suspend ticking n)))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out
           (with-prompt ticking
                        (lambda () (count-down 100000 0))
                        (lambda (n resume) (resume (* n 2)))))
  (newline out)
  (unit))
