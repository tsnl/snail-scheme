(import
  (only (chezscheme)
    current-time
    machine-type
    scheme-version-number
    time-nanosecond
    time-second)
  (except
    (rename (rnrs) (define-record-type r6rs:define-record-type))
    bitwise-and
    bitwise-not
    div
    mod
    partition)
  (rnrs mutable-pairs)
  (rnrs mutable-strings)
  (rnrs r5rs))

(define-syntax define-record-type
  ;; Simplistic R7RS to R6RS define-record-type transformation.
  (syntax-rules ()
    ((define-record-type name
      (make-name param ...)
      name?
      (field-name field-ref field-set!)
      ...)
     (r6rs:define-record-type (name make-name name?)
       (protocol
         (lambda (new)
           (lambda (param ...)
             (new param ...))))
       (fields
         (mutable field-name field-ref field-set!)
         ...)))))

(define (exact-integer? z)
  (and (exact? z) (integer? z)))

 (define read-line
   get-line)

(define (square x)
  (* x x))

(define write-string
  (case-lambda
    ((string)
      (put-string (current-output-port) string))
    ((string port)
      (put-string port string))
    ((string port start)
      (put-string port string start))
    ((string port start end)
      (put-string port string start (fx+ (fx- end start) 1)))))
;; R7RS benchmark timing for compiled Chez programs. The upstream Petite-Chez
;; prelude supplies language compatibility; the benchmark body is unchanged.
;; Use Chez's monotonic clock and integer nanoseconds, not two wall-clock reads.

