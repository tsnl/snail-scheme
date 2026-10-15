(import (scheme base) (scheme write) (snail typing))

(define (check expected actual)
  (unless (equal? expected actual) (error "typed tail result" expected actual)))

;; ---- Dynamic calls and repeated boundaries ----

(: bounce (-> ExactInteger Procedure ExactInteger))
(define (bounce n next)
  (if (= n 0) 0 (next (- n 1) next)))
(define (step n next) (bounce n next))
(check 0 (bounce 1000000 step))

;; A late first assertion establishes just one checking frame after an arbitrarily
;; long unguarded prefix; local assertions finish before the pending outer ones.
(define (prefix n)
  (if (= n 0) (bounce 1000000 step) (prefix (- n 1))))
(check 0 (prefix 1000000))
(: separate-local-check (-> Procedure ExactInteger))
(define (separate-local-check next) (next))
(check 3 (separate-local-check (lambda () (ann (car (cons 3 #f)) i32))))

;; ---- Three-argument i32 state ----

(: fibonacci-state (-> i32 i32 i32 i32))
(define (fibonacci-state n a b)
  (if (<= n 0) a
      (if (= n 1) b (fibonacci-state (- n 1) b (+ a b)))))
(check 0 (fibonacci-state 0 0 1))
(check 1 (fibonacci-state 1 0 1))
(check 233 (fibonacci-state 10 2 3))
(check 1836311903 (fibonacci-state 46 0 1))
(check 0 (fibonacci-state 1000000 0 0))

;; An ordinary recursive operand call must finish before the outer tail edge
;; replaces any parameters. Alternating seeds expose sequential-update errors.
(: rotate-state (-> i32 i32 i32 i32))
(define (rotate-state n a b)
  (if (<= n 0) a (rotate-state (- n 1) (rotate-state 0 b a) a)))
(check 10 (rotate-state 1 3 10))
(check 3 (rotate-state 2 3 10))
(check 10 (rotate-state 100001 3 10))

;; Three different sites recur in different orders. Reachable obligations must
;; be bounded by these sites, even when every dynamic call needs a result guard.
(: stages Vector)
(: integer-stage (-> ExactInteger ExactInteger))
(define (integer-stage n)
  (if (= n 0) 42 ((vector-ref stages 1) (- n 1))))
(: number-stage (-> ExactInteger Number))
(define (number-stage n)
  (if (= n 0) 42 ((vector-ref stages 2) (- n 1))))
(: any-stage (-> ExactInteger Any))
(define (any-stage n)
  (if (= n 0) 42 ((vector-ref stages 0) (- n 1))))
(define stages (vector integer-stage number-stage any-stage))
(check 42 (integer-stage 1000000))

;; ---- Tail-forwarding Scheme primitives ----

(: via-apply (-> ExactInteger ExactInteger))
(define (via-apply n)
  (if (= n 0) 7 (apply via-apply (list (- n 1)))))
(check 7 (via-apply 1000000))

(: via-values (-> ExactInteger ExactInteger))
(define (via-values n)
  (if (= n 0) 11
      (call-with-values (lambda () (values (- n 1) "producer result"))
        (lambda (remaining ignored) (via-values remaining)))))
(check 11 (via-values 1000000))

;; The producer has its own return obligations. The caller's Integer obligation
;; belongs to the consumer, not to this producer's zero or multiple values.
(: zero-producer (-> ExactInteger))
(define (zero-producer)
  (call-with-values (lambda () (values)) (lambda () 9)))
(check 9 (zero-producer))

;; ---- Ordinary calls, assertions, and untyped results ----

(define (text) "abc")
(define (last-step n)
  (if (= n 0) (string-length (text)) (separated (- n 1) last-step)))
(: separated (-> ExactInteger Procedure ExactInteger))
(define (separated n next) (next n))
(check 3 (separated 1000000 last-step))

(: asserted (-> ExactInteger Procedure ExactInteger))
(define (asserted n next)
  (if (= n 0) 5 (ann (next (- n 1) next) ExactInteger)))
(define (assertion-step n next) (asserted n next))
(check 5 (asserted 1000000 assertion-step))

(define (untyped n)
  (if (= n 0) (values 1 2 3) (untyped (- n 1))))
(check '(1 2 3) (call-with-values (lambda () (untyped 1000000)) list))
(display "typed tail checks passed\n")
