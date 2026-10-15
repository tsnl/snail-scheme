;; Alternate String/record union arms; keep allocation outside the timed loop.
(import (scheme base) (scheme write) (scheme time) (scheme process-context) (snail typing))

(define-record-type <box> (box value) box? (value : ExactInteger unbox))
(define text "abcdefgh")
(define item (box 13))

(: measure (-> (U String <box>) ExactInteger))
(define (measure value)
  (if (string? value) (string-length value) (unbox value)))

(define (workload repetitions)
  (let loop ((remaining (* repetitions 10000)) (total 0))
    (if (= remaining 0) total
        (loop (- remaining 1) (+ total (measure text) (measure item))))))

(unless (= (workload 1) 210000) (error "occurrence warmup disagreement"))
(define repetitions (string->number (cadr (command-line))))
(define start (current-jiffy))
(define checksum (workload repetitions))
(define finish (current-jiffy))
(unless (= checksum (* repetitions 210000)) (error "occurrence checksum disagreement"))
(display "checksum: ") (write checksum) (newline)
(display "elapsed: ")
(write (/ (* 1.0 (- finish start)) (jiffies-per-second)))
(display " s\n")
