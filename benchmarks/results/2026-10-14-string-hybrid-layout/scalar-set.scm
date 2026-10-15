(import (snail strict))

;; ---- Runtime Unicode input and rooted mutable storage ----

(define-extern input-i64 "benchmark" "input_i64" (-> I32 I64))
(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))
(define length (input-i64 (ann 0 I32)))
(define value (make-string length))
(define (scalar-at index)
  (let ((choice (remainder index 5)))
    (if (= choice 0) #\null
        (if (= choice 1) #\é
            (if (= choice 2) #\x1f600
                (if (= choice 3) #\x10ffff #\x301))))))
(let loop ((index 0))
  (unless (= index length)
    (string-set! value index (scalar-at index))
    (loop (+ index 1))))

;; ---- Timed scalar stores remain observable through exported probes ----

(define (write-span character)
  (let loop ((index 0))
    (unless (= index length)
      (string-set! value index character)
      (loop (+ index 1)))))
(: bench (-> I64 I64))
(define (bench count)
  (let loop ((round 0))
    (if (< round count)
        (begin (write-span (scalar-at (hide-i64 round))) (loop (+ round 1)))
        (* round length))))
(: probe-character (-> I64 Char))
(define (probe-character index) (string-ref value index))
(: probe-length (-> I64))
(define (probe-length) (string-length value))
(unit)
