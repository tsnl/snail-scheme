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
(define (ml-cons head tail) (cons head (vector tail)))
(define ml-null? null?)
(define ml-car car)
(define (ml-cdr values) (vector-ref (cdr values) 0))
(define (ml-set-cdr! values tail) (vector-set! (cdr values) 0 tail))
(define (make-lattice elements compare) (cons elements compare))
(define lattice->elements car)
(define lattice->cmp cdr)
(define (make-binding source target) (cons source target))
(define binding-source car)
(define binding-target cdr)
(define (unreachable) (error 'lattice "invalid lattice element or workload"))
;; Each proper-list node has an explicit mutable tail. Selection
;; reverses only its fresh accumulator spine; element identities stay shared.
(: ml-map (All (A B) (-> (-> A B) (MutableList A) (MutableList B))))
(define (ml-map procedure values)
  (if (ml-null? values) (ml-empty)
      (let ((head (procedure (ml-car values))))
        (ml-cons head (ml-map procedure (ml-cdr values))))))
(: ml-append (All (T) (-> (MutableList T) (MutableList T) (MutableList T))))
(define (ml-append first last)
  (if (ml-null? first) last
      (ml-cons (ml-car first) (ml-append (ml-cdr first) last))))
(: ml-concatenate (All (T) (-> (MutableList (MutableList T)) (MutableList T))))
(define (ml-concatenate lists)
  (if (ml-null? lists) (ml-empty)
      (if (ml-null? (ml-cdr lists)) (ml-car lists)
          (ml-append (ml-car lists) (ml-concatenate (ml-cdr lists))))))
(: code-member? (-> I64 (MutableList I64) Bool))
(define (code-member? value codes)
  (and (not (ml-null? codes))
       (or (= value (ml-car codes)) (code-member? value (ml-cdr codes)))))
;; The original quoted lists have constant lifetime and precede timing.
;; Point codes: low=0, high=1. Order codes: less=0, equal=1, more=2, uncomparable=3.
(define lattice-base-elements (ml-cons 0 (ml-cons 1 (ml-empty))))
(define lattice-less-equal (ml-cons 0 (ml-cons 1 (ml-empty))))
(define lattice-more-equal (ml-cons 2 (ml-cons 1 (ml-empty))))
(: lexico (All (T)
  (-> (-> T T I64) (-> (MutableList T) (MutableList T) I64))))
(: zulu-select (All (T)
  (-> (-> T Bool) (MutableList T) (MutableList T))))
(: xreverse! (All (T) (-> (MutableList T) (MutableList T))))
(: select-map (All (A B)
  (-> (-> A Bool) (-> A B) (MutableList A) (MutableList B))))
(: map-and (All (T) (-> (-> T Bool) (MutableList T) Bool)))
(: maps-1 (All (S T)
  (-> (Lattice S) (Lattice T) (MutableList (Binding S T)) S (MutableList T))))
(: maps-rest (All (S T R)
  (-> (Lattice S) (Lattice T) (MutableList (Binding S T)) (MutableList S)
      (-> (MutableList (Binding S T)) R) (-> (MutableList R) R) R)))
(: maps (All (S T) (-> (Lattice S) (Lattice T) (Lattice (MutableList T)))))
(: count-maps (All (S T) (-> (Lattice S) (Lattice T) I64)))
(: sum (-> (MutableList I64) I64))
(: run (-> I64 I64))
;;; LATTICE -- Obtained from Andrew Wright.


;; Given a comparison routine that returns one of
;;       less
;;       more
;;       equal
;;       uncomparable
;; return a new comparison routine that applies to sequences.
(define lexico
  (lambda (base)
    (define lex-fixed
      (lambda (fixed lhs rhs)
        (define check
          (lambda (lhs rhs)
            (if (ml-null? lhs)
                fixed
                (let ((probe
                       (base (ml-car lhs)
                             (ml-car rhs))))
                  (if (or (= probe 1)
                          (= probe fixed))
                      (check (ml-cdr lhs)
                             (ml-cdr rhs))
                      3)))))
        (check lhs rhs)))
    (define lex-first
      (lambda (lhs rhs)
        (if (ml-null? lhs)
            1
            (let ((probe
                   (base (ml-car lhs)
                         (ml-car rhs))))
              (case probe
                ((0 2)
                 (lex-fixed probe
                            (ml-cdr lhs)
                            (ml-cdr rhs)))
                ((1)
                 (lex-first (ml-cdr lhs)
                            (ml-cdr rhs)))
                ((3)
                 3))))))
    lex-first))







;; Select elements of a list which pass some test.
(define zulu-select
  (lambda (test lst)
    (define select-a
      (lambda (ac lst)
        (if (ml-null? lst)
            (xreverse! ac)
            (select-a
             (let ((head (ml-car lst)))
               (if (test head)
                   (ml-cons head ac)
                   ac))
             (ml-cdr lst)))))
    (select-a (ml-empty) lst)))

(define (xreverse! lst)
  (letrec ((rotate
            (lambda (fo fum)
              (let ((next (ml-cdr fo)))
                (ml-set-cdr! fo fum)
                (if (ml-null? next)
                    fo
                    (rotate next fo))))))
    (if (ml-null? lst)
          (ml-empty)
          (rotate lst (ml-empty)))))

;; Select elements of a list which pass some test and map a function
;; over the result.  Note, only efficiency prevents this from being the
;; composition of select and map.
(define select-map
  (lambda (test func lst)
    (define select-a
      (lambda (ac lst)
        (if (ml-null? lst)
            (xreverse! ac)
            (select-a
             (let ((head (ml-car lst)))
               (if (test head)
                   (ml-cons (func head)
                         ac)
                   ac))
             (ml-cdr lst)))))
    (select-a (ml-empty) lst)))



;; This version of map-and tail-recurses on the last test.
(define map-and
  (lambda (proc lst)
    (if (ml-null? lst)
        #t
        (letrec ((drudge
                  (lambda (lst)
                    (let ((rest (ml-cdr lst)))
                      (if (ml-null? rest)
                          (proc (ml-car lst))
                          (and (proc (ml-car lst))
                               (drudge rest)))))))
          (drudge lst)))))

(define (maps-1 source target pas new)
  (let ((scmp (lattice->cmp source))
        (tcmp (lattice->cmp target)))
    (let ((less
           (select-map
            (lambda (p)
              (= 0
                   (scmp (binding-source p) new)))
            binding-target
            pas))
          (more
           (select-map
            (lambda (p)
              (= 2
                   (scmp (binding-source p) new)))
            binding-target
            pas)))
      (zulu-select
       (lambda (t)
         (and
          (map-and
           (lambda (t2)
             (code-member? (tcmp t2 t) lattice-less-equal))
           less)
          (map-and
           (lambda (t2)
             (code-member? (tcmp t2 t) lattice-more-equal))
           more)))
       (lattice->elements target)))))

(define (maps-rest source target pas rest to-1 to-collect)
  (if (ml-null? rest)
      (to-1 pas)
      (let ((next (ml-car rest))
            (rest (ml-cdr rest)))
        (to-collect
         (ml-map
          (lambda (x)
            (maps-rest source target
                       (ml-cons
                        (make-binding next x)
                        pas)
                       rest
                       to-1
                       to-collect))
          (maps-1 source target pas next))))))

(define (maps source target)
  (make-lattice
   (maps-rest source
              target
              (ml-empty)
              (lattice->elements source)
              (lambda (x) (ml-cons (ml-map binding-target x) (ml-empty)))
              (lambda (x) (ml-concatenate x)))
   (lexico (lattice->cmp target))))

(define (count-maps source target)
  (maps-rest source
             target
             (ml-empty)
             (lattice->elements source)
             (lambda (x) 1)
             sum))

(define (sum lst)
  (if (ml-null? lst)
      0
      (+ (ml-car lst) (sum (ml-cdr lst)))))

(define (run k)
  (let* ((l2
          (make-lattice lattice-base-elements
                        (lambda (lhs rhs)
                          (case lhs
                            ((0)
                             (case rhs
                               ((0)
                                1)
                               ((1)
                                0)
                               (else
                                (unreachable))))
                            ((1)
                             (case rhs
                               ((0)
                                2)
                               ((1)
                                1)
                               (else
                                (unreachable))))
                            (else
                             (unreachable))))))
         (l3 (maps l2 l2))
         (l4 (maps l3 l3)))
    (count-maps l2 l2)
    (count-maps l3 l3)
    (count-maps l2 l3)
    (count-maps l3 l2)
    (case k
      ((33) (count-maps l3 l3))
      ((44) (count-maps l4 l4))
      ((45) (let ((l5 (maps l4 l4)))
              (count-maps l4 l5)))
      ((54) (let ((l5 (maps l4 l4)))
              (count-maps l5 l4)))
      ((55) (let ((l5 (maps l4 l4)))
              (count-maps l5 l5)))
      (else (unreachable)))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 (number->string input1))
         (name "lattice"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2)
     count
     (lambda () (run (hide count input1)))
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
