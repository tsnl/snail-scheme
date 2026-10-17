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

;; This is probably from Lars Hansen's MS thesis.
;; The quick-1 benchmark.  (Figure 35, page 132.)


(define (quick-1 v less?)

  (define (helper left right)
    (if (< left right)
        (let ((median (partition v left right less?)))
          (if (< (- median left) (- right median))
              (begin (helper left (- median 1))
                     (helper (+ median 1) right))
              (begin (helper (+ median 1) right)
                     (helper left (- median 1)))))
        v))

  (helper 0 (- (vector-length v) 1)))


(define (partition v left right less?)
  (let ((mid (vector-ref v right)))

    (define (uploop i)
      (let ((i (+ i 1)))
        (if (and (< i right) (less? (vector-ref v i) mid))
            (uploop i)
            i)))

    (define (downloop j)
      (let ((j (- j 1)))
        (if (and (> j left) (less? mid (vector-ref v j)))
            (downloop j)
            j)))

    (define (ploop i j)
      (let* ((i (uploop i))
             (j (downloop j)))
        (let ((tmp (vector-ref v i)))
          (vector-set! v i (vector-ref v j))
          (vector-set! v j tmp)
          (if (< i j)
              (ploop i j)
              (begin (vector-set! v j (vector-ref v i))
                     (vector-set! v i (vector-ref v right))
                     (vector-set! v right tmp)
                     i)))))

    (ploop (- left 1) right)))

;;; Hansen's original code for this benchmark used Larceny's
;;; predefined random procedure.  When Marc Feeley modified
;;; Hansen's benchmark for the Gambit benchmark suite, however,
;;; he added a specific random number generator taken from an
;;; article in CACM.  Feeley's generator used bignums, and was
;;; extremely slow, causing the Gambit version of this benchmark
;;; to spend nearly all of its time generating the random numbers.
;;; For a benchmark called quicksort to become a bignum benchmark
;;; was very misleading, so Clinger left Feeley's version of this
;;; benchmark out of the Larceny benchmark suite.
;;;
;;; The following random number generator is much better and
;;; faster than the one used in the Gambit benchmark.  See
;;;
;;; http://srfi.schemers.org/srfi-27/mail-archive/msg00000.html
;;; http://www.math.purdue.edu/~lucier/random/random.scm

;;; A uniform [0,1] random number generator; is
;;; Pierre L'Ecuyer's generator from his paper
;;; "Good parameters and implementations for combined multiple
;;; recursive random number generators"
;;; available at his web site http://www.iro.umontreal.ca/~lecuyer

(define seed-set! #f)
(define seed-ref #f)
(define random-flonum #f)

(let ((norm 2.328306549295728e-10)
      (m1 4294967087.0)
      (m2 4294944443.0)
      (a12 1403580.0)
      (a13n 810728.0)
      (a21 527612.0)
      (a23n 1370589.0)
      (seed (vector 1.0 0.0 0.0 1.0 0.0 0.0)));; will be mutated

  ;; uses no conversions between flonums and fixnums.

  (set! random-flonum
        (lambda ()
          (let ((seed seed));; make it local
            (let ((p1 (- (* a12 (vector-ref seed 1))
                         (* a13n (vector-ref seed 0))))
                  (p2 (- (* a21 (vector-ref seed 5))
                         (* a23n (vector-ref seed 3)))))
              (let ((k1 (truncate (/ p1 m1)))
                    (k2 (truncate (/ p2 m2)))
                    (ignore1 (vector-set! seed 0 (vector-ref seed 1)))
                    (ignore3 (vector-set! seed 3 (vector-ref seed 4))))
                (let ((p1 (- p1 (* k1 m1)))
                      (p2 (- p2 (* k2 m2)))
                      (ignore2 (vector-set! seed 1 (vector-ref seed 2)))
                      (ignore4 (vector-set! seed 4 (vector-ref seed 5))))
                  (let ((p1 (if (< p1 0.0) (+ p1 m1) p1))
                        (p2 (if (< p2 0.0) (+ p2 m2) p2)))
                    (vector-set! seed 2 p1)
                    (vector-set! seed 5 p2)
                    (if (<= p1 p2)
                        (* norm (+ (- p1 p2) m1))
                        (* norm (- p1 p2))))))))))

  (set! seed-ref (lambda () (vector->list seed)))

  (set! seed-set! (lambda l (set! seed (list->vector l)))))

(define (random n)
  (exact (truncate (* (inexact n) (random-flonum)))))

;;; Even with the improved random number generator,
;;; this benchmark still spends almost all of its time
;;; generating the random vector.  To make this a true
;;; quicksort benchmark, we generate a relatively small
;;; random vector and then sort many copies of it.

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read))
         (s3 (number->string count))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "quicksort")
         (n (hide count input1))
         (r (hide count input2))
         (less? (hide count (lambda (x y) (< x y))))
         (v (make-vector n)))
    (do ((i 0 (+ i 1)))
        ((= i n))
      (vector-set! v i (random r)))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s3)
     count
     (lambda () (quick-1 (vector-map values v) less?))
     (lambda (v)
       (call-with-current-continuation
        (lambda (return)
          (do ((i 1 (+ i 1)))
              ((= i (vector-length v))
               #t)
            (unless (<= (vector-ref v (- i 1))
                        (vector-ref v i))
              (return #f)))))))))

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
