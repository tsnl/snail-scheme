;; Tensor operations have one shape/dtype contract. Numeric compiled tensors
;; use unboxed runtime storage; object tensors retain ordinary Scheme GC values.
(define-library (snail-scheme iverson-ghost)
  (export array array? dtype shape size array-ref array->vector astype iota
          reshape transpose add sub mul div sum mean matmul gather scatter scatter-add)
  (import (scheme base))

  (cond-expand
   (snail-scheme
    (import (rename (only (snail-scheme core)
                          %iverson-array %iverson-array? %iverson-dtype %iverson-shape
                          %iverson-data %iverson-ref %iverson-iota %iverson-reshape
                          %iverson-cast %iverson-transpose %iverson-binary %iverson-reduce
                          %iverson-matmul %iverson-gather %iverson-scatter)
                    (%iverson-array dense-array) (%iverson-array? dense-array?)
                    (%iverson-dtype dense-dtype) (%iverson-shape dense-shape)
                    (%iverson-data dense-vector) (%iverson-ref dense-ref)
                    (%iverson-iota dense-iota) (%iverson-reshape dense-reshape)
                    (%iverson-cast dense-cast) (%iverson-transpose dense-transpose)
                    (%iverson-binary dense-binary) (%iverson-reduce dense-reduce)
                    (%iverson-matmul dense-matmul) (%iverson-gather dense-gather)
                    (%iverson-scatter dense-scatter)))))

  (begin

    ;; ---- Shape, dtype, and object storage ----

    ;; Private vectors retain tagged Scheme values in collector-visible fields.
    ;; Copies are shallow: slots are immutable, referenced objects keep identity.
    ;; Standard vectors remain mutable and participate as rank-one object tensors.
    (define-record-type <object-array>
      (make-object dimensions data) object-array?
      (dimensions object-shape) (data object-data))

    (define (object-tensor? value) (or (vector? value) (object-array? value)))
    (define (array? value) (or (object-tensor? value) (dense-array? value)))

    (define (checked-shape dimensions)
      (unless (list? dimensions) (error "array shape must be a list" dimensions))
      (map (lambda (d)
             (unless (and (exact-integer? d) (>= d 0))
               (error "array dimension must be an exact nonnegative integer" d))
             d)
           dimensions))

    (define (shape-size dimensions)
      (if (memv 0 dimensions) 0
          (let loop ((rest dimensions) (count 1))
            (if (null? rest) count (loop (cdr rest) (* count (car rest)))))))

    (define (dtype-code kind)
      (case kind ((f64) 0) ((f32) 1) ((i32) 2)
            (else (error "expected f64, f32, i32, or object dtype" kind))))

    (define (selected-dtype options)
      (let ((kind (if (null? options) 'f64 (car options))))
        (unless (or (null? options) (null? (cdr options))) (error "too many dtype arguments"))
        (unless (eq? kind 'object) (dtype-code kind))
        kind))

    (define (dtype value)
      (if (object-tensor? value) 'object
          (vector-ref '#(f64 f32 i32) (dense-dtype value))))

    (define (shape value)
      (cond ((vector? value) (list (vector-length value)))
            ((object-array? value) (append (object-shape value) '()))
            (else (vector->list (dense-shape value)))))

    (define (size value) (shape-size (shape value)))

    (define (generate-vector count procedure)
      (let ((data (make-vector count)))
        (let loop ((i 0))
          (when (< i count)
            (vector-set! data i (procedure i))
            (loop (+ i 1))))
        data))

    (define (copy-vector data)
      (generate-vector (vector-length data) (lambda (i) (vector-ref data i))))

    (define (flat-vector elements)
      (cond ((vector? elements) elements)
            ((list? elements) (list->vector elements))
            (else (error "array data must be a flat list or vector" elements))))

    (define (array dimensions elements . options)
      (let* ((dimensions (checked-shape dimensions)) (data (flat-vector elements))
             (kind (selected-dtype options)))
        (unless (= (shape-size dimensions) (vector-length data))
          (error "array shape does not match data length" dimensions))
        (if (eq? kind 'object) (make-object dimensions (copy-vector data))
            (dense-array (dtype-code kind) (list->vector dimensions) data))))

    (define (array->vector value)
      (cond ((vector? value) (copy-vector value))
            ((object-array? value) (copy-vector (object-data value)))
            (else (dense-vector value))))

    (define (index-offset dimensions indices)
      (unless (= (length dimensions) (length indices))
        (error "array index rank mismatch" indices dimensions))
      (let loop ((ds dimensions) (is indices) (offset 0))
        (if (null? ds) offset
            (let ((i (car is)) (d (car ds)))
              (unless (and (exact-integer? i) (<= 0 i) (< i d))
                (error "array index out of range" i d))
              (loop (cdr ds) (cdr is) (+ (* offset d) i))))))

    (define (array-ref value . indices)
      (let ((i (index-offset (shape value) indices)))
        (cond ((vector? value) (vector-ref value i))
              ((object-array? value) (vector-ref (object-data value) i))
              (else (dense-ref value i)))))

    (define (astype kind value)
      (if (or (eq? kind 'object) (object-tensor? value))
          (array (shape value) (array->vector value) kind)
          (dense-cast (dtype-code kind) value)))

    (define (iota count . options)
      (checked-shape (list count))
      (let ((kind (selected-dtype options)))
        (if (eq? kind 'object) (make-object (list count) (generate-vector count (lambda (i) i)))
            (dense-iota (dtype-code kind) count))))

    (define (reshape dimensions value)
      (let ((dimensions (checked-shape dimensions)))
        (unless (= (shape-size dimensions) (size value)) (error "reshape must preserve element count"))
        (cond ((vector? value) (make-object dimensions (copy-vector value)))
              ((object-array? value) (make-object dimensions (object-data value)))
              (else (dense-reshape (list->vector dimensions) value)))))

    ;; ---- Boxed shape kernels and dtype dispatch ----

    ;; These kernels handle object dtype in compiled programs and provide the
    ;; Chibi reference for numeric dtypes. Numeric compiled kernels do not box
    ;; elements or invoke these Scheme loops.
    (define (broadcast-shape a b)
      (let loop ((a (reverse a)) (b (reverse b)) (result '()))
        (cond ((null? a) (append (reverse b) result))
              ((null? b) (append (reverse a) result))
              (else
               (let* ((x (car a)) (y (car b))
                      (d (cond ((or (= x y) (= y 1)) x) ((= x 1) y)
                               (else (error "incompatible broadcast shapes" a b)))))
                 (loop (cdr a) (cdr b) (cons d result)))))))

    (define (row-strides dimensions)
      ;; Empty shapes have no reachable addresses. Their other dimensions can
      ;; be large, so do not multiply unused strides in a fixed-width runtime.
      (if (memv 0 dimensions) (make-list (length dimensions) 0)
          (let loop ((rest (reverse dimensions)) (stride 1) (result '()))
            (if (null? rest) result
                (loop (cdr rest) (* stride (car rest)) (cons stride result))))))

    (define (broadcast-strides dimensions rank)
      (append (make-list (- rank (length dimensions)) 0)
              (map (lambda (d stride) (if (= d 1) 0 stride)) dimensions (row-strides dimensions))))

    ;; Nonempty output shapes have positive dimensions, so division is safe.
    (define (broadcast-offset index dimensions strides)
      (let loop ((i index) (ds (reverse dimensions)) (ss (reverse strides)) (offset 0))
        (if (null? ds) offset
            (loop (quotient i (car ds)) (cdr ds) (cdr ss)
                  (+ offset (* (modulo i (car ds)) (car ss)))))))

    (define (binary-dtype a b)
      (cond ((or (object-tensor? a) (object-tensor? b)) 'object)
            ((and (array? a) (array? b) (not (eq? (dtype a) (dtype b))))
             (error "array dtype mismatch; use astype explicitly"))
            ((array? a) (dtype a)) ((array? b) (dtype b)) (else 'f64)))

    (define (normalize-result kind value)
      (cond ((eq? kind 'object) value)
            ((eq? kind 'i32) (- (modulo (+ value 2147483648) 4294967296) 2147483648))
            (else (array-ref (array '() (vector value) kind)))))

    (define (element-operation kind code a b)
      (normalize-result kind
                        (case code ((0) (+ a b)) ((1) (- a b)) ((2) (* a b))
                              ((3) (if (eq? kind 'object) (/ a b) (/ (inexact a) b))))))

    (define (operand-vector value kind)
      (if (array? value) (array->vector value)
          (if (eq? kind 'object) (vector value)
              (array->vector (array '() (vector value) kind)))))

    (define (operand-shape value) (if (array? value) (shape value) '()))

    (define (boxed-binary code a b)
      (let* ((input-kind (binary-dtype a b))
             (kind (if (and (= code 3) (eq? input-kind 'i32)) 'f64 input-kind))
             (as (operand-shape a)) (bs (operand-shape b))
             (dimensions (broadcast-shape as bs))
             (x (operand-vector a input-kind)) (y (operand-vector b input-kind))
             (sa (broadcast-strides as (length dimensions)))
             (sb (broadcast-strides bs (length dimensions))))
        (array dimensions
               (generate-vector (shape-size dimensions)
                                (lambda (i)
                                  (element-operation kind code
                                                     (vector-ref x (broadcast-offset i dimensions sa))
                                                     (vector-ref y (broadcast-offset i dimensions sb)))))
               kind)))

    (define (binary-operation code a b)
      (if (or (object-tensor? a) (object-tensor? b)) (boxed-binary code a b)
          (dense-binary code a b)))

    (define (add a b) (binary-operation 0 a b))
    (define (sub a b) (binary-operation 1 a b))
    (define (mul a b) (binary-operation 2 a b))
    (define (div a b) (binary-operation 3 a b))

    (define (boxed-transpose value)
      (let* ((dimensions (reverse (shape value))) (strides (reverse (row-strides (shape value))))
             (data (array->vector value)))
        (array dimensions
               (generate-vector (size value)
                                (lambda (i) (vector-ref data (broadcast-offset i dimensions strides))))
               (dtype value))))

    (define (transpose value)
      (if (object-tensor? value) (boxed-transpose value) (dense-transpose value)))

    ;; ---- Reductions and matrix multiplication ----

    (define (reduction-axis value options)
      (if (null? options) -1
          (let ((axis (car options)))
            (unless (and (null? (cdr options)) (exact-integer? axis)
                         (<= 0 axis) (< axis (length (shape value))))
              (error "expected one nonnegative array axis" options))
            axis)))

    (define (remove-axis dimensions axis)
      (if (= axis 0) (cdr dimensions)
          (cons (car dimensions) (remove-axis (cdr dimensions) (- axis 1)))))

    (define (sum-cell data count step base kind)
      (let loop ((k 0) (result (normalize-result kind 0)))
        (if (= k count) result
            (loop (+ k 1) (element-operation kind 0 result (vector-ref data (+ base (* k step))))))))

    (define (boxed-sum value axis kind)
      (let* ((dimensions (shape value)) (data (array->vector value))
             (output (if (= axis -1) '() (remove-axis dimensions axis)))
             (width (if (= axis -1) (size value) (list-ref dimensions axis)))
             (count (shape-size output))
             (inner (if (or (= axis -1) (= count 0) (= width 0)) 1
                        (shape-size (list-tail dimensions (+ axis 1))))))
        (array output
               (generate-vector count
                                (lambda (i)
                                  (if (= width 0) (normalize-result kind 0)
                                      (sum-cell data width inner
                                                (+ (* (quotient i inner) width inner) (modulo i inner)) kind))))
               kind)))

    (define (boxed-reduce code value axis)
      (let* ((kind (dtype value)) (kind (if (and (= code 1) (eq? kind 'i32)) 'f64 kind))
             (count (if (= axis -1) (size value) (list-ref (shape value) axis))))
        (when (and (= code 1) (= count 0)) (error "mean of an empty reduction"))
        (let ((result (boxed-sum value axis kind)))
          (if (= code 0) result (boxed-binary 3 result count)))))

    (define (reduction-operation code value options)
      (let ((axis (reduction-axis value options)))
        (if (object-tensor? value) (boxed-reduce code value axis) (dense-reduce code value axis))))

    (define (sum value . axis) (reduction-operation 0 value axis))
    (define (mean value . axis) (reduction-operation 1 value axis))

    (define (matrix-cell a b row column width columns kind)
      (let loop ((k 0) (result (normalize-result kind 0)))
        (if (= k width) result
            (loop (+ k 1)
                  (element-operation kind 0 result
                                     (element-operation kind 2 (vector-ref a (+ (* row width) k))
                                                        (vector-ref b (+ (* k columns) column))))))))

    (define (boxed-matmul a b)
      (unless (and (array? a) (array? b) (= (length (shape a)) 2) (= (length (shape b)) 2)
                   (= (list-ref (shape a) 1) (car (shape b))))
        (error "matmul requires compatible rank-two arrays"))
      (let* ((m (car (shape a))) (k (list-ref (shape a) 1)) (n (list-ref (shape b) 1))
             (kind (binary-dtype a b)) (x (array->vector a)) (y (array->vector b)))
        (array (list m n) (generate-vector (* m n)
                                           (lambda (i) (matrix-cell x y (quotient i n) (modulo i n) k n kind)))
               kind)))

    (define (matmul a b)
      (if (or (object-tensor? a) (object-tensor? b)) (boxed-matmul a b) (dense-matmul a b)))

    ;; ---- Gather and functional scatter ----

    ;; Indices address the flattened row-major source. Repeated scatter indices
    ;; are processed in index order: overwrite keeps the last, add accumulates.
    (define (checked-indices index length)
      (unless (and (array? index) (eq? (dtype index) 'i32)) (error "indices must be an i32 array"))
      (let ((data (array->vector index)))
        (let loop ((i 0))
          (when (< i (vector-length data))
            (unless (<= 0 (vector-ref data i) (- length 1)) (error "gather/scatter index out of range"))
            (loop (+ i 1))))
        data))

    (define (boxed-gather value index)
      (let ((indices (checked-indices index (size value))) (data (array->vector value)))
        (array (shape index)
               (generate-vector (size index) (lambda (i) (vector-ref data (vector-ref indices i))))
               (dtype value))))

    (define (gather value index)
      (if (object-tensor? value) (boxed-gather value index) (dense-gather value index)))

    (define (boxed-scatter code base index updates)
      (let* ((kind (dtype base)) (indices (checked-indices index (size base)))
             (data (array->vector base)) (values (operand-vector updates kind)))
        (unless (or (null? (operand-shape updates)) (equal? (operand-shape updates) (shape index)))
          (error "scatter updates must match index shape or be scalar"))
        (when (and (not (eq? kind 'object)) (array? updates) (not (eq? kind (dtype updates))))
          (error "scatter update dtype mismatch"))
        (scatter-slots! code data indices values kind)
        (array (shape base) data kind)))

    (define (scatter-slots! code data indices updates kind)
      (let loop ((k 0))
        (when (< k (vector-length indices))
          (let* ((i (vector-ref indices k))
                 (value (vector-ref updates (if (= (vector-length updates) 1) 0 k))))
            (vector-set! data i (if (= code 0) value (element-operation kind 0 (vector-ref data i) value))))
          (loop (+ k 1)))))

    (define (scatter-operation code base index updates)
      (if (object-tensor? base) (boxed-scatter code base index updates)
          (dense-scatter code base index updates)))

    (define (scatter base index updates) (scatter-operation 0 base index updates))
    (define (scatter-add base index updates) (scatter-operation 1 base index updates)))

  ;; ---- Chibi reference for numeric storage ----

  (cond-expand
   ((not snail-scheme)
    (begin
      (define-record-type <dense-array>
        (make-dense kind dimensions data) dense-array?
        (kind dense-kind) (dimensions dense-dimensions) (data dense-data))

      (define (binary-exponent value)
        (let loop ((x value) (e 0))
          (cond ((>= x 2.0) (loop (/ x 2.0) (+ e 1)))
                ((< x 1.0) (loop (* x 2.0) (- e 1)))
                (else e))))

      ;; Round to binary32, including ties to even, subnormals, and overflow.
      ;; The reference stores those rounded values in ordinary host vectors.
      (define (round-f32 value)
        (if (or (= value 0.0) (not (= value value)) (= (abs value) (string->number "+inf.0"))) value
            (let* ((magnitude (abs value)) (e (binary-exponent magnitude))
                   (quantum (expt 2.0 (if (< e -126) -149 (- e 23))))
                   (result (* quantum (round (/ magnitude quantum)))))
              (* (if (< value 0) -1.0 1.0)
                 (if (>= result (expt 2.0 128)) (string->number "+inf.0") result)))))

      (define (checked-element kind value)
        (unless (real? value) (error "numeric array requires real elements" value))
        (case kind ((f64) (inexact value)) ((f32) (round-f32 (inexact value)))
              ((i32)
               (unless (and (integer? value) (<= -2147483648 value 2147483647))
                 (error "i32 conversion requires an integer in range" value))
               (exact value))))

      (define (dense-array code dimensions data)
        (let ((kind (vector-ref '#(f64 f32 i32) code)))
          (make-dense kind (vector->list dimensions)
                      (generate-vector (vector-length data) (lambda (i) (checked-element kind (vector-ref data i)))))))

      (define (dense-operand value)
        (if (dense-array? value) value (array '() (vector value))))

      (define (dense-dtype value) (dtype-code (dense-kind (dense-operand value))))
      (define (dense-shape value) (list->vector (dense-dimensions (dense-operand value))))
      (define (dense-vector value) (copy-vector (dense-data (dense-operand value))))
      (define (dense-ref value index) (vector-ref (dense-data (dense-operand value)) index))

      (define (dense-iota code count)
        (when (and (= code 2) (> count 2147483648)) (error "i32 iota length out of range"))
        (array (list count) (generate-vector count (lambda (i) i)) (vector-ref '#(f64 f32 i32) code)))

      (define (dense-reshape dimensions value)
        (let ((value (dense-operand value)))
          (make-dense (dense-kind value) (vector->list dimensions) (dense-data value))))

      (define (dense-cast code value)
        (array (shape value) (array->vector value) (vector-ref '#(f64 f32 i32) code)))

      (define (dense-transpose value) (boxed-transpose value))
      (define (dense-binary code a b) (boxed-binary code a b))
      (define (dense-reduce code value axis) (boxed-reduce code value axis))
      (define (dense-matmul a b) (boxed-matmul a b))
      (define (dense-gather value index) (boxed-gather value index))
      (define (dense-scatter code base index updates) (boxed-scatter code base index updates)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-iverson-ghost)
    (import (snail-scheme test-utils))
    (begin
      (define (expect-array value dimensions elements)
        (expect (shape value) dimensions)
        (expect (array->vector value) elements))

      (define (rejects? thunk)
        (guard (ex ((error-object? ex) #t)) (thunk) #f))

      (define (test-array-ownership)
        (let* ((dimensions (list 2 2)) (data (vector 1 2 3 4)) (a (array dimensions data)))
          (set-car! dimensions 9)
          (vector-set! data 0 99)
          (set-car! (shape a) 8)
          (vector-set! (array->vector a) 0 88)
          (expect-array a '(2 2) '#(1.0 2.0 3.0 4.0))
          (expect (array-ref a 1 0) 3.0)
          (expect (array? a) #t)
          (expect (array? 1) #f)))

      (define (test-array-broadcasting)
        (let ((a (array '(2 1) '(1 2))) (b (array '(3) '(10 20 30))))
          (expect-array (add a b) '(2 3) '#(11.0 21.0 31.0 12.0 22.0 32.0))
          (expect-array (sub 100 b) '(3) '#(90.0 80.0 70.0))
          (expect-array (mul b 2) '(3) '#(20.0 40.0 60.0))
          (expect-array (div b 2) '(3) '#(5.0 10.0 15.0))
          (expect-array (add (array '(2 1 1) '(1 2)) (array '(3 2) '(1 2 3 4 5 6)))
                        '(2 3 2) '#(2.0 3.0 4.0 5.0 6.0 7.0 3.0 4.0 5.0 6.0 7.0 8.0))))

      (define (test-array-structure)
        (let ((a (reshape '(2 3) (iota 6))))
          (expect-array (reshape '(3 2) a) '(3 2) '#(0.0 1.0 2.0 3.0 4.0 5.0))
          (expect-array (transpose a) '(3 2) '#(0.0 3.0 1.0 4.0 2.0 5.0))
          (expect-array (transpose (reshape '(2 1 3) (iota 6)))
                        '(3 1 2) '#(0.0 3.0 1.0 4.0 2.0 5.0))
          (expect-array (add 2 3) '() '#(5.0))
          (expect (array-ref (sum a)) 15.0)))

      (define (test-array-reductions)
        (let ((a (array '(2 3) '(1 2 3 4 5 6))))
          (expect-array (sum a 0) '(3) '#(5.0 7.0 9.0))
          (expect-array (sum a 1) '(2) '#(6.0 15.0))
          (expect-array (mean a 1) '(2) '#(2.0 5.0))
          (expect-array (mean a) '() '#(3.5))
          (expect-array (mean 7) '() '#(7.0))))

      (define (test-empty-arrays)
        (let ((a (array '(2 0 3) '())))
          (expect (size a) 0)
          (expect-array (add a (array '(1 3) '(1 2 3))) '(2 0 3) '#())
          (expect-array (sum a 1) '(2 3) '#(0.0 0.0 0.0 0.0 0.0 0.0))
          (expect-array (mean a 2) '(2 0) '#())
          (expect-array (sum a) '() '#(0.0))
          (expect-array (transpose a) '(3 0 2) '#())
          (expect (rejects? (lambda () (mean a 1))) #t)
          (expect (rejects? (lambda () (mean a))) #t)))

      (define (test-array-matmul)
        (let ((a (array '(2 3) '(1 2 3 4 5 6)))
              (b (array '(3 3) '(1 2 3 4 5 6 7 8 9))))
          (expect-array (matmul a b) '(2 3) '#(30.0 36.0 42.0 66.0 81.0 96.0)))
        (expect-array (matmul (array '(2 0) '()) (array '(0 3) '()))
                      '(2 3) '#(0.0 0.0 0.0 0.0 0.0 0.0)))

      (define (test-large-empty-shapes)
        (for-each
         (lambda (kind)
           (let ((value (array '(0 2097152 2097152 2097152) '() kind)))
             (expect-array (transpose value) '(2097152 2097152 2097152 0) '#())
             (expect-array (add value 1) '(0 2097152 2097152 2097152) '#())
             (expect-array (sum (reshape '(0 1 2097152 2097152 2097152) value) 1)
                           '(0 2097152 2097152 2097152) '#())))
         '(object f64 f32 i32)))

      (define (test-floating-zero-sign)
        (let ((negative-zero (string->number "-0.0")) (negative-infinity (string->number "-inf.0")))
          (for-each
           (lambda (kind)
             (let ((value (array '(1) (vector negative-zero) kind)))
               (expect (= (array-ref (div 1 value) 0) negative-infinity) #t)
               (expect (= (array-ref (div 1 (div value 1)) 0) negative-infinity) #t)))
           '(f64 f32))))

      (define (test-object-tensors)
        (let* ((nested (vector 'value)) (data (vector 1 "two" nested))
               (a (array '(3) data 'object)) (view (reshape '(1 3) a)))
          (vector-set! data 0 9)
          (vector-set! (array->vector view) 1 "changed")
          (expect (dtype data) 'object)
          (expect (shape data) '(3))
          (expect (array? data) #t)
          (expect (array-ref a 0) 1)
          (expect (array-ref view 0 1) "two")
          (expect (eq? (array-ref view 0 2) nested) #t)
          (vector-set! nested 0 'mutated)
          (expect (array-ref a 2) '#(mutated)))
        (let* ((v (vector 1 2)) (a (reshape '(2 1) v)))
          (vector-set! v 0 9)
          (expect-array a '(2 1) '#(1 2)))
        (expect-array (add '#(1 2) 3) '(2) '#(4 5))
        (expect-array (mean '#(1 2)) '() (vector (string->number "3/2")))
        (expect-array (scatter '#(a b) (iota 1 'i32) 'c) '(2) '#(c b)))

      (define (test-array-dtypes)
        (for-each
         (lambda (kind)
           (let* ((a (array '(2 2) '(1 2 3 4) kind)) (total (sum a 0)))
             (expect (dtype a) kind)
             (expect (dtype (add a 2)) kind)
             (expect (dtype (transpose a)) kind)
             (expect (dtype (matmul a a)) kind)
             (expect (dtype total) kind)
             (expect (array-ref total 0) (if (eq? kind 'i32) 4 4.0))
             (expect (dtype (mean a)) (if (eq? kind 'i32) 'f64 kind))
             (expect (dtype (astype 'object a)) 'object)
             (expect (dtype (astype kind (astype 'object a))) kind)))
         '(f64 f32 i32))
        (let ((a (array '(1) '(16777217) 'f32)))
          (expect-array a '(1) '#(16777216.0))
          (expect-array (add a 1) '(1) '#(16777216.0)))
        (expect-array (add (array '(1) '(2147483647) 'i32) 1) '(1) '#(-2147483648))
        (expect-array (sum (array '(2) '(2147483647 2147483647) 'i32)) '() '#(-2))
        (expect-array (mean (array '(2) '(2147483647 2147483647) 'i32)) '() '#(2147483647.0))
        (expect-array (div (array '(2) '(1 3) 'i32) 2) '(2) '#(0.5 1.5))
        (expect (dtype (div (iota 0 'i32) 2)) 'f64))

      (define (test-array-indexing)
        (for-each
         (lambda (kind)
           (let* ((a (array '(3) '(10 20 30) kind))
                  (index (array '(3) '(2 0 2) 'i32))
                  (updates (array '(3) '(1 2 3) kind))
                  (number (if (memq kind '(object i32)) (lambda (x) x) (lambda (x) (+ 0.0 x)))))
             (expect-array (gather a index) '(3) (list->vector (map number '(30 10 30))))
             (expect-array (scatter a index updates) '(3) (list->vector (map number '(2 20 3))))
             (expect-array (scatter-add a index updates) '(3) (list->vector (map number '(12 20 34))))
             (expect-array (scatter-add a index 1) '(3) (list->vector (map number '(11 20 32))))
             (expect-array a '(3) (list->vector (map number '(10 20 30))))
             (expect (dtype (gather a (iota 0 'i32))) kind)
             (expect (shape (gather a (reshape '(1 3) index))) '(1 3))))
         '(object f64 f32 i32)))

      (define (test-object-promotion)
        (let ((a (array '(1) '(16777216) 'f32)) (one (array '() '(1) 'object)))
          (expect-array (add a one) '(1) '#(16777217.0))
          (expect (dtype (add a one)) 'object)
          (expect-array (scatter '#(0) (iota 1 'i32) a) '(1) '#(16777216.0)))
        (let* ((v (vector 1 2)) (a (astype 'object v)))
          (vector-set! v 0 9)
          (expect-array a '(2) '#(1 2)))
        (expect-array (gather (array '(2 2) '(1 2 3 4) 'i32) (array '() '(3) 'i32)) '() '#(4))
        (expect-array (scatter-add (array '(1) '(16777216) 'f32)
                                   (array '(2) '(0 0) 'i32) (array '(2) '(1 -16777216) 'f32)) '(1) '#(0.0)))

      (define (test-dtype-and-index-errors)
        (for-each
         (lambda (thunk) (expect (rejects? thunk) #t))
         (list (lambda () (array '(1) '(1.5) 'i32))
               (lambda () (array '(1) '(2147483648) 'i32))
               (lambda () (array '(1) '(1) 'unknown))
               (lambda () (array '(1) '(1) 'f32 'f64))
               (lambda () (astype 'i32 (array '(1) '(1.5))))
               (lambda () (add (iota 2 'f32) (iota 2 'f64)))
               (lambda () (add (iota 0 'f32) (iota 0 'f64)))
               (lambda () (div (iota 2 'i32) 1.5))
               (lambda () (div (iota 0 'i32) 1.5))
               (lambda () (iota 2147483649 'i32))
               (lambda () (gather (iota 2) (iota 1)))
               (lambda () (gather (iota 2) 1))
               (lambda () (gather (iota 2) (array '(1) '(-1) 'i32)))
               (lambda () (gather '#(a b) (array '(1) '(2) 'i32)))
               (lambda () (scatter (iota 3 'i32) (iota 2 'i32) (iota 2 'f32)))
               (lambda () (scatter (iota 3 'f32) (iota 0 'i32) '#()))
               (lambda () (scatter (iota 3) (reshape '(2 0) (iota 0 'i32)) (iota 0)))
               (lambda () (scatter (iota 3) (iota 2 'i32) (iota 3))))))

      (define (test-array-errors)
        (for-each (lambda (thunk) (expect (rejects? thunk) #t))
                  (list (lambda () (array '(2) '(1)))
                        (lambda () (array '(-1) '()))
                        (lambda () (array '(1.0) '(1)))
                        (lambda () (array '(1) '(bad)))
                        (lambda () (reshape '(3) (iota 2)))
                        (lambda () (add (iota 2) (iota 3)))
                        (lambda () (array-ref (iota 2) -1))
                        (lambda () (array-ref (iota 2)))
                        (lambda () (sum (iota 2) 1))
                        (lambda () (sum (iota 2) -1))
                        (lambda () (sum (iota 2) 0 0))
                        (lambda () (matmul (iota 2) (iota 2))))))

      (define (test-iverson-ghost)
        (run-test test-array-ownership)
        (run-test test-array-broadcasting)
        (run-test test-array-structure)
        (run-test test-array-reductions)
        (run-test test-empty-arrays)
        (run-test test-large-empty-shapes)
        (run-test test-floating-zero-sign)
        (run-test test-array-matmul)
        (run-test test-object-tensors)
        (run-test test-array-dtypes)
        (run-test test-array-indexing)
        (run-test test-object-promotion)
        (run-test test-dtype-and-index-errors)
        (run-test test-array-errors))))))
