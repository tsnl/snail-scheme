(import
  (only (chezscheme)
    port-closed?
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

; read-line is supplied by the same Scheme line builder.

(define (square x)
  (* x x))

; write-string is supplied by the same Scheme character loop.
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
(define (unit) (if #f #f))
(define (unreachable) (error 'tail "unreachable"))
(define i32-eq =)
(define i32->i64 values)
(define input-handle values)
(define ref-get values)
(define (end-of-file) (vector 0))
(define (line text) (vector 1 text))
(define (line-text value) (vector-ref value 1))
(define (line-eof? value) (= (vector-ref value 0) 0))
(define (port-read port)
  (let ((character (read-char port))) (if (eof-object? character) -1 (char->integer character))))
(define (port-peek port)
  (let ((character (peek-char port))) (if (eof-object? character) -1 (char->integer character))))
(define (string-copy! target at source start end)
  (let loop ((index start))
    (unless (= index end)
      (string-set! target (+ at (- index start)) (string-ref source index))
      (loop (+ index 1)))))
(define (read-line port)
      (let* ((handle (ref-get (input-handle port))) (code (port-read handle)))
        (if (i32-eq code (ann -1 I32)) (end-of-file)
            (line (read-line-text handle code (make-string 0) 0)))))
(define (consume-line-feed handle)
      (when (i32-eq (port-peek handle) (ann 10 I32)) (port-read handle) (unit)))
(define (read-line-text handle code buffer count)
      (if (or (i32-eq code (ann -1 I32))
              (i32-eq code (ann 10 I32)) (i32-eq code (ann 13 I32)))
          (begin
            (when (i32-eq code (ann 13 I32)) (consume-line-feed handle))
            (if (= count (string-length buffer)) buffer (substring buffer 0 count)))
          (let ((buffer (line-capacity buffer count)))
            (string-set! buffer count (integer->char (i32->i64 code)))
            (read-line-text handle (port-read handle) buffer (+ count 1)))))
(define (line-capacity buffer count)
      (if (< count (string-length buffer)) buffer
          (if (= count 4294967294) (unreachable)
              (let* ((size (if (= count 0) 64
                               (if (> count 2147483647) 4294967294 (* count 2))))
                     (grown (make-string size)))
                (string-copy! grown 0 buffer 0 count)
                grown))))
(define write-string
  (let ((output-handle values) (ref-get values))
    (define (port-check-output port)
      (unless (and (output-port? port) (not (port-closed? port)))
        (error 'write-string "expected an open output port")))
    (define (write-string-to text port)
      ;; Even an empty write checks direction and lifetime without emitting text.
      (port-check-output (ref-get (output-handle port)))
      (let ((count (string-length text)))
        (let loop ((index 0))
          (unless (= index count)
            (write-char (string-ref text index) port)
            (loop (+ index 1))))))
    write-string-to))
(: tail-for-each (All (T) (-> (-> T Unit) (List T) Unit)))
(define (tail-for-each procedure values)
  (unless (null? values)
    (procedure (car values))
    (tail-for-each procedure (cdr values))))
(: tail-r-aux (-> InputPort (List String) (List String)))
(: echo-lines-in-reverse-order (-> InputPort OutputPort Unit))
(: go (-> String String Unit))
;;; TAIL -- One of the Kernighan and Van Wyk benchmarks.
;;;
;;; Modified for R7RS by Will Clinger.
;;;
;;; The key idea of this benchmark is that, for each iteration,
;;; the entire input is read line by line before any output
;;; is produced, and the lines are then written to the output
;;; in the reverse of the order in which they were read.


(define (tail-r-aux port file-so-far)
  (let ((x (read-line port)))
    (if (line-eof? x)
        file-so-far
        (tail-r-aux port (cons (line-text x) file-so-far)))))

(define (echo-lines-in-reverse-order in out)
  (tail-for-each (lambda (line) (write-string line out) (newline out))
            (tail-r-aux in '())))

(define (go input output)
  (call-with-input-file
      input
    (lambda (in)
      (when (file-exists? output)
        (delete-file output))
      (call-with-output-file
          output
        (lambda (out)
          (echo-lines-in-reverse-order in out))))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read))
         (s3 (number->string count))
         (s2 input2)
         (s1 input1)
         (name "tail"))
    (run-r7rs-benchmark
     (string-append name ":" s3)
     count
     (lambda () (go (hide count input1) (hide count input2)))
     (lambda (result) #t))))

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
