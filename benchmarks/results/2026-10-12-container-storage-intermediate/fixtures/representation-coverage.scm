(import (scheme base) (scheme read) (scheme write) (scheme inexact))

;; ---- Ordinary values and observable checks ----

(define (check expected actual)
  (unless (equal? expected actual) (error "storage coverage mismatch" expected actual)))
(define (identity value) value)
(define (other-identity value) value)
(define opaque-identity (if (read) identity other-identity))

;; ---- Homogeneous elements and source/result independence ----

(define (numeric-source)
  (let ((source (make-vector 4 0.25)))
    (vector-set! source 1 1.25)
    source))
(define (check-numeric-vector)
  (let* ((source (numeric-source)) (alias source)
         (appended (vector-append source source)) (copied (vector-copy source)))
    (check #t (eq? source alias))
    (vector-set! alias 2 2.25)
    (check 2.25 (vector-ref source 2))
    (vector-set! appended 0 "result-only")
    (vector-set! copied 1 #t)
    (check 0.25 (vector-ref source 0))
    (check 1.25 (vector-ref source 1))
    (check "result-only" (vector-ref appended 0))))

;; Both uses refer to the same mutable hole. The allocation must use common
;; storage from the start; this is not a request for runtime backing widening.
(define (check-shared-object)
  (let* ((source (make-vector 2 0.25))
         (first (identity source)) (second (opaque-identity source)))
    (vector-set! second 0 "shared")
    (check #t (eq? first second))
    (check "shared" (vector-ref first 0))))

(define (filled value) (make-vector 2 value))
(define (check-factory-instantiation)
  (let ((numeric (filled 0.25)) (heterogeneous (filled 0.25)))
    (vector-set! heterogeneous 0 "separate allocation")
    (vector-set! numeric 1 1.25)
    (check 0.25 (vector-ref numeric 0))
    (check 1.25 (vector-ref numeric 1))
    (check "separate allocation" (vector-ref heterogeneous 0))))

;; ---- Numeric edge values and mixed layouts ----

(define (check-numeric-edges)
  (let* ((real (vector -0.0 +nan.0 1.25))
         (integer (vector 1099511627776 -1099511627776))
         (output (vector-append real integer)))
    (check -inf.0 (/ 1.0 (vector-ref output 0)))
    (check #t (nan? (vector-ref output 1)))
    (check 1.25 (vector-ref output 2))
    (check #t (exact? (vector-ref output 3)))
    (check 1099511627776 (vector-ref output 3))
    (vector-copy! output 0 integer)
    (check 1099511627776 (vector-ref output 0))))
(define (check-overlap)
  (let ((values (vector 1.25 2.25 3.25 4.25)))
    (vector-copy! values 1 values 0 3)
    (check 1.25 (vector-ref values 1))
    (check 3.25 (vector-ref values 3))
    (vector-copy! values 0 values 1 4)
    (check 1.25 (vector-ref values 0))
    (check 3.25 (vector-ref values 2))))

;; ---- Managed references and shallow copy ----

(define (check-reference-elements)
  (let* ((element (cons 1099511627776 0.25))
         (source (make-vector 2 element)) (output (vector-copy source)))
    (check #t (eq? element (vector-ref output 0)))
    (set-car! element 1099511627777)
    (check 1099511627777 (car (vector-ref output 1)))
    (vector-set! output 0 (cons 7 0.25))
    (check #t (eq? element (vector-ref source 0)))))

;; ---- Pair fields, record fields, and scalar returns ----

(define-record-type <sample> (sample count weight) sample?
  (count sample-count set-sample-count!) (weight sample-weight set-sample-weight!))
(define (check-pair-fields)
  (let ((object (cons 1099511627776 0.25)))
    (set-car! object (+ (car object) 1))
    (set-cdr! object (+ (cdr object) 0.5))
    (check 1099511627777 (car object))
    (check 0.75 (cdr object))))
(define (check-record-fields)
  (let* ((object (sample 1099511627776 0.25)) (alias object))
    (set-sample-count! alias (+ (sample-count object) 1))
    (set-sample-weight! alias (+ (sample-weight object) 0.5))
    (check #t (eq? object alias))
    (check 1099511627777 (sample-count object))
    (check 0.75 (sample-weight object))))
(define (real-return value) (+ value 0.5))
(define (integer-return value) (+ value 1))

;; ---- Immutable captures and shared mutable captured cells ----

(define (real-reader value) (lambda (input) (+ value input)))
(define (integer-reader value) (lambda (input) (+ value input)))
(define (shared-counter)
  (let ((value 0.25))
    (cons (lambda () (set! value (+ value 0.5))) (lambda () value))))
(define (check-captures)
  (let ((real (real-reader 0.25)) (integer (integer-reader 1099511627776))
        (counter (shared-counter)))
    (check 1.75 (real 1.5))
    (check 1099511627777 (integer 1))
    ((car counter))
    ((car counter))
    (check 1.25 ((cdr counter)))))

;; ---- Boolean and character storage conversions ----

(define (check-tags)
  (let ((flags (make-vector 2 #f)) (characters (make-vector 2 (integer->char 955))))
    (vector-set! flags 1 #t)
    (vector-set! characters 1 (integer->char 128512))
    (check #f (vector-ref flags 0))
    (check #t (vector-ref flags 1))
    (check 955 (char->integer (vector-ref characters 0)))
    (check 128512 (char->integer (vector-ref characters 1)))))

(check-numeric-vector)
(check-shared-object)
(check-factory-instantiation)
(check-numeric-edges)
(check-overlap)
(check-reference-elements)
(check-pair-fields)
(check-record-fields)
(check-captures)
(check-tags)
(check 1.75 (real-return 1.25))
(check 1099511627777 (integer-return 1099511627776))
(display "+!REPRESENTATION_COVERAGE!+#t") (newline)
