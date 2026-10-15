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

(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define (simplex-infeasible) (vector 0))
(define (simplex-unbounded) (vector 1))
(define (simplex-solved values) (vector 2 values))
(define (simplex-original-value result)
  (case (vector-ref result 0)
    ((0) #f) ((1) #t) ((2) (vector-ref result 1))))
(define (unreachable) (error #f "This shouldn't happen"))
;;; SIMPLEX -- Simplex algorithm.


(define (matrix-rows a) (vector-length a))
(define (matrix-columns a) (vector-length (vector-ref a 0)))
(define (matrix-ref a i j) (vector-ref (vector-ref a i) j))
(define (matrix-set! a i j x) (vector-set! (vector-ref a i) j x))

(define (complain)
  (unreachable))

(define (simplex a m1 m2 m3)
                                        ;(define *epsilon* 1e-6)
  (define *epsilon* 0.000001)
  (unless (and (>= m1 0)
               (>= m2 0)
               (>= m3 0)
               (= (matrix-rows a) (+ m1 m2 m3 2)))
    (complain))
  (let* ((m12 (+ m1 m2 1))
         (m (- (matrix-rows a) 2))
         (n (- (matrix-columns a) 1))
         (l1 (make-vector n))
         (l2 (make-vector m))
         (l3 (make-vector m2))
         (nl1 (ref n))
         (iposv (make-vector m))
         (izrov (make-vector n))
         (ip (ref 0))
         (kp (ref 0))
         (bmax (ref 0.0))
         (one? (ref #f))
         (pass2? (ref #t)))
    (define (simp1 mm abs?)
      (ref-set! kp (vector-ref l1 0))
      (ref-set! bmax (matrix-ref a mm (ref-get kp)))
      (do ((k 1 (+ k 1))) ((>= k (ref-get nl1)))
        (when (positive?
               (if abs?
                   (- (abs (matrix-ref a mm (vector-ref l1 k)))
                      (abs (ref-get bmax)))
                   (- (matrix-ref a mm (vector-ref l1 k)) (ref-get bmax))))
          (begin
            (ref-set! kp (vector-ref l1 k))
            (ref-set! bmax (matrix-ref a mm (vector-ref l1 k)))))))
    (define (simp2)
      (ref-set! ip 0)
      (let ((q1 (ref 0.0))
            (flag? (ref #f)))
        (do ((i 0 (+ i 1))) ((= i m))
          (if (ref-get flag?)
              (when (< (matrix-ref a (vector-ref l2 i) (ref-get kp)) (- *epsilon*))
                (let ((q (/ (- (matrix-ref a (vector-ref l2 i) 0))
                            (matrix-ref a (vector-ref l2 i) (ref-get kp)))))
                  (cond
                   ((< q (ref-get q1))
                    (ref-set! ip (vector-ref l2 i))
                    (ref-set! q1 q))
                   ((= q (ref-get q1))
                    (let ((qp (ref 0.0))
                          (q0 (ref 0.0)))
                      (let loop ((k 1))
                        (if (<= k n)
                            (begin
                              (ref-set! qp
                                    (/ (- (matrix-ref a (ref-get ip) k))
                                       (matrix-ref a (ref-get ip) (ref-get kp))))
                              (ref-set! q0
                                    (/
                                     (-
                                      (matrix-ref a (vector-ref l2 i) k))
                                     (matrix-ref a (vector-ref l2 i) (ref-get kp))))
                              (if (= (ref-get q0) (ref-get qp))
                                  (loop (+ k 1))))))
                      (if (< (ref-get q0) (ref-get qp))
                          (ref-set! ip (vector-ref l2 i))))))))
              (when (< (matrix-ref a (vector-ref l2 i) (ref-get kp)) (- *epsilon*))
                (ref-set! q1 (/ (- (matrix-ref a (vector-ref l2 i) 0))
                            (matrix-ref a (vector-ref l2 i) (ref-get kp))))
                (ref-set! ip (vector-ref l2 i))
                (ref-set! flag? #t))))))
    (define (simp3 phase-one?)
      (let ((piv (/ (matrix-ref a (ref-get ip) (ref-get kp)))))
        (do ((ii 0 (+ ii 1))) ((= ii (+ m (if phase-one? 2 1))))
          (unless (= ii (ref-get ip))
            (matrix-set! a ii (ref-get kp) (* piv (matrix-ref a ii (ref-get kp))))
            (do ((kk 0 (+ kk 1))) ((= kk (+ n 1)))
              (unless (= kk (ref-get kp))
                (matrix-set!
                 a ii kk (- (matrix-ref a ii kk)
                            (* (matrix-ref a (ref-get ip) kk)
                               (matrix-ref a ii (ref-get kp)))))))))
        (do ((kk 0 (+ kk 1))) ((= kk (+ n 1)))
          (unless (= kk (ref-get kp))
            (matrix-set! a (ref-get ip) kk (* (- piv) (matrix-ref a (ref-get ip) kk)))))
        (matrix-set! a (ref-get ip) (ref-get kp) piv)))
    (do ((k 0 (+ k 1))) ((= k n))
      (vector-set! l1 k (+ k 1))
      (vector-set! izrov k k))
    (do ((i 0 (+ i 1))) ((= i m))
      (when (negative? (matrix-ref a (+ i 1) 0))
        (complain))
      (vector-set! l2 i (+ i 1))
      (vector-set! iposv i (+ n i)))
    (do ((i 0 (+ i 1))) ((= i m2)) (vector-set! l3 i #t))
    (when (positive? (+ m2 m3))
      (do ((k 0 (+ k 1))) ((= k (+ n 1)))
        (do ((i (+ m1 1) (+ i 1)) (sum 0.0 (+ sum (matrix-ref a i k))))
            ((> i m) (matrix-set! a (+ m 1) k (- sum)))))
      (let loop ()
        (simp1 (+ m 1) #f)
        (cond
         ((<= (ref-get bmax) *epsilon*)
          (cond ((< (matrix-ref a (+ m 1) 0) (- *epsilon*))
                 (ref-set! pass2? #f))
                ((<= (matrix-ref a (+ m 1) 0) *epsilon*)
                 (let loop ((ip1 m12))
                   (if (<= ip1 m)
                       (cond ((= (vector-ref iposv (- ip1 1)) (+ (ref-get ip) n -1))
                              (simp1 ip1 #t)
                              (cond ((positive? (ref-get bmax))
                                     (ref-set! ip ip1)
                                     (ref-set! one? #t))
                                    (else
                                     (loop (+ ip1 1)))))
                             (else
                              (loop (+ ip1 1))))
                       (do ((i (+ m1 1) (+ i 1))) ((>= i m12))
                         (when (vector-ref l3 (- i (+ m1 1)))
                           (do ((k 0 (+ k 1))) ((= k (+ n 1)))
                             (matrix-set!
                              a i k (- (matrix-ref a i k)))))))))
                (else
                 (simp2)
                 (if (zero? (ref-get ip)) (ref-set! pass2? #f) (ref-set! one? #t)))))
         (else (simp2) (if (zero? (ref-get ip)) (ref-set! pass2? #f) (ref-set! one? #t))))
        (when (ref-get one?)
          (ref-set! one? #f)
          (simp3 #t)
          (cond
           ((>= (vector-ref iposv (- (ref-get ip) 1)) (+ n m12 -1))
            (let loop ((k 0))
              (cond
               ((and (< k (ref-get nl1)) (not (= (ref-get kp) (vector-ref l1 k))))
                (loop (+ k 1)))
               (else
                (ref-set! nl1 (- (ref-get nl1) 1))
                (do ((is k (+ is 1))) ((>= is (ref-get nl1)))
                  (vector-set! l1 is (vector-ref l1 (+ is 1))))
                (matrix-set!
                 a (+ m 1) (ref-get kp) (+ (matrix-ref a (+ m 1) (ref-get kp)) 1.0))
                (do ((i 0 (+ i 1))) ((= i (+ m 2)))
                  (matrix-set! a i (ref-get kp) (- (matrix-ref a i (ref-get kp)))))))))
           ((and (>= (vector-ref iposv (- (ref-get ip) 1)) (+ n m1))
                 (vector-ref l3
                             (- (vector-ref iposv (- (ref-get ip) 1)) (+ m1 n))))
            (vector-set! l3 (- (vector-ref iposv (- (ref-get ip) 1)) (+ m1 n)) #f)
            (matrix-set!
             a (+ m 1) (ref-get kp) (+ (matrix-ref a (+ m 1) (ref-get kp)) 1.0))
            (do ((i 0 (+ i 1))) ((= i (+ m 2)))
              (matrix-set! a i (ref-get kp) (- (matrix-ref a i (ref-get kp)))))))
          (let ((t (vector-ref izrov (- (ref-get kp) 1))))
            (vector-set! izrov (- (ref-get kp) 1) (vector-ref iposv (- (ref-get ip) 1)))
            (vector-set! iposv (- (ref-get ip) 1) t))
          (loop))))
    (if (ref-get pass2?)
         (let loop ()
           (simp1 0 #f)
           (cond
            ((positive? (ref-get bmax))
             (simp2)
             (cond ((zero? (ref-get ip)) (simplex-unbounded))
                   (else (simp3 #f)
                         (let ((t (vector-ref izrov (- (ref-get kp) 1))))
                           (vector-set! izrov
                                        (- (ref-get kp) 1) (vector-ref iposv (- (ref-get ip) 1)))
                           (vector-set! iposv (- (ref-get ip) 1) t))
                         (loop))))
            (else (simplex-solved (list iposv izrov)))))
         (simplex-infeasible))))

(define (test input)
  (simplex (vector (vector 0.0 1.0 1.0 3.0 -0.5)
                   (vector 740.0 -1.0 0.0 -2.0 0.0)
                   (vector 0.0 0.0 -2.0 0.0 7.0)
                   (vector 0.5 0.0 -1.0 1.0 -2.0)
                   (vector 9.0 -1.0 -1.0 -1.0 -1.0)
                   (vector 0.0 0.0 0.0 0.0 0.0))
           2 1 1))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 "")
         (name "simplex"))
    (run-r7rs-benchmark
     (string-append name ":" s2)
     count
     (lambda () (test (hide count input1)))
     (lambda (result) (equal? (simplex-original-value result) output)))))

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
