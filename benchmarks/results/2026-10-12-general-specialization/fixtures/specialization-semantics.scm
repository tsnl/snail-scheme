(import (scheme base) (scheme write) (snail typing))

;; These independent checks exercise observable behavior across specialization
;; boundaries. They are deliberately broader than a numeric recursion kernel.

(define (check name value expected)
  (unless (equal? value expected) (error name value expected))
  (display name)
  (newline))

(: identity (All (A) (-> A A)))
(define (identity value) value)
(check 'poly-integer (identity 1073741824) 1073741824)
(check 'poly-float (identity 1.25) 1.25)
(check 'poly-string (identity "hello") "hello")
(check 'poly-identity (eq? identity (inst identity String)) #t)
(check 'poly-opaque (apply (inst identity String) (list 42)) 42)

(define (untyped-id value) value)
(check 'inferred-integer (untyped-id 7) 7)
(check 'inferred-string (untyped-id "seven") "seven")
(check 'inferred-pair (untyped-id '(one . two)) '(one . two))

(define (make-offset amount)
  (lambda (value) (+ value amount)))
(define add-two (make-offset 2))
(define add-three (make-offset 3))
(check 'captured-integers (list (add-two 10) (add-three 10)) '(12 13))
(check 'captured-floats (list (add-two 1.5) (add-three 2.5)) '(3.5 5.5))

(define (invoke procedure value) (procedure value))
(check 'higher-order (list (invoke identity "value") (invoke add-two 9)) '("value" 11))
(define changing untyped-id)
(check 'before-assignment (changing 3) 3)
(set! changing add-three)
(check 'after-assignment (changing 3) 6)

(define shared (vector 'first))
(check 'shared-identity (eq? ((inst identity Vector) shared) shared) #t)
(vector-set! (untyped-id shared) 0 'changed)
(check 'shared-mutation (vector-ref ((inst identity Vector) shared) 0) 'changed)

(define (make-counter value)
  (lambda () (set! value (+ value 1)) value))
(define counter (make-counter 10))
(check 'mutable-capture (list (counter) (counter) (counter)) '(11 12 13))

(define (nested-capture offset value)
  (define (add-to-offset argument) (+ offset argument))
  (add-to-offset value))
(check 'nested-integers (nested-capture 10 4) 14)
(check 'nested-floats (nested-capture 1.5 2.25) 3.75)
(check 'nested-mixed (nested-capture 1.5 4) 5.5)

(define (forward-identity value)
  ((lambda (argument) (untyped-id argument)) value))
(check 'nested-reference (forward-identity "same reference") "same reference")
(check 'nested-number (forward-identity 1073741824) 1073741824)

(define (same-a left right depth)
  (if (= depth 0) (list left right) (same-b right left (- depth 1))))
(define (same-b left right depth)
  (if (= depth 0) (list left right) (same-a right left (- depth 1))))
(check 'mutual-tail (same-a 'left "right" 100000) '(left "right"))

(define (many value) (values value (+ value 1)))
(check 'multiple-values (call-with-values (lambda () (many 7)) list) '(7 8))
(check 'rest-arguments (apply list '(1 "two" 3.5)) '(1 "two" 3.5))

(define order '())
(define (note tag value) (set! order (cons tag order)) value)
(check 'operand-result ((note 'operator +) (note 'left 1) (note 'right 2)) 3)
;; Save the baseline's observable order for a byte-for-byte differential check.
(write (reverse order))
(newline)
(display "specialization semantics passed")
(newline)
