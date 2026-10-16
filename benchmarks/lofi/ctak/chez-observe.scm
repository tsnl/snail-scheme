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

(define (ctak x y z)
  (observed-call/cc (lambda (k) (ctak-aux k x y z))))

(define (ctak-aux k x y z)
  (trace 0 x y z)
  (if (not (< y x))
      (k z)
      (observed-call/cc
       (lambda (k)
         ;; R7RS leaves operand order unspecified; select left to right.
         (let* ((first (observed-call/cc
                       (lambda (k) (ctak-aux k (- x 1) y z))))
                (second (observed-call/cc
                        (lambda (k) (ctak-aux k (- y 1) z x))))
                (third (observed-call/cc
                        (lambda (k) (ctak-aux k (- z 1) x y)))))
           (ctak-aux k first second third))))))

(let* ((x (read)) (y (read)) (z (read)))
  (trace 9 (ctak x y z) 0 0))
