;; Diagnostic observation only; never the measured benchmark.
(import (rnrs))

;; Event 0: source call; 1: capture; 2: invocation; 3: Peano step; 9: result.
(define (trace event x y z)
  (for-each (lambda (value) (display value) (display " ")) (list event x y z))
  (newline))

(define (observed-call/cc receiver)
  (trace 1 0 0 0)
  (call-with-current-continuation
    (lambda (k)
      (receiver (lambda (value) (trace 2 value 0 0) (k value))))))

(define (succ n) (+ n 1))
(define (pred n) (- n 1))

(define (addc x y k)
  (if (zero? y)
      (k x)
      (begin (trace 3 x y 0) (addc (succ x) (pred y) k))))

(define (fibc x c)
  (trace 0 x 0 0)
  (if (zero? x)
      (c 0)
      (if (zero? (pred x))
          (c 1)
          ;; R7RS leaves operand order unspecified; select left to right.
          (let* ((first (observed-call/cc (lambda (c) (fibc (pred x) c))))
                 (second (observed-call/cc (lambda (c) (fibc (pred (pred x)) c)))))
            (addc first second c)))))

(trace 9 (fibc (read) (lambda (value) (trace 2 value 0 0) value)) 0 0)
