;; FIBC, with captured operand contexts and Peano addition kept explicit.
(import (lofi base))

;; ---- Captured Fibonacci operands ----

;; The source captures the continuation of each recursive operand. Immutable
;; frames retain the unevaluated operand and the enclosing return context.
(def Continuation (datatype ()
  (done)
  (first-operand (n I64) (next Continuation))
  (second-operand (first I64) (next Continuation))))

(def capture (-> Continuation Continuation)
  (lambda (current) current))

(def succ (-> I64 I64) (lambda (n) (+ n (ann 1 I64))))
(def pred (-> I64 I64) (lambda (n) (- n (ann 1 I64))))

;; Each successor/predecessor pair is part of the benchmark's algorithm.
(def addc (-> I64 I64 Continuation I64)
  (lambda (x y next)
    (if (= y (ann 0 I64))
      (resume next x)
      (addc (succ x) (pred y) next))))

(def fibc (-> I64 Continuation I64)
  (lambda (x next)
    (if (= x (ann 0 I64))
      (resume next (ann 0 I64))
      (if (= (pred x) (ann 0 I64))
        (resume next (ann 1 I64))
        (fibc (pred x) (capture (first-operand x next)))))))

(def resume (-> Continuation I64 I64)
  (lambda (continuation value)
    (match continuation
      ((done) value)
      ((first-operand x next)
        (fibc (pred (pred x)) (capture (second-operand value next))))
      ((second-operand first next) (addc first value next)))))

;; ---- Canonical benchmark driver ----

(define-extern input-i64 "benchmark" "input_i64" (-> I32 I64))
(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(def input (input-i64 (ann 0 I32)))

;; The original hides the identity continuation separately from the input.
(def hidden-identity (-> Continuation)
  (lambda () (if (barrier) (done) (done))))

(def bench (-> I64 I64)
  (lambda (count)
    (begin
      (def repeat (-> I64 I64 I64)
        (lambda (iteration result)
          (if (< iteration count)
            (repeat (+ iteration (ann 1 I64)) (fibc (hide-i64 input) (hidden-identity)))
            result)))
      (repeat (ann 0 I64) (ann 0 I64)))))

(unit)
