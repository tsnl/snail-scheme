(import (scheme base) (scheme read) (scheme write) (scheme time))

;; ---- One homogeneous allocation with no opaque mutator ----

(define size (read))
(define rounds (read))
(define objects (make-vector size 1099511627776))
(let loop ((index 0))
  (when (< index size)
    (vector-set! objects index (+ 1099511627776 index))
    (loop (+ index 1))))
(define (update-pass)
  (let loop ((index 0))
    (when (< index size)
      (vector-set! objects index (+ (vector-ref objects index) 1))
      (loop (+ index 1)))))
(define (run)
  (let loop ((round 0))
    (when (< round rounds) (update-pass) (loop (+ round 1)))))

;; ---- Full observation outside the hot loop ----

(define start (current-jiffy))
(run)
(define elapsed (/ (exact (- (current-jiffy) start)) (inexact (jiffies-per-second))))
(define (checksum)
  (let loop ((index 0) (sum 0))
    (if (= index size) sum
        (loop (+ index 1) (+ sum (vector-ref objects index))))))
(define actual (checksum))
(define expected
  (+ (* size (+ 1099511627776 (* rounds 1)))
     (quotient (* size (- size 1)) 2)))
(unless (= actual expected) (error "homogeneous update mismatch" actual expected))
(display "+!STORAGE!+i64-update,")
(for-each (lambda (value) (write value) (display ","))
          (list size rounds actual elapsed))
(newline)
