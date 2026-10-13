(import (scheme base) (scheme read) (scheme write) (scheme time))

;; ---- Distinct managed references with numeric fields ----

(define size (read))
(define rounds (read))
(define objects (make-vector size (cons 1099511627776 0.25)))
(let loop ((index 0))
  (when (< index size)
    (vector-set! objects index (cons (+ 1099511627776 index) 0.25))
    (loop (+ index 1))))
(define anchor (vector-ref objects 0))
(define copied (vector-copy objects))
(unless (eq? anchor (vector-ref copied 0)) (error "copy lost pair identity"))

;; The array stores managed references. Updates happen to pair fields, leaving
;; reference element identity stable and testing shallow-copy alias behavior.
(define (update-pass)
  (let loop ((index 0))
    (when (< index size)
      (let ((object (vector-ref objects index)))
        (set-car! object (+ (car object) 1)))
      (loop (+ index 1)))))
(define (run)
  (let loop ((round 0))
    (when (< round rounds) (update-pass) (loop (+ round 1)))))
(define start (current-jiffy))
(run)
(define elapsed (/ (exact (- (current-jiffy) start)) (inexact (jiffies-per-second))))

;; ---- Complete observation outside the workload timer ----

(define (checksum)
  (let loop ((index 0) (sum 0))
    (if (= index size) sum
        (loop (+ index 1) (+ sum (car (vector-ref objects index)))))))
(define actual (checksum))
(define expected (+ (* size (+ 1099511627776 rounds)) (quotient (* size (- size 1)) 2)))
(unless (= actual expected) (error "pair update mismatch" actual expected))
(unless (eq? anchor (vector-ref copied 0)) (error "pair identity changed"))
(unless (= (+ 1099511627776 rounds) (car (vector-ref copied 0)))
  (error "shallow copy failed to observe field mutation"))
(display "+!STORAGE!+managed-pair-vector,")
(for-each (lambda (value) (write value) (display ",")) (list size rounds actual elapsed))
(newline)
