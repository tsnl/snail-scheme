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
(r6rs:define-record-type (classNil Nil empty-node?) (fields))
(r6rs:define-record-type (classNode make-node-cells classNode?)
  (fields (immutable left node.left-cell) (immutable right node.right-cell)
          (immutable i node.i) (immutable j node.j)))
(define (unit) (if #f #f))
(define (make-node-raw left right i j) (make-node-cells (ref left) (ref right) i j))
(define (node.left node) (ref-get (node.left-cell node)))
(define (node.right node) (ref-get (node.right-cell node)))
(define (node.left-set! node value) (ref-set! (node.left-cell node) value))
(define (node.right-set! node value) (ref-set! (node.right-cell node) value))
(define (power-of-two n)
  (let loop ((n n) (value 1)) (if (= n 0) value (loop (- n 1) (* value 2)))))
(define diagnostic-text '#("\n" " Total memory available= ???????? bytes" "  Free memory= ???????? bytes" "Garbage Collector Test" "GCBench: Top down construction" "GCBench: Bottom up construction" "GCBench: Main" "Failed"))
(define diagnostic-sizes '#(( " Stretching memory with a binary tree of depth " . "") ( " Creating a long-lived binary tree of depth " . "") ( " Creating a long-lived array of " . " inexact reals")))
(define (print-text code) (display (vector-ref diagnostic-text code)))
(define (print-size code value)
  (let ((parts (vector-ref diagnostic-sizes code)))
    (display (string-append (car parts) (number->string value) (cdr parts)))))
(define (print-construction iters depth)
  (display (string-append "Creating " (number->string iters) " trees of depth " (number->string depth))))
;;  This is adapted from a benchmark written by John Ellis and Pete Kovac
;;  of Post Communications.
;;  It was modified by Hans Boehm of Silicon Graphics.
;;  It was translated into Scheme by William D Clinger of Northeastern Univ.
;;  Last modified 24 November 2007 (translated into R6RS Scheme).
;;
;;       This is no substitute for real applications.  No actual application
;;       is likely to behave in exactly this way.  However, this benchmark was
;;       designed to be more representative of real applications than other
;;       Java GC benchmarks of which we are aware.
;;       It attempts to model those properties of allocation requests that
;;       are important to current GC techniques.
;;       It is designed to be used either to obtain a single overall performance
;;       number, or to give a more detailed estimate of how collector
;;       performance varies with object lifetimes.  It prints the time
;;       required to allocate and collect balanced binary trees of various
;;       sizes.  Smaller trees result in shorter object lifetimes.  Each cycle
;;       allocates roughly the same amount of memory.
;;       Two data structures are kept around during the entire process, so
;;       that the measured performance is representative of applications
;;       that maintain some live in-memory data.  One of these is a tree
;;       containing many pointers.  The other is a large array containing
;;       double precision floating point numbers.  Both should be of comparable
;;       size.
;;
;;       The results are only really meaningful together with a specification
;;       of how much memory was used.  It is possible to trade memory for
;;       better time performance.  This benchmark should be run in a 32 MB
;;       heap, though we don't currently know how to enforce that uniformly.

;; In the Java version, this routine prints the heap size and the amount
;; of free memory.  There is no portable way to do this in Scheme; each
;; implementation needs its own version.


(define (run-benchmark2 name thunk)
  (print-text name)
  (print-text 0)
  (thunk))

(define (PrintDiagnostics)
  (print-text 1)
  (print-text 2)
  (print-text 0))

(define (gcbench kStretchTreeDepth)

  ;;  Nodes used by a tree of a given size
  (define (TreeSize i)
    (- (power-of-two (+ i 1)) 1))

  ;;  Number of iterations to use for a given tree depth
  (define (NumIters i)
    (quotient (* 2 (TreeSize kStretchTreeDepth))
              (TreeSize i)))

  ;;  Parameters are determined by kStretchTreeDepth.
  ;;  In Boehm's version the parameters were fixed as follows:
  ;;    public static final int kStretchTreeDepth    = 18;  // about 16Mb
  ;;    public static final int kLongLivedTreeDepth  = 16;  // about 4Mb
  ;;    public static final int kArraySize  = 500000;       // about 4Mb
  ;;    public static final int kMinTreeDepth = 4;
  ;;    public static final int kMaxTreeDepth = 16;
  ;;  In Larceny the storage numbers above would be 12 Mby, 3 Mby, 6 Mby.

  (let* ((kLongLivedTreeDepth (- kStretchTreeDepth 2))
         (kArraySize          (* 4 (TreeSize kLongLivedTreeDepth)))
         (kMinTreeDepth       4)
         (kMaxTreeDepth       kLongLivedTreeDepth))

    ;; Elements 3 and 4 of the allocated records are useless.
    ;; They're just to take up space, so this will be comparable
    ;; to the Java original.

    (define nil (Nil))

    (let ((make-empty-node (lambda () (make-node-raw nil nil 0 0)))
	  (make-node (lambda (l r) (make-node-raw l r 0 0))))

      ;;  Build tree top down, assigning to older objects.
      (define (Populate iDepth thisNode)
        (if (<= iDepth 0)
            (unit)
            (let ((iDepth (- iDepth 1)))
              (node.left-set! thisNode (make-empty-node))
              (node.right-set! thisNode (make-empty-node))
              (Populate iDepth (node.left thisNode))
              (Populate iDepth (node.right thisNode)))))

      ;;  Build tree bottom-up
      (define (MakeTree iDepth)
        (if (<= iDepth 0)
            (make-empty-node)
            (make-node (MakeTree (- iDepth 1))
                       (MakeTree (- iDepth 1)))))

      (define (TimeConstruction depth)
        (let ((iNumIters (NumIters depth)))
          (print-construction iNumIters depth)
          (print-text 0)
          (run-benchmark2
           4
           (lambda ()
             (do ((i 0 (+ i 1)))
                 ((>= i iNumIters) (unit))
               (Populate depth (make-empty-node)))))
          (run-benchmark2
           5
           (lambda ()
             (do ((i 0 (+ i 1)))
                 ((>= i iNumIters) (unit))
               (MakeTree depth))))))

      (define (run-benchmark-x)
        (print-text 3)
        (print-text 0)
        (print-size 0 kStretchTreeDepth)
        (print-text 0)
        (PrintDiagnostics)
        (run-benchmark2
         6
         (lambda ()
           ;;  Stretch the memory space quickly
           (MakeTree kStretchTreeDepth)

           ;;  Create a long lived object
           (print-size 1 kLongLivedTreeDepth)
           (print-text 0)
           (let ((longLivedTree (make-empty-node)))
             (Populate kLongLivedTreeDepth longLivedTree)

             ;;  Create long-lived array, filling half of it
             (print-size 2 kArraySize)
             (print-text 0)
             (let ((array (make-vector kArraySize 0.0)))
               (do ((i 0 (+ i 1)))
                   ((>= i (quotient kArraySize 2)) (unit))
                 (vector-set! array i (/ 1.0 (inexact (+ i 1)))))
               (PrintDiagnostics)

               (do ((d kMinTreeDepth (+ d 2)))
                   ((> d kMaxTreeDepth) (unit))
                 (TimeConstruction d))

               (if (or (empty-node? longLivedTree)
                       (let ((n (min 1000
                                     (- (quotient (vector-length array)
                                                  2)
                                        1))))
                         (not (= (vector-ref array n)
                                 (/ 1.0 (inexact (+ n 1)))))))
                   (begin (print-text 7) (print-text 0)))
               ;;  fake reference to LongLivedTree
               ;;  and array
               ;;  to keep them from being optimized away
               ))))
        (PrintDiagnostics))

      (run-benchmark-x))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "gcbench"))
    (display "The garbage collector should touch about ")
    (display (expt 2 (- input1 13)))
    (display " megabytes of heap storage.")
    (newline)
    (display "The use of more or less memory will skew the results.")
    (newline)
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2)
     count
     (lambda () (gcbench (hide count input1)))
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