(define (current-jiffy)
  (let ((now (current-time 'time-monotonic)))
    (+ (* (time-second now) 1000000000) (time-nanosecond now))))

(define (jiffies-per-second) 1000000000)

(define (current-second)
  (/ (current-jiffy) 1000000000.0))

(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define (unit) (if #f #f))
(define bv-display display)
(define bv-newline newline)
(: bv-same-bool? (-> Bool Bool Bool))
(define (bv-same-bool? actual expected) (if actual expected (not expected)))
(define (bv-zero? value) (= value 0))
(define (bv-odd? value) (not (= (remainder value 2) 0)))
;; The generator supplies a nonnegative integer. Rational round(n/4) chooses
;; the even quotient at a tie: 2 -> 0, 6 -> 2, 10 -> 2, 14 -> 4.
(define (bv-round-quarter value)
  (let ((whole (quotient value 4)) (part (remainder value 4)))
    (if (or (> part 2) (and (= part 2) (bv-odd? whole))) (+ whole 1) whole)))
(: test (-> String Bool Bool Unit))
(: string-bytevector-tests (-> I64 I64 Unit))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Copyright 2007 William D Clinger.
;;
;; Permission to copy this software, in whole or in part, to use this
;; software for any lawful purpose, and to redistribute this software
;; is granted subject to the restriction that all copies made of this
;; software must include this copyright notice in full.
;;
;; I also request that you send me a copy of any improvements that you
;; make to this software so that they may be incorporated within it to
;; the benefit of the Scheme community.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Tests of string <-> bytevector conversions.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; Crude test rig, just for benchmarking.

(define failed-tests (ref (ann '() (List String))))

(define (test name actual expected)
  (unless (bv-same-bool? actual expected)
    (bv-display "******** FAILED TEST ******** ")
    (bv-display name)
    (bv-newline)
    (ref-set! failed-tests (cons name (ref-get failed-tests)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; We're limited to Ascii strings here because the R7RS doesn't
;; actually require anything beyond Ascii.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Basic sanity tests, followed by stress tests on random inputs.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (string-bytevector-tests
         *random-stress-tests* *random-stress-test-max-size*)

  (define (test-roundtrip bvec tostring tobvec)
    (let* ((s1 (tostring bvec))
           (b2 (tobvec s1))
           (s2 (tostring b2)))
      (test "round trip of string conversion" (string=? s1 s2) #t)))

  ;; This random number generator doesn't have to be good.
  ;; It just has to be fast.

  (define random
    (letrec ((random14
              (lambda (n)
                (ref-set! x (remainder (+ (* a (ref-get x)) c) (+ m 1)))
                (remainder (quotient (ref-get x) 8) n)))
             (a 701)
             (x (ref 1))
             (c 743483)
             (m 524287)
             (loop
              (lambda (q r n)
                (if (bv-zero? q)
                    (remainder r n)
                    (loop (quotient q 16384)
                          (+ (* 16384 r) (random14 16384))
                          n)))))
      (lambda (n)
        (if (< n 16384)
            (random14 n)
            (loop (quotient n 16384) (random14 16384) n)))))

  ;; Returns a random bytevector of length up to n,
  ;; with all elements less than 128.

  (define (random-bytevector n)
    (let* ((n (random n))
           (bv (make-bytevector n)))
      (do ((i 0 (+ i 1)))
          ((= i n) bv)
        (bytevector-u8-set! bv i (random 128)))))

  ;; Returns a random bytevector of even length up to n.

  (define (random-bytevector2 n)
    (let* ((n (random n))
           (n (if (bv-odd? n) (+ n 1) n))
           (bv (make-bytevector n)))
      (do ((i 0 (+ i 1)))
          ((= i n) bv)
        (bytevector-u8-set! bv i (random 128)))))

  ;; Returns a random bytevector of multiple-of-4 length up to n.

  (define (random-bytevector4 n)
    (let* ((n (random n))
           (n (* 4 (bv-round-quarter n)))
           (bv (make-bytevector n)))
      (do ((i 0 (+ i 1)))
          ((= i n) bv)
        (bytevector-u8-set! bv i (random 128)))))

  (test-roundtrip (random-bytevector 10) utf8->string string->utf8)

  (do ((i 0 (+ i 1)))
      ((= i *random-stress-tests*) (unit))
    (test-roundtrip (random-bytevector *random-stress-test-max-size*)
                    utf8->string string->utf8))

  )

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read))
         (s3 (number->string count))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "bv2string"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2 ":" s3)
     count
     (lambda ()
       (string-bytevector-tests (hide count input1) (hide count input2))
       (length (ref-get failed-tests)))
     (lambda (result) (equal? result output)))))

(define (this-scheme-implementation-name) "chez")

;;; The following code is appended to all benchmarks.

;;; Given an integer and an object, returns the object
;;; without making it too easy for compilers to tell
;;; the object will be returned.

(define (hide r x)
  (call-with-values
   (lambda ()
     (values (vector values (lambda (x) x))
             (if (< r 100) 0 1)))
   (lambda (v i)
     ((vector-ref v i) x))))

;;; Given the name of a benchmark,
;;; the number of times it should be executed,
;;; a thunk that runs the benchmark once,
;;; and a unary predicate that is true of the
;;; correct results the thunk may return,
;;; runs the benchmark for the number of specified iterations.

(define (run-r7rs-benchmark name count thunk ok?)

  ;; Rounds to thousandths.
  (define (rounded x)
    (/ (round (* 1000 x)) 1000))

  (display "Running ")
  (display name)
  (newline)
  (flush-output-port (current-output-port))
  (let* ((j/s (jiffies-per-second))
         (t0 (current-second))
         (j0 (current-jiffy)))
    (let loop ((i 0)
               (result #f))
      (cond ((< i count)
             (loop (+ i 1) (thunk)))
            ((ok? result)
             (let* ((t1 (current-second))
                    (j1 (current-jiffy))
                    (jifs (- j1 j0))
                    (secs (inexact (/ jifs j/s)))
                    (secs2 (rounded (- t1 t0))))
               (display "Elapsed time: ")
               (write secs)
               (display " seconds (")
               (write secs2)
               (display ") for ")
               (display name)
               (newline)
               (display "+!CSVLINE!+")
               (display (this-scheme-implementation-name))
               (display ",")
               (display name)
               (display ",")
               (display secs)
               (newline)
               (flush-output-port (current-output-port)))
             0)
            (else
             (display "ERROR: returned incorrect result: ")
             (write result)
             (newline)
             (display "+!CSVLINE!+")
             (display (this-scheme-implementation-name))
             (display ",")
             (display name)
             (display ",")
             (display "INCORRECT")
             (newline)
             (flush-output-port (current-output-port))
             0)))))

(run-benchmark)
