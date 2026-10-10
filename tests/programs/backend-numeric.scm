(import (scheme base) (scheme write))

(define (check expected actual)
  (if (not (equal? expected actual)) (error "numeric instruction mismatch" expected actual)))

;; Compare direct Wasm helpers with the uniform closure adapters.
(define (check-operations x y add subtract equal less less-equal greater greater-equal)
  (check (add x y) (+ x y))
  (check (subtract x y) (- x y))
  (check (equal x y) (= x y))
  (check (less x y) (< x y))
  (check (less-equal x y) (<= x y))
  (check (greater x y) (> x y))
  (check (greater-equal x y) (>= x y)))

;; Cross every fixnum edge, zero, sign, boxed integer, and inexact fallback.
(for-each (lambda (x)
            (for-each (lambda (y) (check-operations x y + - = < <= > >=))
                      '(-1073741825 -1073741824 -1 0 1 1073741823 1073741824 2.5)))
          '(-1073741825 -1073741824 -1 0 1 1073741823 1073741824 2.5))
(check #f (= +nan.0 1))
(check #t (< -inf.0 +inf.0))
(check 6 (+ 1 2 3))
(check -8 (- 8))
(check 7 (let ((- (lambda (x y) (+ x y)))) (- 3 4)))
(check '#(1 2 3) (vector 1 2 3))
(check 5 (apply - '(9 4)))

;; Effects and values checks still occur before a direct numeric instruction.
(define order '())
(define (note x) (set! order (cons x order)) x)
(check 5 (- (note 9) (note 4)))
(check '(4 9) order)

;; Numeric allocation must retain the executing closure's captured objects.
(define (capturing text)
  (lambda (n) (+ n 1) text))
(check "captured" ((capturing (string #\c #\a #\p #\t #\u #\r #\e #\d)) 1073741823))

;; Tail calls to numeric helpers preserve the result.
(define (tail-add x y) (+ x y))
(check 1073741824 (tail-add 1073741823 1))
(display "numeric instruction checks passed\n")
