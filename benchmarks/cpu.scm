;; Recursive Fibonacci: deliberately repeat arithmetic and procedure calls.
;;
;; Run from the repository root. An optional positive argument repeats the
;; fixed workload; it never changes the inputs or chooses a faster algorithm.
;; This is a call/arithmetic baseline, not a recommended Fibonacci algorithm.
;; The iterative implementation supplies an independent, untimed oracle.
(import (scheme base) (scheme write) (scheme time) (scheme process-context))

;; ---- Inputs and algorithms ----

(define inputs '(22 23 24 25))

(define (fibonacci n)
  (if (< n 2)
      n
      (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(define (fibonacci-linear n)
  (let loop ((remaining n) (a 0) (b 1))
    (if (= remaining 0)
        a
        (loop (- remaining 1) b (+ a b)))))

(define (weighted-answer n answer)
  (* (+ n 1) answer))

(define (workload)
  (let loop ((remaining inputs) (checksum 0))
    (if (null? remaining)
        checksum
        (let ((n (car remaining)))
          (loop (cdr remaining)
                (+ checksum (weighted-answer n (fibonacci n))))))))

(define (expected-answer)
  (let loop ((remaining inputs) (checksum 0))
    (if (null? remaining)
        checksum
        (let ((n (car remaining)))
          (loop (cdr remaining)
                (+ checksum (weighted-answer n (fibonacci-linear n))))))))

;; Checks run before the timer, including the two recursion base cases.

(define (require-equal actual expected description)
  (unless (= actual expected)
    (error description actual expected)))

(define (check-small-inputs)
  (let loop ((n 0))
    (when (<= n 12)
      (require-equal (fibonacci n) (fibonacci-linear n) "Fibonacci disagreement")
      (loop (+ n 1)))))

(define (check-known-values)
  (for-each
   (lambda (example)
     (require-equal (fibonacci-linear (car example)) (cdr example)
                    "incorrect Fibonacci oracle"))
   '((0 . 0) (1 . 1) (2 . 1) (10 . 55) (22 . 17711) (25 . 75025))))

(define (check-recurrence n)
  (require-equal (fibonacci-linear (+ n 2))
                 (+ (fibonacci-linear n) (fibonacci-linear (+ n 1)))
                 "incorrect Fibonacci recurrence"))

(define (check-cassini n)
  (let ((previous (fibonacci-linear (- n 1)))
        (current (fibonacci-linear n))
        (next (fibonacci-linear (+ n 1))))
    (require-equal (- (* previous next) (* current current))
                   (if (= (modulo n 2) 0) 1 -1)
                   "incorrect Fibonacci identity")))

(define (check-oracle)
  (check-small-inputs)
  (check-known-values)
  (for-each check-recurrence inputs)
  (for-each check-cassini inputs))

;; Fixed repetition keeps future compiler comparisons comparable. Checking the
;; result makes incorrect computation observable; valid constant folding remains
;; a possible future optimization of these deliberately fixed inputs.

(define (positive-count text)
  (let ((count (string->number text)))
    (unless (and (exact-integer? count) (> count 0))
      (error "repeat count must be a positive integer" text))
    count))

(define (repetitions)
  (let ((arguments (cdr (command-line))))
    (cond ((null? arguments) 1)
          ((null? (cdr arguments)) (positive-count (car arguments)))
          (else (error "usage: cpu [REPETITIONS]")))))

(define (repeat-work count expected)
  (let loop ((remaining count) (checksum 0))
    (if (= remaining 0)
        checksum
        (let ((answer (workload)))
          (require-equal answer expected "incorrect Fibonacci result")
          (loop (- remaining 1) (+ checksum answer))))))

(define (elapsed-microseconds start finish)
  (quotient (* (- finish start) 1000000) (jiffies-per-second)))

(define (write-seconds microseconds)
  (display (quotient microseconds 1000000))
  (display ".")
  (let ((fraction (number->string (modulo microseconds 1000000))))
    (display (substring "000000" 0 (- 6 (string-length fraction))))
    (display fraction)))

(define (report answer microseconds count)
  (display "CPU: recursive Fibonacci") (newline)
  (display "checksum: ") (write answer) (newline)
  (display "elapsed: ") (write-seconds microseconds)
  (display " s; repetitions: ") (write count) (newline))

(define (main)
  (check-oracle)
  (let* ((count (repetitions))
         (expected (expected-answer))
         (start (current-jiffy))
         (answer (repeat-work count expected))
         (finish (current-jiffy)))
    (require-equal answer (* count expected) "incorrect Fibonacci checksum")
    (report answer (elapsed-microseconds start finish) count)))

(main)
