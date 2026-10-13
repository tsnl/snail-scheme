(import (scheme base) (scheme write) (scheme process-context) (snail typing))

;; ---- Concrete payloads and shared locations ----

(define (check expected actual)
  (unless (equal? expected actual)
    (error "binding storage disagreement" expected actual)))

(: global-real InexactReal)
(define global-real -0.0)
(check -inf.0 (/ 1.0 global-real))
(set! global-real 2.5)
(check 2.5 global-real)

(: make-parameter-counter (-> InexactReal Procedure))
(define (make-parameter-counter value)
  (: increment (-> InexactReal InexactReal))
  (define (increment step)
    (set! value (+ value step))
    value)
  increment)
(define first-counter (make-parameter-counter 1.25))
(define second-counter (make-parameter-counter 2.5))
(check 1.75 (first-counter 0.5))
(check 2.0 (apply first-counter (list 0.25)))
(check 2.5 (second-counter 0.0))

(: capture-fields (-> InexactReal ExactInteger Boolean Char Procedure))
(define (capture-fields real integer boolean character)
  (lambda ()
    (check 1.25 real)
    (check 4294967296 integer)
    (check #f boolean)
    (check #\λ character)))
((capture-fields 1.25 4294967296 #f #\λ))

;; ---- Initialization belongs to the location ----

(define (assigned-before-initializer)
  (: value InexactReal)
  (define (read-value) value)
  (: write-value (-> InexactReal Unspecified))
  (define (write-value new) (set! value new))
  (define ignored (begin (write-value 1.5) (check 1.5 (read-value))))
  (define value 2.5)
  (check 2.5 (read-value)))
(assigned-before-initializer)

(define (read-before-initializer)
  (: value InexactReal)
  (define (read-value) value)
  (define ignored (read-value))
  (define value 1.25)
  value)

(if (member "early-read" (command-line))
    (read-before-initializer)
    (display "binding storage checks passed\n"))
