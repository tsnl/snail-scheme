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
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define (unit) (if #f #f))
(define (unreachable) (error 'matrix "invalid typed Matrix value"))
(define (no-permutation) #f)
(define (permutation dispatch) dispatch)
(define permutation-dispatch values)
(define permutation? procedure?)
(define (current-object value) (vector 0 value))
(define (next-permutation value) (vector 1 value))
(define (remaining-objects value) (vector 2 value))
(define (current-value value) (vector-ref value 1))
(define next-value current-value)
(define remaining-values current-value)
(define (gcd-value value) (vector 0 value))
(define gcd-result-value current-value)
(define (gcd-negative sign magnitude) (vector 1 sign magnitude))
(define (gcd-sign value) (vector-ref value 1))
(define (gcd-magnitude value) (vector-ref value 2))
(define (no-primes) '())
(define (prime-node value tail) (cons value tail))
(define prime-value car)
(define prime-tail cdr)
(define prime-null? null?)
(define (matrix-answer value) (vector 0 value))
(define (marker-answer value) (vector 1 value))
(define answer-matrix current-value)
(define answer-marker current-value)
(define (matrix-answer? value) (= (vector-ref value 0) 0))
(define (best size count answers) (vector size count answers))
(define (best-size value) (vector-ref value 0))
(define (best-count value) (vector-ref value 1))
(define (best-answers value) (vector-ref value 2))
;; These lists are persistent. Only the prime-list tail and last box
;; are mutable; the predicate closure continues to see the original head.

(: list (All (T) (-> (Rest T) (List T))))

(: reverse (All (T) (-> (List T) (List T))))

(: map-one (All (A B) (-> (-> A B) (List A) (List B))))
(define (map-one procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (map-one procedure (cdr values))))))
(: map-two (All (A B C) (-> (-> A B C) (List A) (List B) (List C))))
(define (map-two procedure first second)
  (if (null? first) '()
      (let ((head (procedure (car first) (car second))))
        (cons head (map-two procedure (cdr first) (cdr second))))))
(: exact-integer? (-> I64 Bool))



(: expt (-> I64 I64 I64))

(: perm-now (All (T) (-> (Permutation T) T)))
(define (perm-now value) (current-value ((permutation-dispatch value) 0)))
(: perm-brother (All (T) (-> (Permutation T) (Permutation T))))
(define (perm-brother value) (next-value ((permutation-dispatch value) 1)))
(: perm-child (All (T) (-> (Permutation T) (Permutation T))))
(define (perm-child value) (next-value ((permutation-dispatch value) 2)))
(: perm-puke (All (T) (-> (Permutation T) (List T))))
(define (perm-puke value) (remaining-values ((permutation-dispatch value) 3)))
(define (prime-cons head tail) (prime-node head (ref tail)))
(define (prime-cdr value) (ref-get (prime-tail value)))
(define (prime-set-cdr! value tail) (ref-set! (prime-tail value) tail))
(: same-row? (-> (List I64) (List I64) Bool))
(define (same-row? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (= (car left) (car right))
           (same-row? (cdr left) (cdr right)))))
(: same-matrix? (-> (List (List I64)) (List (List I64)) Bool))
(define (same-matrix? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-row? (car left) (car right))
           (same-matrix? (cdr left) (cdr right)))))
(define (same-answer? left right)
  (if (matrix-answer? left)
      (and (matrix-answer? right) (same-matrix? (answer-matrix left) (answer-matrix right)))
      (and (not (matrix-answer? right)) (string=? (answer-marker left) (answer-marker right)))))
(define (same-answers? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-answer? (car left) (car right))
           (same-answers? (cdr left) (cdr right)))))
(define (matrix-read-answers value)
  (and value (map-one (lambda (answer)
                       (if (string? answer) (marker-answer answer) (matrix-answer answer))) value)))
(define (matrix-same-result? value expected)
  (if value (and expected (same-answers? value expected)) (not expected)))
