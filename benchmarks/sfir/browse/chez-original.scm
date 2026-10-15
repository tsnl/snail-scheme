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

;;; BROWSE -- Benchmark to create and browse through
;;; an AI-like data base of units.


(define (lookup key table)
  (let loop ((x table))
    (if (null? x)
        #f
        (let ((pair (car x)))
          (if (eq? (car pair) key)
              pair
              (loop (cdr x)))))))

(define *properties* '())

(define (get key1 key2)
  (let ((x (lookup key1 *properties*)))
    (if x
        (let ((y (lookup key2 (cdr x))))
          (if y
              (cdr y)
              #f))
        #f)))

(define (put key1 key2 val)
  (let ((x (lookup key1 *properties*)))
    (if x
        (let ((y (lookup key2 (cdr x))))
          (if y
              (set-cdr! y val)
              (set-cdr! x (cons (cons key2 val) (cdr x)))))
        (set! *properties*
              (cons (list key1 (cons key2 val)) *properties*)))))

(define *current-gensym* 0)

(define (generate-symbol)
  (set! *current-gensym* (+ *current-gensym* 1))
  (string->symbol (number->string *current-gensym*)))

(define (append-to-tail! x y)
  (if (null? x)
      y
      (do ((a x b)
           (b (cdr x) (cdr b)))
          ((null? b)
           (set-cdr! a y)
           x))))

(define (tree-copy x)
  (if (not (pair? x))
      x
      (cons (tree-copy (car x))
            (tree-copy (cdr x)))))

;;; n is # of symbols
;;; m is maximum amount of stuff on the plist
;;; npats is the number of basic patterns on the unit
;;; ipats is the instantiated copies of the patterns

(define *rand* 21)

(define (init n m npats ipats)
  (let ((ipats (tree-copy ipats)))
    (do ((p ipats (cdr p)))
        ((null? (cdr p)) (set-cdr! p ipats)))
    (do ((n n (- n 1))
         (i m (cond ((zero? i) m)
                    (else (- i 1))))
         (name (generate-symbol) (generate-symbol))
         (a '()))
        ((= n 0) a)
      (set! a (cons name a))
      (do ((i i (- i 1)))
          ((zero? i))
        (put name (generate-symbol) #f))
      (put name
           'pattern
           (do ((i npats (- i 1))
                (ipats ipats (cdr ipats))
                (a '()))
               ((zero? i) a)
             (set! a (cons (car ipats) a))))
      (do ((j (- m i) (- j 1)))
          ((zero? j))
        (put name (generate-symbol) #f)))))

(define (browse-random)
  (set! *rand* (remainder (* *rand* 17) 251))
  *rand*)

(define (randomize l)
  (do ((a '()))
      ((null? l) a)
    (let ((n (remainder (browse-random) (length l))))
      (cond ((zero? n)
             (set! a (cons (car l) a))
             (set! l (cdr l))
             l)
            (else
             (do ((n n (- n 1))
                  (x l (cdr x)))
                 ((= n 1)
                  (set! a (cons (cadr x) a))
                  (set-cdr! x (cddr x))
                  x)))))))

(define (my-match pat dat alist)
  (cond ((null? pat)
         (null? dat))
        ((null? dat) '())
        ((or (eq? (car pat) '?)
             (eq? (car pat)
                  (car dat)))
         (my-match (cdr pat) (cdr dat) alist))
        ((eq? (car pat) '*)
         (or (my-match (cdr pat) dat alist)
             (my-match (cdr pat) (cdr dat) alist)
             (my-match pat (cdr dat) alist)))
        (else (cond ((not (pair? (car pat)))
                     (cond ((eq? (string-ref (symbol->string (car pat)) 0)
                                 #\?)
                            (let ((val (assq (car pat) alist)))
                              (cond (val (my-match (cons (cdr val)
                                                         (cdr pat))
                                                   dat alist))
                                    (else (my-match (cdr pat)
                                                    (cdr dat)
                                                    (cons (cons (car pat)
                                                                (car dat))
                                                          alist))))))
                           ((eq? (string-ref (symbol->string (car pat)) 0)
                                 #\*)
                            (let ((val (assq (car pat) alist)))
                              (cond (val (my-match (append (cdr val)
                                                           (cdr pat))
                                                   dat alist))
                                    (else
                                     (do ((l '()
                                             (append-to-tail!
                                              l
                                              (cons (if (null? d)
                                                        '()
                                                        (car d))
                                                    '())))
                                          (e (cons '() dat) (cdr e))
                                          (d dat (if (null? d) '() (cdr d))))
                                         ((or (null? e)
                                              (my-match (cdr pat)
                                                        d
                                                        (cons
                                                         (cons (car pat) l)
                                                         alist)))
                                          (if (null? e) #f #t)))))))

                           ;; fix suggested by Manuel Serrano
                           ;; (cond did not have an else clause);
                           ;; this changes the run time quite a bit

                           (else #f)))
                    (else (and
                           (pair? (car dat))
                           (my-match (car pat)
                                     (car dat) alist)
                           (my-match (cdr pat)
                                     (cdr dat) alist)))))))

(define database
  (randomize
   (init 100 10 4 '((a a a b b b b a a a a a b b a a a)
                    (a a b b b b a a
                       (a a)(b b))
                    (a a a b (b a) b a b a)))))

(define (browse pats)
  (investigate
   database
   pats)
  (map string->number (map symbol->string database)))

(define (investigate units pats)
  (do ((units units (cdr units)))
      ((null? units))
    (do ((pats pats (cdr pats)))
        ((null? pats))
      (do ((p (get (car units) 'pattern)
              (cdr p)))
          ((null? p))
        (my-match (car pats) (car p) '())))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 "")
         (name "browse"))
    (run-r7rs-benchmark
     (string-append name ":" s2)
     count
     (lambda () (browse (hide count input1)))
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
