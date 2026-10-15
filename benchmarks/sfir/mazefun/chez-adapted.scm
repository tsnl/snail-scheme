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
(define wall-value (vector 0))
(define (coordinate row column) (vector 1 row column))
(define (open-cell? value) (= (vector-ref value 0) 1))
(define (coordinate-row value) (vector-ref value 1))
(define (coordinate-column value) (vector-ref value 2))
(define (dimensions rows columns) (vector rows columns))
(define (dimension-rows value) (vector-ref value 0))
(define (dimension-columns value) (vector-ref value 1))
(define maze-initial-value (vector 0))
(define maze-error-value (vector 1))
(define maze-other-value (vector 3))
(define (maze-grid rows) (vector 2 rows))
(define (maze-kind value) (vector-ref value 0))
(define (maze-rows value) (vector-ref value 1))
;; Position lists contain Coordinate values by construction. Writes
;; share that same label; they never add a cell wrapper or copy its coordinates.
(define (same-bool? left right) (if left right (not right)))
(define (maze-even? value) (= (remainder value 2) 0))
(define (maze-odd? value) (not (maze-even? value)))
(define (same-cavity? left right)
  (if (open-cell? left)
      (and (open-cell? right) (= (coordinate-row left) (coordinate-row right))
           (= (coordinate-column left) (coordinate-column right)))
      (not (open-cell? right))))
(define (cavity-member? value values)
  (and (not (null? values))
       (or (same-cavity? value (car values)) (cavity-member? value (cdr values)))))
(: singleton (All (T) (-> T (List T))))
(define (singleton value) (cons value '()))
(: append-two (All (T) (-> (List T) (List T) (List T))))
(define (append-two first last)
  (if (null? first) last (cons (car first) (append-two (cdr first) last))))
(: append-four (All (T) (-> (List T) (List T) (List T) (List T) (List T))))
(define (append-four first second third last)
  (append-two first (append-two second (append-two third last))))
(: maze-map (All (A B) (-> (-> A B) (List A) (List B))))
(define (maze-map procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (maze-map procedure (cdr values))))))
(define (same-row? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-bool? (car left) (car right))
           (same-row? (cdr left) (cdr right)))))
(define (same-grid? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-row? (car left) (car right))
           (same-grid? (cdr left) (cdr right)))))
(define (same-maze? actual expected)
  (and (= (maze-kind actual) (maze-kind expected))
       (if (= (maze-kind actual) 2) (same-grid? (maze-rows actual) (maze-rows expected))
           (not (= (maze-kind actual) 3)))))
