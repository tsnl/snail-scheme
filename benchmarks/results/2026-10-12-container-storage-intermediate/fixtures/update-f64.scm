(import (scheme base) (scheme read) (scheme write) (scheme time))

;; ---- One homogeneous allocation with no opaque mutator ----

(define size (read))
(define rounds (read))
(define objects (make-vector size 0.25))
(let loop ((index 0))
  (when (< index size)
    (vector-set! objects index (+ 0.25 (inexact index)))
    (loop (+ index 1))))
(define (update-pass)
  (let loop ((index 0))
    (when (< index size)
      (vector-set! objects index (+ (vector-ref objects index) 0.5))
      (loop (+ index 1)))))
(define (run)
  (let loop ((round 0))
    (when (< round rounds) (update-pass) (loop (+ round 1)))))

;; ---- Full observation outside the hot loop ----

(define start (current-jiffy))
(run)
(define elapsed (/ (exact (- (current-jiffy) start)) (inexact (jiffies-per-second))))
(define (checksum)
  (let loop ((index 0) (sum 0.0))
    (if (= index size) sum
        (loop (+ index 1) (+ sum (vector-ref objects index))))))
(define actual (checksum))
(define expected
  (+ (* size (+ 0.25 (* rounds 0.5)))
     (quotient (* size (- size 1)) 2)))
(unless (= actual expected) (error "homogeneous update mismatch" actual expected))
(display "+!STORAGE!+f64-update,")
(for-each (lambda (value) (write value) (display ","))
          (list size rounds actual elapsed))
(newline)
