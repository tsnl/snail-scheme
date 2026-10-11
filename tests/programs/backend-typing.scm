(import (scheme base) (scheme write) (snail typing))

(define (check expected actual)
  (unless (equal? expected actual) (error "typing result" expected actual)))

;; ---- Guarded functions and occurrence filters ----

(: fibonacci (-> ExactInteger ExactInteger))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(: measure (-> (U String ExactInteger) ExactInteger))
(define (measure x)
  (let ((text? string?))
    (let ((saved (text? x)))
      (if saved (string-length x) (+ x 1)))))

(define (textual? x) (string? x))
(: measured (-> (U String ExactInteger) ExactInteger))
(define (measured x) (if (textual? x) (string-length x) (+ x 1)))

(: choose (-> Any Boolean))
(define (choose x) (and (string? x) (> (string-length x) 2)))

(: mutable (-> ExactInteger ExactInteger))
(define (mutable n)
  (define (increment!) (set! n (+ n 1)))
  (increment!) n)

(check 75025 (fibonacci 25))
(check 3 (measure "abc"))
(check 10 (measure 9))
(check 4 (measured "abcd"))
(check 6 (measured 5))
(check #t (choose "hello"))
(check #f (choose 3))
(check 11 (mutable 10))
(check 12 ((ann (lambda (n) (+ n 2)) (-> ExactInteger ExactInteger)) 10))
(check 42 (ann ((lambda (f) (f)) (lambda () 42)) ExactInteger))

;; ---- Integer representations and unchecked source compatibility ----

(: plus (-> ExactInteger ExactInteger ExactInteger))
(define (plus a b) (+ a b))
(check 2147483648 (plus 2147483647 1))
(check -2147483649 (plus -2147483648 -1))
(check 9223372036854775807 (plus 9223372036854775806 1))
(check -9223372036854775808 (plus -9223372036854775807 -1))
(check #t (integer? 2.0))
(check 3.0 (if (integer? 2.0) (+ 2.0 1) 0))
(check 3 ((lambda (+) (+ 1 2)) (lambda (x y) (- y (- x 2)))))
(check '(1 2) (call-with-values (lambda () (values 1 2)) list))

;; A mutable read has no occurrence identity, even when mutation is nested.
(let ((x 1))
  (define (change!) (set! x "changed"))
  (check 2 (if (exact-integer? x) (+ x (begin (change!) 1)) 0))
  (check "changed" x))


;; Typed fields extend the existing record form. Nominal identity is independent
;; of the mutable field's value, which the accessor must check on every read.
(define-record-type <point>
  (make-point y x) point?
  (x : ExactInteger point-x set-point-x!)
  (y : String point-y))
(: point-measure (-> (U String <point>) ExactInteger))
(define (point-measure value)
  (if (point? value) (point-x value) (string-length value)))
(define point (make-point "a" 4))
(check 4 (point-measure point))
(check 3 (point-measure "abc"))
(set-point-x! point 8)
(check 8 (point-x point))

;; The specialized representation must preserve widened intermediates and tails.
(: fibonacci32 (-> i32 i32 i32))
(define (fibonacci32 n offset)
  (if (< n 2) (+ n offset)
      (+ (fibonacci32 (- n 1) offset) (fibonacci32 (- n 2) offset))))
;; F(10) + 3 * F(11): the second argument participates in every base case.
(check 322 (fibonacci32 10 3))
(: cancel (-> i32 i32 i32))
(define (cancel a b) (- (+ a b) b))
(check 2147483647 (cancel 2147483647 2147483647))
(check -2147483648 (cancel -2147483648 -2147483648))
(: count-down (-> i32 i32 i32))
(define (count-down n total)
  (if (= n 0) total (count-down (- n 1) (+ total 1))))
(check 1000000 (count-down 1000000 0))
(display "typing checks passed\n")
