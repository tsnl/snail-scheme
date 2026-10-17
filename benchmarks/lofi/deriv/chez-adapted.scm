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

(define (datum-tag value) (vector-ref value 0))
(define (datum-pair? value) (= (datum-tag value) 4))
(define (datum-null? value) (= (datum-tag value) 2))
(define (make-datum-number value) (vector 3 value))
(define (datum-cons first rest) (vector 4 first rest))
(define (datum-number-value value)
  (if (= (datum-tag value) 3) (vector-ref value 1) (error #f "not a number datum")))
(define (datum-car value)
  (if (= (datum-tag value) 4) (vector-ref value 1) (error #f "not a pair datum")))
(define (datum-cdr value)
  (if (= (datum-tag value) 4) (vector-ref value 2) (error #f "not a pair datum")))
(define (unreachable) (error #f "No derivation method available"))
(define (make-datum-false) (vector 0))
(define (make-datum-true) (vector 1))
(define (make-datum-empty) (vector 2))
(define (make-datum-x) (vector 5))
(define (make-datum-a) (vector 6))
(define (make-datum-b) (vector 7))
(define (make-datum-plus) (vector 8))
(define (make-datum-minus) (vector 9))
(define (make-datum-times) (vector 10))
(define (make-datum-divide) (vector 11))
(define datum-false (make-datum-false))
(define datum-true (make-datum-true))
(define datum-empty (make-datum-empty))
(define datum-x (make-datum-x))
(define datum-a (make-datum-a))
(define datum-b (make-datum-b))
(define datum-plus (make-datum-plus))
(define datum-minus (make-datum-minus))
(define datum-times (make-datum-times))
(define datum-divide (make-datum-divide))
(define datum-zero (make-datum-number 0))
(define datum-one (make-datum-number 1))
(define (datum-x? value) (= (datum-tag value) 5))
(define (datum-a? value) (= (datum-tag value) 6))
(define (datum-b? value) (= (datum-tag value) 7))
(define (datum-plus? value) (= (datum-tag value) 8))
(define (datum-minus? value) (= (datum-tag value) 9))
(define (datum-times? value) (= (datum-tag value) 10))
(define (datum-divide? value) (= (datum-tag value) 11))
(define (datum-cadr value) (datum-car (datum-cdr value)))
(define (datum-caddr value) (datum-car (datum-cdr (datum-cdr value))))
(define (datum-list3 a b c)
  (datum-cons a (datum-cons b (datum-cons c datum-empty))))
(define (datum-list4 a b c d)
  (datum-cons a (datum-cons b (datum-cons c (datum-cons d datum-empty)))))
(define (datum-map f values)
  (if (datum-null? values) datum-empty
      (datum-cons (f (datum-car values)) (datum-map f (datum-cdr values)))))
(define (datum-equal? left right)
  (let ((tag (datum-tag left)))
    (and (= tag (datum-tag right))
         (cond ((= tag 3) (= (datum-number-value left) (datum-number-value right)))
               ((= tag 4) (and (datum-equal? (datum-car left) (datum-car right))
                              (datum-equal? (datum-cdr left) (datum-cdr right))))
               (else #t)))))
(define (datum-from-scheme value)
  (cond ((pair? value) (datum-cons (datum-from-scheme (car value)) (datum-from-scheme (cdr value))))
        ((integer? value) (make-datum-number value))
        ((equal? value '#f) datum-false)
        ((equal? value '#t) datum-true)
        ((equal? value '()) datum-empty)
        ((equal? value 'x) datum-x)
        ((equal? value 'a) datum-a)
        ((equal? value 'b) datum-b)
        ((equal? value '+) datum-plus)
        ((equal? value '-) datum-minus)
        ((equal? value '*) datum-times)
        ((equal? value '/) datum-divide)
        (else (error #f "datum outside deriv finite vocabulary"))))
;;; DERIV -- Symbolic derivation.


;;; Returns the wrong answer for quotients.
;;; Fortunately these aren't used in the benchmark.

(define (deriv a)
  (cond ((not (datum-pair? a))
         (if (datum-x? a) datum-one datum-zero))
        ((datum-plus? (datum-car a))
         (datum-cons datum-plus
               (datum-map deriv (datum-cdr a))))
        ((datum-minus? (datum-car a))
         (datum-cons datum-minus
               (datum-map deriv (datum-cdr a))))
        ((datum-times? (datum-car a))
         (datum-list3 datum-times
               a
               (datum-cons datum-plus
                     (datum-map (lambda (a) (datum-list3 datum-divide (deriv a) a)) (datum-cdr a)))))
        ((datum-divide? (datum-car a))
         (datum-list3 datum-minus
               (datum-list3 datum-divide
                     (deriv (datum-cadr a))
                     (datum-caddr a))
               (datum-list3 datum-divide
                     (datum-cadr a)
                     (datum-list4 datum-times
                           (datum-caddr a)
                           (datum-caddr a)
                           (deriv (datum-caddr a))))))
        (else
         (unreachable))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (datum-from-scheme (read)))
         (output (datum-from-scheme (read)))
         (s (number->string count))
         (name "deriv"))
    (run-r7rs-benchmark
     (string-append name ":" s)
     count
     (lambda () (deriv (hide count input1)))
     (lambda (result) (datum-equal? result output)))))

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
               (result datum-false))
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
