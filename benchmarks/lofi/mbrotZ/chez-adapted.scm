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

(define (complex64 real imag) (vector real imag))
(define (complex64-real value) (vector-ref value 0))
(define (complex64-imag value) (vector-ref value 1))
(define (i64->f64 value) (inexact value))
(define (complex64-add left right)
  (complex64 (+ (complex64-real left) (complex64-real right))
             (+ (complex64-imag left) (complex64-imag right))))
(define (complex64-scale value scale)
  (complex64 (* (complex64-real value) scale)
             (* (complex64-imag value) scale)))
(define (complex64-multiply left right)
  (let ((a (complex64-real left)) (b (complex64-imag left))
        (c (complex64-real right)) (d (complex64-imag right)))
    (complex64 (- (* a c) (* b d)) (+ (* a d) (* b c)))))
(define mbrot-z-origin (complex64 -1.0 -0.5))
(define mbrot-empty-row (make-vector 0 0))
;;; MBROT -- Generation of Mandelbrot set fractal
;;; using Scheme's complex numbers.


(define (count z0 step z)

  (let* ((max-count 64)
         (radius    4.0)
         (radius^2  (* radius radius)))

    (let ((z0 (complex64-add z0 (complex64-scale z step))))

      (let loop ((z z0)
                 (c 0))
        (if (= c max-count)
            c
            (let* ((zr (complex64-real z))
                   (zi (complex64-imag z))
                   (zr^2 (* zr zr))
                   (zi^2 (* zi zi)))
              (if (> (+ zr^2 zi^2) radius^2)
                  c
                  (loop (complex64-add (complex64-multiply z z) z0) (+ c 1)))))))))

(define (mbrot matrix z0 step n)
  (let loop1 ((y (- n 1)))
    (when (>= y 0)
        (let loop2 ((x (- n 1)))
          (if (>= x 0)
            (begin
              (vector-set! (vector-ref matrix x)
                            y
                            (count z0
                                   step
                                   (complex64 (i64->f64 x)
                                                     (i64->f64 y))))
              (loop2 (- x 1)))
            (loop1 (- y 1)))))))

(define (test n)
  (let ((matrix (make-vector n mbrot-empty-row)))
    (let loop ((i (- n 1)))
      (when (>= i 0)
        (vector-set! matrix i (make-vector n 0))
        (loop (- i 1))))
    (mbrot matrix mbrot-z-origin 0.005 n)
    (vector-ref (vector-ref matrix 0) 0)))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "mbrotZ"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2)
     count
     (lambda () (test (hide count input1)))
     (lambda (result) (= result output)))))

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