(define (permutation-error code)
  (display "gen-perms: Bad msg: ~a; message code ") (display code) (newline)
  (flush-output-port (current-output-port))
  (unreachable))
(: div (-> I64 I64 I64))
(: mod (-> I64 I64 I64))
(: maximal? (-> (List (List I64)) Bool))
(: zunda (-> (Permutation (List I64)) (List (List I64)) Bool))
(: zebra (-> (Permutation (List I64)) (-> (List I64) (-> I64 I64))
               (-> (List I64) (-> I64 I64)) (List (List I64)) I64 Bool))
(: zulu (-> (List I64) (-> I64 I64) (List (List I64)) (-> (List (List I64)) Bool) Bool))
(: all? (All (T) (-> (-> T Bool) (List T) Bool)))
(: gen-perms (All (T) (-> (List T) (Permutation T))))
(: fold (All (A S) (-> (List A) (-> A S S) S S)))
(: miota (-> I64 (List I64)))
(: proc->vector (-> I64 (-> I64 I64) (Vector I64)))
(: make-modular (All (T) (-> I64 (-> (-> I64 I64 (-> I64 Bool) (-> I64 I64 I64) (-> I64 I64) (-> I64 I64 I64) (-> I64 I64) T) T))))
(: extended-gcd (All (T) (-> I64 I64 (-> I64 I64 I64 T) (GcdResult T))))
(: make-row-reduce (-> I64 I64 (-> I64 Bool) (-> I64 I64 I64) (-> I64 I64) (-> I64 I64 I64) (-> I64 I64) (-> (List (List I64)) (List (List I64)))))
(: make-in-row-space? (-> I64 I64 (-> I64 Bool) (-> I64 I64 I64) (-> I64 I64) (-> I64 I64 I64) (-> I64 I64) (-> (List (List I64)) (-> (List I64) Bool))))
(: make-modular-row-reduce (-> I64 (-> (List (List I64)) (List (List I64)))))
(: make-modular-in-row-space? (-> I64 (-> (List (List I64)) (-> (List I64) Bool))))
(: find-prime (-> I64 I64))
(: det-upper-bound (-> I64 I64))
(: go (All (S) (-> I64 I64 (-> (List (List I64)) S S) S S)))
(: go-folder (-> (List (List I64)) Best Best))
(: really-go (-> I64 I64 (List Answer)))
(: remove-in-order (All (T) (-> (-> T Bool) (List T) (List T))))
(: fold-over-rows (All (S) (-> I64 (-> (List I64) S S) S S)))
(: fold-over-subs-of-size (All (T S) (-> (List T) I64 (-> (List T) S S) S S)))
;;; MATRIX -- Obtained from Andrew Wright.


;;; We need R6RS div and mod for this benchmark.

(define (div x y)
  (cond ((and (exact-integer? x)
              (exact-integer? y)
              (>= x 0))
         (quotient x y))
        ((< y 0)
         ;; x < 0, y < 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               q
               (+ q 1))))
        (else
         ;; x < 0, y > 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               q
               (- q 1))))))

(define (mod x y)
  (cond ((and (exact-integer? x)
              (exact-integer? y)
              (>= x 0))
         (remainder x y))
        ((< y 0)
         ;; x < 0, y < 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               0
               (- r y))))
        (else
         ;; x < 0, y > 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               0
               (+ r y))))))

;; Chez-Scheme compatibility stuff:

(define (chez-box x) (ref x))
(define (chez-unbox x) (ref-get x))
(define (chez-set-box! x y) (ref-set! x y))