(define (maze-mark? value) (or (eq? value '_) (eq? value '*)))
(define (maze-row? value) (and (list? value) (for-all maze-mark? value)))
(define (maze-grid? value) (and (list? value) (for-all maze-row? value)))
(define (maze-expected-kind value)
  (cond ((eq? value #f) 0) ((eq? value 'error) 1)
        ((maze-grid? value) 2) (else 3)))
(define (read-expected-maze value)
  (case (maze-expected-kind value)
    ((0) maze-initial-value) ((1) maze-error-value)
    ((2) (maze-grid (maze-map (lambda (row) (maze-map (lambda (mark) (eq? mark '_)) row)) value)))
    (else maze-other-value)))
(define (original-maze value)
  (case (maze-kind value)
    ((0) #f) ((1) 'error)
    ((2) (maze-map (lambda (row) (maze-map (lambda (mark) (if mark '_ '*)) row)) (maze-rows value)))
    (else (error 'mazefun "impossible actual result"))))
(: foldr (All (A B) (-> (-> A B B) B (List A) B)))
(: foldl (All (A B) (-> (-> B A B) B (List A) B)))
(: for (All (T) (-> I64 I64 (-> I64 T) (List T))))
(: concat (All (T) (-> (List (List T)) (List T))))
(: list-read (All (T) (-> (List T) I64 T)))
(: list-write (All (T) (-> (List T) I64 T (List T))))
(: list-remove-pos (All (T) (-> (List T) I64 (List T))))
(: make-matrix (All (T) (-> I64 I64 (-> I64 I64 T) (List (List T)))))
(: matrix-read (All (T) (-> (List (List T)) I64 I64 T)))
(: matrix-write (All (T) (-> (List (List T)) I64 I64 T (List (List T)))))
(: matrix-size (All (T) (-> (List (List T)) Dimensions)))
(: matrix-map (All (A B) (-> (-> A B) (List (List A)) (List (List B)))))
(: shuffle (All (T) (-> (List T) (List T))))
(: shuffle-aux (All (T) (-> (List T) I64 (List T))))
(: make-maze (-> I64 I64 MazeResult))
;;; MAZEFUN -- Constructs a maze in a purely functional way,
;;; written by Marc Feeley.


(define foldr
  (lambda (f base lst)
    (define foldr-aux
      (lambda (lst)
        (if (null? lst)
            base
            (f (car lst) (foldr-aux (cdr lst))))))

    (foldr-aux lst)))

(define foldl
  (lambda (f base lst)
    (define foldl-aux
      (lambda (base lst)
        (if (null? lst)
            base
            (foldl-aux (f base (car lst)) (cdr lst)))))

    (foldl-aux base lst)))

(define for
  (lambda (lo hi f)
    (define for-aux
      (lambda (lo)
        (if (< lo hi)
            (cons (f lo) (for-aux (+ lo 1)))
            '())))

    (for-aux lo)))

(define concat
  (lambda (lists)
    (foldr append-two '() lists)))

(define list-read
  (lambda (lst i)
    (if (= i 0)
        (car lst)
        (list-read (cdr lst) (- i 1)))))

(define list-write
  (lambda (lst i val)
    (if (= i 0)
        (cons val (cdr lst))
        (cons (car lst) (list-write (cdr lst) (- i 1) val)))))

(define list-remove-pos
  (lambda (lst i)
    (if (= i 0)
        (cdr lst)
        (cons (car lst) (list-remove-pos (cdr lst) (- i 1))))))

(define duplicates?
  (lambda (lst)
    (if (null? lst)
        #f
        (or (cavity-member? (car lst) (cdr lst))
            (duplicates? (cdr lst))))))

(define make-matrix
  (lambda (n m init)
    (for 0 n (lambda (i) (for 0 m (lambda (j) (init i j)))))))

(define matrix-read
  (lambda (mat i j)
    (list-read (list-read mat i) j)))

(define matrix-write
  (lambda (mat i j val)
    (list-write mat i (list-write (list-read mat i) j val))))

(define matrix-size
  (lambda (mat)
    (dimensions (length mat) (length (car mat)))))

(define matrix-map
  (lambda (f mat)
    (maze-map (lambda (lst) (maze-map f lst)) mat)))

(define initial-random 0)

(define next-random-number
  (lambda (current-random)
    (remainder (+ (* current-random 3581) 12751) 131072)))

(define shuffle
  (lambda (lst)
    (shuffle-aux lst initial-random)))

(define shuffle-aux
  (lambda (lst current-random)
    (if (null? lst)
        '()
        (let ((new-random (next-random-number current-random)))
          (let ((i (remainder new-random (length lst))))
            (cons (list-read lst i)
                  (shuffle-aux (list-remove-pos lst i)
                               new-random)))))))

(define make-maze
  (lambda (n m) ; n and m must be odd
    (if (not (and (maze-odd? n) (maze-odd? m)))
        maze-error-value
        (let ((cave
               (make-matrix n m (lambda (i j)
                                  (if (and (maze-even? i) (maze-even? j))
                                      (coordinate i j)
                                      wall-value))))
              (possible-holes
               (concat
                (for 0 n (lambda (i)
                           (concat
                            (for 0 m (lambda (j)
                                       (if (same-bool? (maze-even? i) (maze-even? j))
                                           '()
                                           (singleton (coordinate i j)))))))))))
          (cave-to-maze (pierce-randomly (shuffle possible-holes) cave))))))

(define cave-to-maze
  (lambda (cave)
    (maze-grid (matrix-map open-cell? cave))))

(define pierce
  (lambda (pos cave)
    (let ((i (coordinate-row pos)) (j (coordinate-column pos)))
      (matrix-write cave i j pos))))

(define pierce-randomly
  (lambda (possible-holes cave)
    (if (null? possible-holes)
        cave
        (let ((hole (car possible-holes)))
          (pierce-randomly (cdr possible-holes)
                           (try-to-pierce hole cave))))))

(define try-to-pierce
  (lambda (pos cave)
    (let ((i (coordinate-row pos)) (j (coordinate-column pos)))
      (let ((ncs (neighboring-cavities pos cave)))
        (if (duplicates?
             (maze-map (lambda (nc) (matrix-read cave (coordinate-row nc) (coordinate-column nc))) ncs))
            cave
            (pierce pos
                    (foldl (lambda (c nc) (change-cavity c nc pos))
                           cave
                           ncs)))))))

(define change-cavity
  (lambda (cave pos new-cavity-id)
    (let ((i (coordinate-row pos)) (j (coordinate-column pos)))
      (change-cavity-aux cave pos new-cavity-id (matrix-read cave i j)))))

(define change-cavity-aux
  (lambda (cave pos new-cavity-id old-cavity-id)
    (let ((i (coordinate-row pos)) (j (coordinate-column pos)))
      (let ((cavity-id (matrix-read cave i j)))
        (if (same-cavity? cavity-id old-cavity-id)
            (foldl (lambda (c nc)
                     (change-cavity-aux c nc new-cavity-id old-cavity-id))
                   (matrix-write cave i j new-cavity-id)
                   (neighboring-cavities pos cave))
            cave)))))

(define neighboring-cavities
  (lambda (pos cave)
    (let ((size (matrix-size cave)))
      (let ((n (dimension-rows size)) (m (dimension-columns size)))
        (let ((i (coordinate-row pos)) (j (coordinate-column pos)))
          (append-four (if (and (> i 0) (open-cell? (matrix-read cave (- i 1) j)))
                      (singleton (coordinate (- i 1) j))
                      '())
                  (if (and (< i (- n 1)) (open-cell? (matrix-read cave (+ i 1) j)))
                      (singleton (coordinate (+ i 1) j))
                      '())
                  (if (and (> j 0) (open-cell? (matrix-read cave i (- j 1))))
                      (singleton (coordinate i (- j 1)))
                      '())
                  (if (and (< j (- m 1)) (open-cell? (matrix-read cave i (+ j 1))))
                      (singleton (coordinate i (+ j 1)))
                      '())))))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read-expected-maze (read)))
         (s3 (number->string count))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "mazefun"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2 ":" s3)
     count
     (lambda () (make-maze (hide count input1) (hide count input2)))
     (lambda (result) (same-maze? (if result result maze-initial-value) output)))))

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
             (write (if result (original-maze result) #f))
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
