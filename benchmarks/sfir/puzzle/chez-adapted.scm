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
(define (puzzle-failed) (vector 0))
(define (puzzle-count value) (vector 1 value))
(define puzzle-failure (puzzle-failed))
(define (puzzle-original-value result)
  (if (= (vector-ref result 0) 0) #f (vector-ref result 1)))
(define (puzzle-error) (newline) (display "Error."))
(define (puzzle-for-each procedure values)
  (unless (null? values)
    (procedure (car values)) (puzzle-for-each procedure (cdr values))))
;;; PUZZLE -- Forest Baskett's Puzzle benchmark, originally written in Pascal.


(define (my-iota n)
  (do ((n n (- n 1))
       (list '() (cons (- n 1) list)))
      ((zero? n) list)))

(define *size* 511)
(define classmax 3)
(define typemax 12)

(define *iii* (ref 0))
(define *kount* (ref 0))
(define *d* 8)

(define *piececount* (make-vector (+ classmax 1) 0))
(define *class* (make-vector (+ typemax 1) 0))
(define *piecemax* (make-vector (+ typemax 1) 0))
(define *puzzle* (make-vector (+ *size* 1) #t))
(define *p* (make-vector (+ typemax 1) (make-vector 0 #t)))

(define (fit i j)
  (let ((end (vector-ref *piecemax* i)))
    (do ((k 0 (+ k 1)))
        ((or (> k end)
             (and (vector-ref (vector-ref *p* i) k)
                  (vector-ref *puzzle* (+ j k))))
         (if (> k end) #t #f)))))

(define (place i j)
  (let ((end (vector-ref *piecemax* i)))
    (do ((k 0 (+ k 1)))
        ((> k end))
      (when (vector-ref (vector-ref *p* i) k)
        (vector-set! *puzzle* (+ j k) #t)))
    (vector-set! *piececount*
                 (vector-ref *class* i)
                 (- (vector-ref *piececount* (vector-ref *class* i)) 1))
    (do ((k j (+ k 1)))
        ((or (> k *size*) (not (vector-ref *puzzle* k)))
         (if (> k *size*) 0 k)))))

(define (puzzle-remove i j)
  (let ((end (vector-ref *piecemax* i)))
    (do ((k 0 (+ k 1)))
        ((> k end))
      (when (vector-ref (vector-ref *p* i) k)
        (vector-set! *puzzle* (+ j k) #f)))
    (vector-set! *piececount*
                 (vector-ref *class* i)
                 (+ (vector-ref *piececount* (vector-ref *class* i)) 1))))

(define (trial j)
  (let candidates ((i 0))
    (if (> i typemax)
        (begin (ref-set! *kount* (+ (ref-get *kount*) 1)) #f)
        (if (and (not (zero? (vector-ref *piececount* (vector-ref *class* i))))
                 (fit i j))
            (let ((k (place i j)))
              (if (or (trial k) (zero? k))
                  (begin (ref-set! *kount* (+ (ref-get *kount*) 1)) #t)
                  (begin (puzzle-remove i j) (candidates (+ i 1)))))
            (candidates (+ i 1))))))

(define (definePiece iclass ii jj kk)
  (let ((index (ref 0)))
    (do ((i 0 (+ i 1)))
        ((> i ii))
      (do ((j 0 (+ j 1)))
          ((> j jj))
        (do ((k 0 (+ k 1)))
            ((> k kk))
          (ref-set! index (+ i (* *d* (+ j (* *d* k)))))
          (vector-set! (vector-ref *p* (ref-get *iii*)) (ref-get index)  #t))))
    (vector-set! *class* (ref-get *iii*) iclass)
    (vector-set! *piecemax* (ref-get *iii*) (ref-get index))
    (when (not (= (ref-get *iii*) typemax))
      (ref-set! *iii* (+ (ref-get *iii*) 1)))))

(define (start size)
  (ref-set! *kount* 0)
  (do ((m 0 (+ m 1)))
      ((> m size))
    (vector-set! *puzzle* m #t))
  (do ((i 1 (+ i 1)))
      ((> i 5))
    (do ((j 1 (+ j 1)))
        ((> j 5))
      (do ((k 1 (+ k 1)))
          ((> k 5))
        (vector-set! *puzzle* (+ i (* *d* (+ j (* *d* k)))) #f))))
  (do ((i 0 (+ i 1)))
      ((> i typemax))
    (do ((m 0 (+ m 1)))
        ((> m size))
      (vector-set! (vector-ref *p* i) m #f)))
  (ref-set! *iii* 0)
  (definePiece 0 3 1 0)
  (definePiece 0 1 0 3)
  (definePiece 0 0 3 1)
  (definePiece 0 1 3 0)
  (definePiece 0 3 0 1)
  (definePiece 0 0 1 3)

  (definePiece 1 2 0 0)
  (definePiece 1 0 2 0)
  (definePiece 1 0 0 2)

  (definePiece 2 1 1 0)
  (definePiece 2 1 0 1)
  (definePiece 2 0 1 1)

  (definePiece 3 1 1 1)

  (vector-set! *piececount* 0 13)
  (vector-set! *piececount* 1 3)
  (vector-set! *piececount* 2 1)
  (vector-set! *piececount* 3 1)
  (let ((m (+ (* *d* (+ *d* 1)) 1))
        (n (ref 0)))
    (cond ((fit 0 m) (ref-set! n (place 0 m)))
          (else (puzzle-error)))
    (if (trial (ref-get n))
        (puzzle-count (ref-get *kount*))
        puzzle-failure)))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 input1)
         (name "puzzle"))
    (run-r7rs-benchmark
     (string-append name ":" s2)
     count
     (lambda () (start (hide count input1)))
     (lambda (result) (equal? result output)))))

(puzzle-for-each (lambda (i) (vector-set! *p* i (make-vector (+ *size* 1) #t)))
          (my-iota (+ typemax 1)))

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
               (result puzzle-failure))
      (cond ((< i count)
             (loop (+ i 1) (thunk)))
            ((ok? (puzzle-original-value result))
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
             (write (puzzle-original-value result))
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
