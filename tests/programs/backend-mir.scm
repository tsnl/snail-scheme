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

;; Direct literals exercise immediate emission; quoted containers still load
;; their children through the constant table. Compare against runtime values.
(check -1073741824 (string->number "-1073741824"))
(check 1073741823 (string->number "1073741823"))
(check -1073741825 (string->number "-1073741825"))
(check 1073741824 (string->number "1073741824"))
(check -1 (string->number "-1"))
(check #\λ (integer->char 955))
(check #f (not #t))
(check '() (cdr '(1)))
(check (inexact? 1.0) #t)
(check (list 1 -1 #t #f #\λ '()) (vector->list '#(1 -1 #t #f #\λ ())))
(check (if #f 'unreachable) (if #f 'also-unreachable))

;; Spelling does not identify the core binding, and source mutation disables
;; direct primitive elaboration throughout the program.
(check ((lambda (number?) (number? 'x)) (lambda (x) x)) 'x)
(define original-procedure? procedure?)
(set! procedure? (lambda (value) 'rebound))
(check (procedure? 12) 'rebound)
(set! procedure? original-procedure?)

(display "MIR checks passed")
(newline)
