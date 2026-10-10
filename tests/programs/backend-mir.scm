(import (scheme base) (scheme write))

(define (check actual expected)
  (if (not (equal? actual expected)) (error "MIR check failed" actual expected)))

(define (identity value) value)

;; Both arms suspend in Scheme calls. Their shared suffix must execute on each
;; arrival, including a replay, while the assigned cells retain their mutations.
(define (replay-branch choose-left?)
  (let ((saved #f) (phase 0) (visits '()))
    (let ((value
           (if choose-left?
               (identity (call/cc (lambda (k) (set! saved k) 10)))
               (identity (call/cc (lambda (k) (set! saved k) 20))))))
      (set! visits (cons value visits))
      (if (= phase 0)
          (begin (set! phase 1) (saved 30))
          (reverse visits)))))

(check (replay-branch #t) '(10 30))
(check (replay-branch #f) '(20 30))
(check (procedure? identity) #t)
(check (procedure? 12) #f)
(check (number? 12) #t)
(check (number? 1.5) #t)
(check (number? 'x) #f)
(check (exact-integer? 2147483648) #t)
(check (exact-integer? 1.5) #f)

;; Spelling does not identify the core binding, and source mutation disables
;; direct primitive elaboration throughout the program.
(check ((lambda (number?) (number? 'x)) (lambda (x) x)) 'x)
(define original-procedure? procedure?)
(set! procedure? (lambda (value) 'rebound))
(check (procedure? 12) 'rebound)
(set! procedure? original-procedure?)

(display "MIR checks passed")
(newline)
