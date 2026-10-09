;; A sieve of Eratosthenes followed by a retained list of all discovered primes.
;;
;; Each repetition allocates a fresh flag vector and a fresh prime list. This
;; exercises indexed mutable storage, allocation, and sequential list traversal.
;; Unlike matrix multiplication, the work per allocated byte is relatively low.
;; The list remains reachable while its count, sum, and prime gaps are examined.
(import (scheme base) (scheme write) (scheme time) (scheme process-context))

(define limit 100000)

;; Mutable sieve. Only multiples starting at p*p need clearing: every smaller
;; composite with factor p has already been visited by a smaller prime.

(define (initial-flags maximum)
  (let ((flags (make-vector (+ maximum 1) #t)))
    (vector-set! flags 0 #f)
    (when (> maximum 0) (vector-set! flags 1 #f))
    flags))

(define (clear-multiples! flags prime maximum)
  (let loop ((multiple (* prime prime)))
    (when (<= multiple maximum)
      (vector-set! flags multiple #f)
      (loop (+ multiple prime)))))

(define (sieve maximum)
  (let ((flags (initial-flags maximum)))
    (let loop ((candidate 2))
      (when (<= (* candidate candidate) maximum)
        (when (vector-ref flags candidate)
          (clear-multiples! flags candidate maximum))
        (loop (+ candidate 1))))
    flags))

;; Visit backwards so cons constructs the final ascending list directly.

(define (prime-list flags)
  (let loop ((candidate (- (vector-length flags) 1)) (primes '()))
    (cond ((< candidate 2) primes)
          ((vector-ref flags candidate)
           (loop (- candidate 1) (cons candidate primes)))
          (else (loop (- candidate 1) primes)))))

(define-record-type prime-summary
  (make-summary count sum last twins largest-gap)
  prime-summary?
  (count summary-count)
  (sum summary-sum)
  (last summary-last)
  (twins summary-twins)
  (largest-gap summary-largest-gap))

(define empty-summary (make-summary 0 0 0 0 0))

(define (larger a b)
  (if (> a b) a b))

(define (next-summary summary prime)
  (let* ((previous (summary-last summary))
         (gap (if (= previous 0) 0 (- prime previous))))
    (make-summary (+ (summary-count summary) 1)
                  (+ (summary-sum summary) prime)
                  prime
                  (+ (summary-twins summary) (if (= gap 2) 1 0))
                  (larger (summary-largest-gap summary) gap))))

(define (summarize primes)
  (let loop ((remaining primes) (summary empty-summary))
    (if (null? remaining)
        summary
        (loop (cdr remaining) (next-summary summary (car remaining))))))

(define (summary-values summary)
  (list (summary-count summary) (summary-sum summary) (summary-last summary)
        (summary-twins summary) (summary-largest-gap summary)))

(define (workload maximum)
  (let* ((primes (prime-list (sieve maximum)))
         (summary (summarize primes)))
    ;; This later use keeps the entire list live while summarize allocates.
    (unless (= (length primes) (summary-count summary))
      (error "prime list changed during summarization"))
    summary))

;; Trial division is deliberately independent of the sieve. Small boundary
;; cases exercise empty output and primes exactly at the inclusive upper bound.

(define (prime-by-division? n)
  (and (>= n 2)
       (let loop ((divisor 2))
         (cond ((> (* divisor divisor) n) #t)
               ((= (modulo n divisor) 0) #f)
               (else (loop (+ divisor 1)))))))

(define (check-flags maximum)
  (let ((flags (sieve maximum)))
    (let loop ((n 0))
      (when (<= n maximum)
        (unless (eq? (vector-ref flags n) (prime-by-division? n))
          (error "sieve disagrees with trial division" n))
        (loop (+ n 1))))))

(define (require-summary summary expected)
  (unless (equal? (summary-values summary) expected)
    (error "incorrect prime summary" (summary-values summary) expected)))

(define (check-known-summaries)
  (for-each
   (lambda (example)
     (require-summary (workload (car example)) (cdr example)))
   '((0 0 0 0 0 0)
     (1 0 0 0 0 0)
     (2 1 2 2 0 0)
     (10 4 17 7 2 2)
     (100 25 1060 97 8 8)
     (1000 168 76127 997 35 20))))

(define (check-sieve)
  (for-each check-flags '(0 1 2 3 4 49 128))
  (check-known-summaries))

;; A summary is retained across repetitions, while the previous vector and list
;; become garbage. Check every completed repetition, not just the final one.

(define expected-summary '(9592 454396537 99991 1224 72))

(define (summary-checksum summary)
  (+ (summary-sum summary) (* 3 (summary-count summary))
     (* 5 (summary-last summary)) (* 7 (summary-twins summary))
     (* 11 (summary-largest-gap summary))))

(define (repeat-work count)
  (let loop ((remaining count) (checksum 0))
    (if (= remaining 0)
        checksum
        (let ((summary (workload limit)))
          (require-summary summary expected-summary)
          (loop (- remaining 1) (+ checksum (summary-checksum summary)))))))

(define (positive-count text)
  (let ((count (string->number text)))
    (unless (and (exact-integer? count) (> count 0))
      (error "repeat count must be a positive integer" text))
    count))

(define (repetitions)
  (let ((arguments (cdr (command-line))))
    (cond ((null? arguments) 1)
          ((null? (cdr arguments)) (positive-count (car arguments)))
          (else (error "usage: memory [REPETITIONS]")))))

(define (elapsed-microseconds start finish)
  (quotient (* (- finish start) 1000000) (jiffies-per-second)))

(define (write-milliseconds microseconds)
  (display (quotient microseconds 1000))
  (display ".")
  (let ((fraction (modulo microseconds 1000)))
    (when (< fraction 100) (display "0"))
    (when (< fraction 10) (display "0"))
    (display fraction)))

(define (report checksum elapsed count)
  (display "Memory: sieve and prime list") (newline)
  (display "checksum: ") (write checksum) (newline)
  (display "elapsed: ") (write-milliseconds elapsed)
  (display " ms; repetitions: ") (write count) (newline))

(define (main)
  (check-sieve)
  (let* ((count (repetitions))
         (start (current-jiffy))
         (checksum (repeat-work count))
         (finish (current-jiffy)))
    (report checksum (elapsed-microseconds start finish) count)))

(main)
