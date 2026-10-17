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

;;; FFT - Fast Fourier Transform, translated from "Numerical Recipes in C"

(define (four1 data)
  (let ((n (vector-length data))
        (pi*2 6.28318530717959)) ; to compute the inverse, negate this value

    ;; bit-reversal section

    (let loop1 ((i 0) (j 0))
      (when (< i n)
        (when (< i j)
          (let ((temp (vector-ref data i)))
            (vector-set! data i (vector-ref data j))
            (vector-set! data j temp))
          (let ((temp (vector-ref data (+ i 1))))
            (vector-set! data (+ i 1) (vector-ref data (+ j 1)))
            (vector-set! data (+ j 1) temp)))
        (let loop2 ((m (quotient n 2)) (j j))
          (if (and (>= m 2) (>= j m))
            (loop2 (quotient m 2) (- j m))
            (loop1 (+ i 2) (+ j m))))))

    ;; Danielson-Lanczos section

    (let loop3 ((mmax 2))
      (when (< mmax n)
        (let* ((theta
                (/ pi*2 (inexact mmax)))
               (wpr
                (let ((x (sin (* 0.5 theta))))
                  (* -2.0 (* x x))))
               (wpi
                (sin theta)))
          (let loop4 ((wr 1.0) (wi 0.0) (m 0))
            (when (< m mmax)
              (let loop5 ((i m))
                (if (< i n)
                  (let* ((j
                          (+ i mmax))
                         (tempr
                          (-
                            (* wr (vector-ref data j))
                            (* wi (vector-ref data (+ j 1)))))
                         (tempi
                          (+
                            (* wr (vector-ref data (+ j 1)))
                            (* wi (vector-ref data j)))))
                    (vector-set! data j
                      (- (vector-ref data i) tempr))
                    (vector-set! data (+ j 1)
                      (- (vector-ref data (+ i 1)) tempi))
                    (vector-set! data i
                      (+ (vector-ref data i) tempr))
                    (vector-set! data (+ i 1)
                      (+ (vector-ref data (+ i 1)) tempi))
                    (loop5 (+ j mmax)));***))
              (loop4 (+ (- (* wr wpr) (* wi wpi)) wr)
                     (+ (+ (* wi wpr) (* wr wpi)) wi)
                     (+ m 2))))
          ));******
          (loop3 (* mmax 2)))))))

(define data
  (make-vector 1024 0.0))

(define (run data)
  (four1 data)
  (vector-ref data 0))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "fft"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2)
     count
     (lambda ()
       (run (hide count (make-vector input1 input2))))
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
