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
(define (ml-empty) '())
(define (ml-cons head tail) (cons (vector head) (vector tail)))
(define ml-null? null?)
(define (ml-car values) (vector-ref (car values) 0))
(define (ml-cdr values) (vector-ref (cdr values) 0))
(define (ml-set-car! values head) (vector-set! (car values) 0 head))
(define (ml-set-cdr! values tail) (vector-set! (cdr values) 0 tail))
(define empty-value (vector 0))
(define (integer-item value) (vector 1 value))
(define (item-empty? value) (= (vector-ref value 0) 0))
(define (item-value value) (vector-ref value 1))
(: ml-length (All (T) (-> (MutableList T) I64)))
(define (ml-length values)
  (let loop ((values values) (size 0))
    (if (ml-null? values) size (loop (ml-cdr values) (+ size 1)))))
(define (same-item? left right)
  (if (item-empty? left) (item-empty? right)
      (and (not (item-empty? right)) (= (item-value left) (item-value right)))))
(: same-row? (-> (MutableList Item) (List Item) Bool))
(define (same-row? actual expected)
  (if (ml-null? actual) (null? expected)
      (and (not (null? expected)) (same-item? (ml-car actual) (car expected))
           (same-row? (ml-cdr actual) (cdr expected)))))
(: same-rows? (-> (MutableList (MutableList Item)) (List (List Item)) Bool))
(define (same-rows? actual expected)
  (if (ml-null? actual) (null? expected)
      (and (not (null? expected)) (same-row? (ml-car actual) (car expected))
           (same-rows? (ml-cdr actual) (cdr expected)))))
(define (read-expected-item value)
  (if (null? value) empty-value (integer-item value)))
(define (read-expected-rows value)
  (and value (map (lambda (row) (map read-expected-item row)) value)))
(define (original-item value) (if (item-empty? value) '() (item-value value)))
(define (original-row row)
  (if (ml-null? row) '()
      (cons (original-item (ml-car row)) (original-row (ml-cdr row)))))
(define (original-rows rows)
  (if (ml-null? rows) '()
      (cons (original-row (ml-car rows)) (original-rows (ml-cdr rows)))))
(: append-to-tail! (All (T)
  (-> (MutableList T) (MutableList T) (MutableList T))))
(: destructive (-> I64 I64 (MutableList (MutableList Item))))
;;; DESTRUC -- Destructive operation benchmark.


(define (append-to-tail! x y)
  (if (ml-null? x)
      y
      (let loop ((a x) (b (ml-cdr x)))
        (if (ml-null? b)
            (begin
              (ml-set-cdr! a y)
              x)
            (loop b (ml-cdr b))))))

(define (destructive n m)
  (let ((l (do ((i 10 (- i 1)) (a (ml-empty) (ml-cons (ml-empty) a)))
               ((= i 0) a))))
    (do ((i n (- i 1)))
        ((= i 0) l)
      (cond ((ml-null? (ml-car l))
             (do ((l l (ml-cdr l)))
                 ((ml-null? l))
               (when (ml-null? (ml-car l))
                 (ml-set-car! l (ml-cons empty-value (ml-empty))))
               (append-to-tail! (ml-car l)
                                (do ((j m (- j 1)) (a (ml-empty) (ml-cons empty-value a)))
                                    ((= j 0) a)))))
            (else
             (do ((l1 l (ml-cdr l1)) (l2 (ml-cdr l) (ml-cdr l2)))
                 ((ml-null? l2))
               (let* ((destruc-suffix (let ((n (quotient (ml-length (ml-car l1)) 2)))
                           (cond ((= n 0)
                                  (ml-set-car! l1 (ml-empty))
                                  (ml-car l1))
                                 (else
                                  (do ((j n (- j 1)) (a (ml-car l1) (ml-cdr a)))
                                      ((= j 1)
                                       (let ((x (ml-cdr a)))
                                         (ml-set-cdr! a (ml-empty))
                                         x))
                                    (ml-set-car! a (integer-item i)))))))
                         (destruc-target (do ((j (quotient (ml-length (ml-car l2)) 2) (- j 1))
                              (a (ml-car l2) (ml-cdr a)))
                             ((zero? j) a)
                           (ml-set-car! a (integer-item i)))))
                 (ml-set-cdr! destruc-target destruc-suffix))))))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read-expected-rows (read)))
         (s3 (number->string count))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "destruc"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2 ":" s3)
     count
     (lambda ()
       (destructive (hide count input1) (hide count input2)))
     (lambda (result) (if result (and output (same-rows? result output)) (not output))))))

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
             (write (and result (original-rows result)))
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
