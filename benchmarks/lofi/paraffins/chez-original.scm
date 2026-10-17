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

;;; PARAFFINS -- Compute how many paraffins exist with N carbon atoms.


(define (gen n)
  (let* ((n/2 (quotient n 2))
         (radicals (make-vector (+ n/2 1) '(H))))

    (define (rads-of-size n)
      (let loop1 ((ps
                   (three-partitions (- n 1)))
                  (lst
                   '()))
        (if (null? ps)
            lst
            (let* ((p (car ps))
                   (nc1 (vector-ref p 0))
                   (nc2 (vector-ref p 1))
                   (nc3 (vector-ref p 2)))
              (let loop2 ((rads1
                           (vector-ref radicals nc1))
                          (lst
                           (loop1 (cdr ps)
                                  lst)))
                (if (null? rads1)
                    lst
                    (let loop3 ((rads2
                                 (if (= nc1 nc2)
                                     rads1
                                     (vector-ref radicals nc2)))
                                (lst
                                 (loop2 (cdr rads1)
                                        lst)))
                      (if (null? rads2)
                          lst
                          (let loop4 ((rads3
                                       (if (= nc2 nc3)
                                           rads2
                                           (vector-ref radicals nc3)))
                                      (lst
                                       (loop3 (cdr rads2)
                                              lst)))
                            (if (null? rads3)
                                lst
                                (cons (vector 'C
                                              (car rads1)
                                              (car rads2)
                                              (car rads3))
                                      (loop4 (cdr rads3)
                                             lst))))))))))))

    (define (bcp-generator j)
      (if (odd? j)
          '()
          (let loop1 ((rads1
                       (vector-ref radicals (quotient j 2)))
                      (lst
                       '()))
            (if (null? rads1)
                lst
                (let loop2 ((rads2
                             rads1)
                            (lst
                             (loop1 (cdr rads1)
                                    lst)))
                  (if (null? rads2)
                      lst
                      (cons (vector 'BCP
                                    (car rads1)
                                    (car rads2))
                            (loop2 (cdr rads2)
                                   lst))))))))

    (define (ccp-generator j)
      (let loop1 ((ps
                   (four-partitions (- j 1)))
                  (lst
                   '()))
        (if (null? ps)
            lst
            (let* ((p (car ps))
                   (nc1 (vector-ref p 0))
                   (nc2 (vector-ref p 1))
                   (nc3 (vector-ref p 2))
                   (nc4 (vector-ref p 3)))
              (let loop2 ((rads1
                           (vector-ref radicals nc1))
                          (lst
                           (loop1 (cdr ps)
                                  lst)))
                (if (null? rads1)
                    lst
                    (let loop3 ((rads2
                                 (if (= nc1 nc2)
                                     rads1
                                     (vector-ref radicals nc2)))
                                (lst
                                 (loop2 (cdr rads1)
                                        lst)))
                      (if (null? rads2)
                          lst
                          (let loop4 ((rads3
                                       (if (= nc2 nc3)
                                           rads2
                                           (vector-ref radicals nc3)))
                                      (lst
                                       (loop3 (cdr rads2)
                                              lst)))
                            (if (null? rads3)
                                lst
                                (let loop5 ((rads4
                                             (if (= nc3 nc4)
                                                 rads3
                                                 (vector-ref radicals nc4)))
                                            (lst
                                             (loop4 (cdr rads3)
                                                    lst)))
                                  (if (null? rads4)
                                      lst
                                      (cons (vector 'CCP
                                                    (car rads1)
                                                    (car rads2)
                                                    (car rads3)
                                                    (car rads4))
                                            (loop5 (cdr rads4)
                                                   lst))))))))))))))

    (let loop ((i 1))
      (if (> i n/2)
          (vector (bcp-generator n)
                  (ccp-generator n))
          (begin
            (vector-set! radicals i (rads-of-size i))
            (loop (+ i 1)))))))

(define (three-partitions m)
  (let loop1 ((lst '())
              (nc1 (quotient m 3)))
    (if (< nc1 0)
        lst
        (let loop2 ((lst lst)
                    (nc2 (quotient (- m nc1) 2)))
          (if (< nc2 nc1)
              (loop1 lst
                     (- nc1 1))
              (loop2 (cons (vector nc1 nc2 (- m (+ nc1 nc2))) lst)
                     (- nc2 1)))))))

(define (four-partitions m)
  (let loop1 ((lst '())
              (nc1 (quotient m 4)))
    (if (< nc1 0)
        lst
        (let loop2 ((lst lst)
                    (nc2 (quotient (- m nc1) 3)))
          (if (< nc2 nc1)
              (loop1 lst
                     (- nc1 1))
              (let ((start (max nc2 (- (quotient (+ m 1) 2) (+ nc1 nc2)))))
                (let loop3 ((lst lst)
                            (nc3 (quotient (- m (+ nc1 nc2)) 2)))
                  (if (< nc3 start)
                      (loop2 lst (- nc2 1))
                      (loop3 (cons (vector nc1 nc2 nc3 (- m (+ nc1 (+ nc2 nc3)))) lst)
                             (- nc3 1))))))))))

(define (nb n)
  (let ((x (gen n)))
    (+ (length (vector-ref x 0))
       (length (vector-ref x 1)))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "paraffins"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2)
     count
     (lambda () (nb (hide count input1)))
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
