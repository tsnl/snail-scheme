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

 (define read-line
   get-line)

(define (square x)
  (* x x))

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
(define (make-point x y z) (vector x y z))
(define (point-x p) (vector-ref p 0))
(define (point-y p) (vector-ref p 1))
(define (point-z p) (vector-ref p 2))
(define (make-sphere color radius center) (vector color radius center))
(define (sphere-color s) (vector-ref s 0))
(define (sphere-radius s) (vector-ref s 1))
(define (sphere-center s) (vector-ref s 2))
(define (no-root) (vector 0))
(define (some-root value) (vector 1 value))
(define (root? value) (= (vector-ref value 0) 1))
(define (root-value value) (vector-ref value 1))
(define (no-point) (vector 0))
(define (some-point value) (vector 1 value))
(define (candidate? value) (= (vector-ref value 0) 1))
(define (candidate-point value) (vector-ref value 1))
(define (miss) (vector 0))
(define (hit sphere point) (vector 1 sphere point))
(define (hit? value) (= (vector-ref value 0) 1))
(define (hit-sphere value) (vector-ref value 1))
(define (hit-point value) (vector-ref value 2))
(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define i64->f64 inexact)
(define f64->i64 exact)
(define (write-i64 number port)
  (when (< number 0) (write-char #\- port))
  (write-negative-digits (if (> number 0) (- 0 number) number) port))
(define (write-negative-digits number port)
  (let ((prefix (quotient number 10)))
    (unless (= prefix 0) (write-negative-digits prefix port))
    (write-char (integer->char (- 48 (remainder number 10))) port)))
;; Chez min/max propagate NaN and select the right equal operand,
;; including signed zero. The source uses these two-argument operations only.
(: ray-min (-> F64 F64 F64))
(define (ray-min left right)
  (if (not (= left left)) left (if (< left right) left right)))
(: ray-max (-> F64 F64 F64))
(define (ray-max left right)
  (if (not (= left left)) left (if (> left right) left right)))
(: sq (-> F64 F64))
(: mag (-> F64 F64 F64 F64))
(: unit-vector (-> F64 F64 F64 Point))
(: distance (-> Point Point F64))
(: minroot (-> F64 F64 F64 Root))
(: tracer (-> String I64 Unit))
(: color-at (-> F64 F64 I64))
(: sendray (-> Point Point F64))
(: first-hit (-> Point Point Hit))
(: lambert (-> Sphere Point Point F64))
(: defsphere (-> F64 F64 F64 F64 F64 Sphere))
(: surface-color (-> Sphere F64))
(: intersect (-> Sphere Point Point Candidate))
(: sphere-intersect (-> Sphere Point Point Candidate))
(: normal (-> Sphere Point Point))
(: sphere-normal (-> Sphere Point Point))
(: ray-test (-> I64 String Unit))
(: run (-> I64 String I64))
;;; RAY -- Ray-trace a simple scene with spheres, generating a ".pgm" file.
;;; Translated to Scheme from Paul Graham's book ANSI Common Lisp, Example 9.8


; make-point: concrete product operation.

; point-x: concrete product operation.
; point-y: concrete product operation.
; point-z: concrete product operation.

(define (sq x) (* x x))

(define (mag x y z)
  (sqrt (+ (+ (sq x) (sq y)) (sq z))))

(define (unit-vector x y z)
  (let ((d (mag x y z)))
    (make-point (/ x d) (/ y d) (/ z d))))

(define (distance p1 p2)
  (mag (- (point-x p1) (point-x p2))
       (- (point-y p1) (point-y p2))
       (- (point-z p1) (point-z p2))))

(define (minroot a b c)
  (if (= a 0.0)
      (some-root (/ (* -1.0 c) b))
      (let ((disc (- (sq b) (* (* 4.0 a) c))))
        (if (< disc 0.0)
            (no-root)
            (let ((discrt (sqrt disc))
                  (minus-b (* -1.0 b))
                  (two-a (* 2.0 a)))
              (some-root (ray-min (/ (+ minus-b discrt) two-a)
                              (/ (- minus-b discrt) two-a))))))))

(define *world* (ref (ann '() (List Sphere))))

(define eye (make-point 0.0 0.0 200.0))

(define (tracer pathname res)
  (when (file-exists? pathname)
    (delete-file pathname))
  (call-with-output-file
      pathname
    (lambda (p)
      (let ((extent (* res 100)))
        (write-string "P2 " p)
        (write-i64 extent p)
        (write-string " " p)
        (write-i64 extent p)
        (write-string " 255" p)
        (newline p)
        (do ((y 0 (+ y 1)))
            ((= y extent))
          (do ((x 0 (+ x 1)))
              ((= x extent))
            (write-i64 (color-at
                    (+ -50.0
                       (/ (i64->f64 x) (i64->f64 res)))
                    (+ -50.0
                       (/ (i64->f64 y) (i64->f64 res))))
                   p)
            (newline p)))))))

(define (color-at x y)
  (let ((ray (unit-vector (- x (point-x eye))
                          (- y (point-y eye))
                          (* -1.0 (point-z eye)))))
    (f64->i64 (round (* (sendray eye ray) 255.0)))))



(define (sendray pt ray)
  (let ((selected (first-hit pt ray)))
    (if (hit? selected)
        (* (lambert (hit-sphere selected) (hit-point selected) ray)
           (surface-color (hit-sphere selected)))
        0.0)))

(define (first-hit pt ray)
  (let loop ((lst (ref-get *world*)) (selected (miss)) (dist 1e308))
    (if (null? lst)
        selected
        (let ((s (car lst)))
          (let ((candidate (intersect s pt ray)))
            (if (candidate? candidate)
                (let* ((h (candidate-point candidate)) (d (distance h pt)))
                  (if (< d dist)
                      (loop (cdr lst) (hit s h) d)
                      (loop (cdr lst) selected dist)))
                (loop (cdr lst) selected dist)))))))

(define (lambert s int ray)
  (let ((n (normal s int)))
    (ray-max 0.0
         (+ (+ (* (point-x ray) (point-x n))
               (* (point-y ray) (point-y n)))
            (* (point-z ray) (point-z n))))))

; make-sphere: concrete product operation.

; sphere-color: concrete product operation.
; sphere-radius: concrete product operation.
; sphere-center: concrete product operation.

(define (defsphere x y z r c)
  (let ((s (make-sphere c r (make-point x y z))))
    (ref-set! *world* (cons s (ref-get *world*)))
    s))

(define (surface-color s)
  (sphere-color s))

(define (intersect s pt ray)
  (sphere-intersect s pt ray))

(define (sphere-intersect s pt ray)
  (let* ((xr (point-x ray))
         (yr (point-y ray))
         (zr (point-z ray))
         (c (sphere-center s))
         (n (minroot
             (+ (+ (sq xr) (sq yr)) (sq zr))
             (* 2.0
                (+ (+ (* (- (point-x pt) (point-x c)) xr)
                      (* (- (point-y pt) (point-y c)) yr))
                   (* (- (point-z pt) (point-z c)) zr)))
             (+ (+ (+ (sq (- (point-x pt) (point-x c)))
                      (sq (- (point-y pt) (point-y c))))
                   (sq (- (point-z pt) (point-z c))))
                (* -1.0 (sq (sphere-radius s)))))))
    (if (root? n)
        (let ((root (root-value n)))
          (some-point (make-point (+ (point-x pt) (* root xr))
                                  (+ (point-y pt) (* root yr))
                                  (+ (point-z pt) (* root zr)))))
        (no-point))))

(define (normal s pt)
  (sphere-normal s pt))

(define (sphere-normal s pt)
  (let ((c (sphere-center s)))
    (unit-vector (- (point-x c) (point-x pt))
                 (- (point-y c) (point-y pt))
                 (- (point-z c) (point-z pt)))))

(define (ray-test res output-file)
  (ref-set! *world* '())
  (defsphere 0.0 -300.0 -1200.0 200.0 0.8)
  (defsphere -80.0 -150.0 -1200.0 200.0 0.7)
  (defsphere 70.0 -100.0 -1200.0 200.0 0.9)
  (do ((x -2 (+ x 1)))
      ((> x 2))
    (do ((z 2 (+ z 1)))
        ((> z 7))
      (defsphere
        (* (i64->f64 x) 200.0)
        300.0
        (* (i64->f64 z) -400.0)
        40.0
        0.75)))
  (tracer output-file res))

(define (run input output)
  (ray-test input output)
  1)

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "ray"))
    (run-r7rs-benchmark
     (string-append name ":" s2)
     count
     (lambda () (run (hide count input1) (hide count input2)))
     (lambda (result) (equal? result output)))))

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
               (result 0))
      (cond ((< i count)
             (loop (+ i 1) (thunk)))
            ((ok? (if (= result 0) #f 'ok))
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
             (write (if (= result 0) #f 'ok))
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
