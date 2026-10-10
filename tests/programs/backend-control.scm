(import (scheme base) (scheme write))

(define (check actual expected)
  (if (not (equal? actual expected)) (error "control-flow check failed" actual expected)))

(define (identity value) value)

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

(display "control-flow checks passed")
(newline)