;; Test that a matrix with entries in {+1, -1} is maximal among the matricies
;; obtainable by
;;       re-ordering the rows
;;       re-ordering the columns
;;       negating any subset of the columns
;;       negating any subset of the rows
;; Where we compare two matricies by lexicographically comparing the first row,
;; then the next to last, etc., and we compare a row by lexicographically
;; comparing the first entry, the second entry, etc., and we compare two
;; entries by +1 > -1.
;; Note, this scheme obeys the useful fact that if (append mat1 mat2) is
;; maximal, then so is mat1.  Thus, we can build up maximal matricies
;; row by row.
;;
;; Once you have chosen the row re-ordering so that you know which row goes
;; last, the set of columns to negate is fixed (since the last row must be
;; all +1's).
;;
;; Note, the column ordering is really totally determined as follows:
;;       all columns for which the second row is +1 must come before all
;;               columns for which the second row is -1.
;;       among columns for which the second row is +1, all columns for which
;;               the third row is +1 come before those for which the third is
;;               -1, and similarly for columns in which the second row is -1.
;;       etc
;; Thus, each succeeding row sorts columns withing refinings equivalence
;; classes.
;;
;; Maximal? assumes that mat has atleast one row, and that the first row
;; is all +1's.
(define maximal?
  (lambda (mat)
    (let pick-first-row
        ((first-row-perm
          (gen-perms mat)))
      (if (permutation? first-row-perm)
          (and (zunda first-row-perm mat)
               (pick-first-row (perm-brother first-row-perm)))
          #t))))

(define zunda
  (lambda (first-row-perm mat)
    (let* ((first-row
            (perm-now first-row-perm))
           (number-of-cols
            (length first-row))
           (make-row->func
            (lambda (if-equal if-different)
              (lambda (row)
                (let ((vec
                       (make-vector number-of-cols)))
                  (do ((i 0 (+ i 1))
                       (first first-row
                              (cdr first))
                       (row row
                            (cdr row)))
                      ((= i number-of-cols) (unit))
                    (vector-set! vec
                                 i
                                 (if (= (car first) (car row))
                                     if-equal
                                     if-different)))
                  (lambda (i)
                    (vector-ref vec i))))))
           (mat
            (cdr mat)))
      (zebra (perm-child first-row-perm)
             (make-row->func 1 -1)
             (make-row->func -1 1)
             mat
             number-of-cols))))


(define zebra
  (lambda (row-perm row->func+ row->func- mat number-of-cols)
    (let _-*-
        ((row-perm
          row-perm)
         (mat
          mat)
         (partitions
          (list (miota number-of-cols))))
      (or (not (permutation? row-perm))
          (and
           (zulu (car mat)
                 (row->func+ (perm-now row-perm))
                 partitions
                 (lambda (new-partitions)
                   (_-*- (perm-child row-perm)
                         (cdr mat)
                         new-partitions)))
           (zulu (car mat)
                 (row->func- (perm-now row-perm))
                 partitions
                 (lambda (new-partitions)
                   (_-*- (perm-child row-perm)
                         (cdr mat)
                         new-partitions)))
           (let ((new-row-perm
                  (perm-brother row-perm)))
             (or (not (permutation? new-row-perm))
                 (_-*- new-row-perm
                       mat
                       partitions))))))))


(define zulu
  (let ((cons-if-not-null
         (lambda (lhs rhs)
           (if (null? lhs)
               rhs
               (cons lhs rhs)))))
    (lambda (old-row new-row-func partitions equal-cont)
      (let _-*-
          ((p-in
            partitions)
           (old-row
            old-row)
           (rev-p-out
            '()))
        (let _-split-
            ((partition
              (car p-in))
             (old-row
              old-row)
             (plus
              '())
             (minus
              '()))
          (if (null? partition)
              (let _-minus-
                  ((old-row
                    old-row)
                   (m
                    minus))
                (if (null? m)
                    (let ((rev-p-out
                           (cons-if-not-null
                            minus
                            (cons-if-not-null
                             plus
                             rev-p-out)))
                          (p-in
                           (cdr p-in)))
                      (if (null? p-in)
                          (equal-cont (reverse rev-p-out))
                          (_-*- p-in old-row rev-p-out)))
                    (or (= 1 (car old-row))
                        (_-minus- (cdr old-row)
                                  (cdr m)))))
              (let ((next
                     (car partition)))
                (case (new-row-func next)
                  ((1)
                   (and (= 1 (car old-row))
                        (_-split- (cdr partition)
                                  (cdr old-row)
                                  (cons next plus)
                                  minus)))
                  ((-1)
                   (_-split- (cdr partition)
                             old-row
                             plus
                             (cons next minus)))))))))))

(define all?
  (lambda (ok? lst)
    (let _-*-
        ((lst
          lst))
      (or (null? lst)
          (and (ok? (car lst))
               (_-*- (cdr lst)))))))

(define gen-perms
  (lambda (objects)
    (let _-*-
        ((zulu-future
          objects)
         (past
          '()))
      (if (null? zulu-future)
          (no-permutation)
          (permutation (lambda (msg)
            (case msg
              ((0)
               (current-object (car zulu-future)))
              ((1)
               (next-permutation (_-*- (cdr zulu-future)
                     (cons (car zulu-future)
                           past))))
              ((2)
               (next-permutation (gen-perms
                (fold past cons (cdr zulu-future)))))
              ((3)
               (remaining-objects (cons (car zulu-future)
                     (fold past cons (cdr zulu-future)))))
              (else
               (permutation-error msg)))))))))

(define fold
  (lambda (lst folder state)
    (let _-*-
        ((lst
          lst)
         (state
          state))
      (if (null? lst)
          state
          (_-*- (cdr lst)
                (folder (car lst)
                        state))))))

(define miota
  (lambda (len)
    (let _-*-
        ((i 0))
      (if (= i len)
          '()
          (cons i
                (_-*- (+ i 1)))))))

(define proc->vector
  (lambda (size proc)
    (let ((res
           (make-vector size)))
      (do ((i 0
              (+ i 1)))
          ((= i size) (unit))
        (vector-set! res
                     i
                     (proc i)))
      res)))

;; Given a prime number P, return a procedure which, given a `maker' procedure,
;; calls it on the operations for the field Z/PZ.
(define make-modular
  (lambda (modulus)
    (let* ((reduce
            (lambda (x)
              (mod x modulus)))
           (coef-zero?
            (lambda (x)
              (zero? (reduce x))))
           (coef-+
            (lambda (x y)
              (reduce (+ x y))))
           (coef-negate
            (lambda (x)
              (reduce (- x))))
           (coef-*
            (lambda (x y)
              (reduce (* x y))))
           (coef-recip
            (let ((inverses
                   (proc->vector (- modulus 1)
                                 (lambda (i)
                                   (gcd-result-value (extended-gcd (+ i 1)
                                                 modulus
                                                 (lambda (gcd inverse ignore)
                                                   inverse)))))))
              ;; Coef-recip.
              (lambda (x)
                (let ((x
                       (reduce x)))
                  (vector-ref inverses (- x 1)))))))
      (lambda (maker)
        (maker 0;; coef-zero
               1;; coef-one
               coef-zero?
               coef-+
               coef-negate
               coef-*
               coef-recip)))))

;; Extended Euclidean algorithm.
;; (extended-gcd a b cont) computes the gcd of a and b, and expresses it
;; as a linear combination of a and b.  It returns calling cont via
;;       (cont gcd a-coef b-coef)
;; where gcd is the GCD and is equal to a-coef * a + b-coef * b.
(define (extended-gcd a b cont)
  (let ((n->sgn/abs
         (lambda (x cont)
           (if (>= x 0)
               (cont 1 x)
               (gcd-negative -1 (- x))))))
    (n->sgn/abs a
                  (lambda (p-a p)
                    (n->sgn/abs b
                                (lambda (q-b q)
                                  (let _-*-
                                      ((p
                                        p)
                                       (p-a
                                        p-a)
                                       (p-b
                                        0)
                                       (q
                                        q)
                                       (q-a
                                        0)
                                       (q-b
                                        q-b))
                                    (if (zero? q)
                                        (gcd-value (cont p p-a p-b))
                                        (let ((mult
                                               (div p q)))
                                          (_-*- q
                                                q-a
                                                q-b
                                                (- p (* mult q))
                                                (- p-a (* mult q-a))
                                                (- p-b (* mult q-b))))))))))))

;; Given elements and operations on the base field, return a procedure which
;; computes the row-reduced version of a matrix over that field.  The result
;; is a list of rows where the first non-zero entry in each row is a 1 (in
;; the coefficient field) and occurs to the right of all the leading non-zero
;; entries of previous rows.  In particular, the number of rows is the rank
;; of the original matrix, and they have the same row-space.
;; The items related to the base field which are needed are:
;;       coef-zero       additive identity
;;       coef-one        multiplicative identity
;;       coef-zero?      test for additive identity
;;       coef-+          addition (two args)
;;       coef-negate     additive inverse
;;       coef-*          multiplication (two args)
;;       coef-recip      multiplicative inverse
;; Note, matricies are stored as lists of rows (i.e., lists of lists).
(define make-row-reduce
  (lambda (coef-zero coef-one coef-zero? coef-+ coef-negate coef-* coef-recip)
    (lambda (mat)
      (let _-*-
          ((mat
            mat))
        (if (or (null? mat)
                (null? (car mat)))
            '()
            (let _-**-
                ((in
                  mat)
                 (out
                  '()))
              (if (null? in)
                  (map
                   (lambda (x)
                     (cons coef-zero x))
                   (_-*- out))
                  (let* ((prow
                          (car in))
                         (pivot
                          (car prow))
                         (prest
                          (cdr prow))
                         (in
                          (cdr in)))
                    (if (coef-zero? pivot)
                        (_-**- in
                               (cons prest out))
                        (let ((zap-row
                               (map
                                (let ((mult
                                       (coef-recip pivot)))
                                  (lambda (x)
                                    (coef-* mult x)))
                                prest)))
                          (cons (cons coef-one zap-row)
                                (map
                                 (lambda (x)
                                   (cons coef-zero x))
                                 (_-*-
                                  (fold in
                                        (lambda (row mat)
                                          (cons
                                           (let ((first-col
                                                  (car row))
                                                 (rest-row
                                                  (cdr row)))
                                             (if (coef-zero? first-col)
                                                 rest-row
                                                 (map
                                                  (let ((mult
                                                         (coef-negate first-col)))
                                                    (lambda (f z)
                                                      (coef-+ f
                                                              (coef-* mult z))))
                                                  rest-row
                                                  zap-row)))
                                           mat))
                                        out))))))))))))))


;; Given elements and operations on the base field, return a procedure which
;; when given a matrix and a vector tests to see if the vector is in the
;; row-space of the matrix.  This returned function is curried.
;; The items related to the base field which are needed are:
;;       coef-zero       additive identity
;;       coef-one        multiplicative identity
;;       coef-zero?      test for additive identity
;;       coef-+          addition (two args)
;;       coef-negate     additive inverse
;;       coef-*          multiplication (two args)
;;       coef-recip      multiplicative inverse
;; Note, matricies are stored as lists of rows (i.e., lists of lists).
(define make-in-row-space?
  (lambda (coef-zero coef-one coef-zero? coef-+ coef-negate coef-* coef-recip)
    (let ((row-reduce
           (make-row-reduce coef-zero
                            coef-one
                            coef-zero?
                            coef-+
                            coef-negate
                            coef-*
                            coef-recip)))
      (lambda (mat)
        (let ((mat
               (row-reduce mat)))
          (lambda (row)
            (let _-*-
                ((row
                  row)
                 (mat
                  mat))
              (if (null? row)
                  #t
                  (let ((r-first
                         (car row))
                        (r-rest
                         (cdr row)))
                    (cond ((coef-zero? r-first)
                           (_-*- r-rest
                                 (map cdr
                                      (if (or (null? mat)
                                              (coef-zero? (caar mat)))
                                          mat
                                          (cdr mat)))))
                          ((null? mat)
                           #f)
                          (else
                           (let* ((zap-row
                                   (car mat))
                                  (z-first
                                   (car zap-row))
                                  (z-rest
                                   (cdr zap-row))
                                  (mat
                                   (cdr mat)))
                             (if (coef-zero? z-first)
                                 #f
                                 (_-*-
                                  (map
                                   (let ((mult
                                          (coef-negate r-first)))
                                     (lambda (r z)
                                       (coef-+ r
                                               (coef-* mult z))))
                                   r-rest
                                   z-rest)
                                  (map cdr mat)))))))))))))))


;; Given a prime number, return a procedure which takes integer matricies
;; and returns their row-reduced form, modulo the prime.
(define make-modular-row-reduce
  (lambda (modulus)
    ((make-modular modulus)
     make-row-reduce)))


(define make-modular-in-row-space?
  (lambda (modulus)
    ((make-modular modulus)
     make-in-row-space?)))



;; Usual utilities.



;; Given a bound, find a prime greater than the bound.
(define find-prime
  (lambda (bound)
    (let* ((primes
            (prime-cons 2 (no-primes)))
           (last
            (chez-box primes))
           (is-next-prime?
            (lambda (trial)
              (let _-*-
                  ((primes
                    primes))
                (or (prime-null? primes)
                    (let ((p
                           (prime-value primes)))
                      (or (< trial (* p p))
                          (and (not (zero? (mod trial p)))
                               (_-*- (prime-cdr primes))))))))))
      (if (> 2 bound)
          2
          (let _-*-
              ((trial
                3))
            (if (is-next-prime? trial)
                (let ((entry
                       (prime-cons trial (no-primes))))
                  (prime-set-cdr! (chez-unbox last) entry)
                  (chez-set-box! last entry)
                  (if (> trial bound)
                      trial
                      (_-*- (+ trial 2))))
                (_-*- (+ trial 2))))))))

;; Given the size of a square matrix consisting only of +1's and -1's,
;; return an upper bound on the determinant.
(define det-upper-bound
  (lambda (size)
    (let ((main-part
           (expt size
                 (div size 2))))
      (if (even? size)
          main-part
          (* main-part
             (do ((i 0 (+ i 1)))
                 ((>= (* i i) size)
                  i)))))))

;; Fold over all maximal matrices.
(define go
  (lambda (number-of-cols inv-size folder state)
    (let* ((in-row-space?
            (make-modular-in-row-space?
             (find-prime
              (det-upper-bound inv-size))))
           (make-tester
            (lambda (mat)
              (let ((tests
                     (let ((old-mat
                            (cdr mat))
                           (new-row
                            (car mat)))
                       (fold-over-subs-of-size old-mat
                                               (- inv-size 2)
                                               (lambda (sub tests)
                                                 (cons
                                                  (in-row-space?
                                                   (cons new-row sub))
                                                  tests))
                                               '()))))
                (lambda (row)
                  (let _-*-
                      ((tests
                        tests))
                    (and (not (null? tests))
                         (or ((car tests) row)
                             (_-*- (cdr tests)))))))))
           (all-rows;; all rows starting with +1 in decreasing order
            (fold
             (fold-over-rows (- number-of-cols 1)
                             cons
                             '())
             (lambda (row rows)
               (cons (cons 1 row)
                     rows))
             '())))
      (let _-*-
          ((number-of-rows
            1)
           (rev-mat
            (list
             (car all-rows)))
           (possible-future
            (cdr all-rows))
           (state
            state))
        (let ((zulu-future
               (remove-in-order
                (if (< number-of-rows inv-size)
                    (in-row-space? rev-mat)
                    (make-tester rev-mat))
                possible-future)))
          (if (null? zulu-future)
              (folder (reverse rev-mat)
                      state)
              (let _-**-
                  ((zulu-future
                    zulu-future)
                   (state
                    state))
                (if (null? zulu-future)
                    state
                    (let ((rest-of-future
                           (cdr zulu-future)))
                      (_-**- rest-of-future
                             (let* ((first
                                     (car zulu-future))
                                    (new-rev-mat
                                     (cons first rev-mat)))
                               (if (maximal? (reverse new-rev-mat))
                                   (_-*- (+ number-of-rows 1)
                                         new-rev-mat
                                         rest-of-future
                                         state)
                                   state))))))))))))

(define go-folder
  (lambda (mat bsize.blen.blist)
    (let ((bsize
           (best-size bsize.blen.blist))
          (size
           (length mat)))
      (if (< size bsize)
          bsize.blen.blist
          (let ((blen
                 (best-count bsize.blen.blist))
                (blist
                 (best-answers bsize.blen.blist)))
            (if (= size bsize)
                (let ((blen
                       (+ blen 1)))
                  ;;                       (if
                  ;;                          (let _-*-
                  ;;                               ((blen
                  ;;                                   blen))
                  ;;                             (or (< blen 10)
                  ;;                                 (and (zero? (mod blen 10))
                  ;;                                      (_-*- (div blen 10)))))
                  ;;
                  ;;                          (begin
                  ;;                             (display blen)
                  ;;                             (display " of size ")
                  ;;                             (display bsize)
                  ;;                             (newline)))

                  (best bsize
                        blen
                              (cond ((< blen 3000)
                                     (cons (matrix-answer mat) blist))
                                    ((= blen 3000)
                                     (cons (marker-answer "...") blist))
                                    (else
                                     blist))))
                ;;                    (begin
                ;;                       (newline)
                ;;                       (display "First of size ")
                ;;                       (display size)
                ;;                       (display ":")
                ;;                       (newline)
                ;;                       (for-each
                ;;                          (lambda (row)
                ;;                             (display " ")
                ;;                             (for-each
                ;;                                (lambda (e)
                ;;                                   (case e
                ;;                                      ((1)
                ;;                                         (display "  1"))
                ;;                                      ((-1)
                ;;                                         (display " -1"))))
                ;;                                row)
                ;;                             (newline))
                ;;                          mat)

                (best size 1 (list (matrix-answer mat)))))))))

(define really-go
  (lambda (number-of-cols inv-size)
    (best-answers
     (go number-of-cols
         inv-size
         go-folder
         (best -1 -1 '())))))

(define remove-in-order
  (lambda (remove? lst)
    (reverse
     (fold lst
           (lambda (e lst)
             (if (remove? e)
                 lst
                 (cons e lst)))
           '()))))

;; The first fold-over-rows is slower than the second one, but folds
;; over rows in lexical order (large to small).
(define fold-over-rows
  (lambda (number-of-cols folder state)
    (if (zero? number-of-cols)
        (folder '()
                state)
        (fold-over-rows (- number-of-cols 1)
                        (lambda (tail state)
                          (folder (cons -1 tail)
                                  state))
                        (fold-over-rows (- number-of-cols 1)
                                        (lambda (tail state)
                                          (folder (cons 1 tail)
                                                  state))
                                        state)))))

;; Fold over subsets of a given size.
(define fold-over-subs-of-size
  (lambda (universe size folder state)
    (let ((usize
           (length universe)))
      (if (< usize size)
          state
          (let _-*-
              ((size
                size)
               (universe
                universe)
               (folder
                folder)
               (csize
                (- usize size))
               (state
                state))
            (cond ((zero? csize)
                   (folder universe state))
                  ((zero? size)
                   (folder '() state))
                  (else
                   (let ((first-u
                          (car universe))
                         (rest-u
                          (cdr universe)))
                     (_-*- size
                           rest-u
                           folder
                           (- csize 1)
                           (_-*- (- size 1)
                                 rest-u
                                 (lambda (tail state)
                                   (folder (cons first-u tail)
                                           state))
                                 csize
                                 state))))))))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (matrix-read-answers (read)))
         (s3 (number->string count))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "matrix"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2 ":" s3)
     count
     (lambda () (really-go (hide count input1) (hide count input2)))
     (lambda (result) (matrix-same-result? result output)))))

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
