(import (scheme base) (scheme write) (snail typing))

;; ---- A user-defined operation ----

(define-class (Combine T)
  (: combine (-> T T T)))

(define-instance (Combine i32)
  (combine (lambda (x y) (+ x y))))
(define-instance (Combine String)
  (combine (lambda (x y) (string-append x y))))

;; ---- One algorithm, two specializations ----

(: twice (All (T) (=> ((Combine T)) (-> T T))))
(define (twice x) (combine x x))

(write (twice 21)) (newline)
(write (twice "hello")) (newline)

;; A selected specialization is an ordinary first-class procedure.
(define double-string (inst twice String))
(write (double-string "x")) (newline)
