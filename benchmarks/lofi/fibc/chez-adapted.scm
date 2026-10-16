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

;;; FIBC -- FIB using first-class continuations, written by Kent Dybvig


;; ---- Captured Fibonacci operands ----

(r6rs:define-record-type (fibc-done done done?) (fields))
(r6rs:define-record-type (fibc-first first-operand first-operand?)
  (fields (immutable n first-n) (immutable next first-next)))
(r6rs:define-record-type (fibc-second second-operand second-operand?)
  (fields (immutable first second-first) (immutable next second-next)))

(define (capture current) current)
(define (succ n) (+ n 1))
(define (pred n) (- n 1))

(define (addc x y next)
  (if (= y 0) (resume next x) (addc (succ x) (pred y) next)))

(define (fibc x next)
  (if (= x 0)
      (resume next 0)
      (if (= (pred x) 0)
          (resume next 1)
          (fibc (pred x) (capture (first-operand x next))))))

(define (resume continuation value)
  (cond
    ((done? continuation) value)
    ((first-operand? continuation)
     (fibc (pred (pred (first-n continuation)))
           (capture (second-operand value (first-next continuation)))))
    (else (addc (second-first continuation) value (second-next continuation)))))

(define (run-benchmark)
  (let* ((count (read))
         (input (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input))
         (name "fibc"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2)
     count
     (lambda () (fibc (hide count input) (hide count (done))))
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
