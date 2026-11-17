;; Evaluating a tensor graph on the CPU: the executable specification of
;; each kind of node, which the GPU's kernels are tested against and which
;; checks gradients by finite differences without a device. Every port is
;; an array of F64, row-major; an F32 result is rounded to single
;; precision and a U32 or I32 one wrapped to 32 bits, as the GPU computes
;; them. A custom node has no CPU form, so a graph with one is not
;; evaluated here.
;;
;;   (evaluate (list loss) inputs)   ; inputs: each param's array, by name
(define-library (snail shell tensor eval)
  (export
   evaluate
   bytes->values
   values->bytes)
  (import
   (snail core base)
   (snail core table)
   (only (snail shell math) exp log sin cos expt)
   (rename (snail shell tensor)
           (exp tensor-exp)
           (log tensor-log)
           (sin tensor-sin)
           (cos tensor-cos)))
  (begin

    ;; ---- Evaluating ----

    ;; Each root's elements, in order, given each param's by name.

    (define (evaluate (roots (List View)) (inputs (Table (Array F64)))) (→ (List (Array F64)))
      (let ((ports (fold-left (lambda (ports n) (evaluated n ports inputs))
                              (empty-table)
                              (toposort roots))))
        (map (lambda (root)
               (array-generate (element-count root)
                               (lambda (i) (element ports root (unflatten i (shape-of root))))))
             roots)))

    ;; The ports with this node's added, each by node key and port.

    (define (evaluated (n Node) (ports (Table (Array F64))) (inputs (Table (Array F64))))
      (→ (Table (Array F64)))
      (fold-left (lambda (ports pair)
                   (table-set ports (port-key n (● (● pair first) name)) (● pair second)))
                 ports
                 (zip (● n ports) (computed n ports inputs))))

    (define (port-key (n Node) (port String)) (→ String) (string-append (● n key) "." port))

    ;; Element `index` of a view, read through its accessor.
    (define (element (ports (Table (Array F64))) (view View) (index (List I64))) (→ F64)
      (match (table-ref ports (port-key (● view node) (● view port)))
        ((Some values)
         (array-ref values
                    (fold-left +
                               (● view accessor offset)
                               (map (lambda (pair) (* (● pair first) (● pair second)))
                                    (zip index (● view accessor pitch))))))
        ((None) (panic "eval: a port read before its node"))))

    ;; Flat index i as an index into `shape`, row-major.
    (define (unflatten (i I64) (shape (List I64))) (→ (List I64))
      (map (lambda (pair) (remainder (quotient i (● pair second)) (● pair first)))
           (zip shape (contiguous-pitch shape))))

    (define (dense-of (n Node) (port String) (f (Fn (List I64) → F64))) (→ (Array F64))
      (let ((shape (● (port-of n port) shape)))
        (array-generate (product shape) (lambda (i) (f (unflatten i shape))))))

    ;; ---- Kinds ----

    ;; Each port's values, in the node's port order.

    (define (computed (n Node) (ports (Table (Array F64))) (inputs (Table (Array F64))))
      (→ (List (Array F64)))
      (let ((arg (lambda (k) (list-ref (● n args) k)))
            (out (● (car-of (● n ports)) etype)))
        (match (● n kind)
          ((Param name) (list (input-of inputs name)))
          ((Constant _ data) (list (bytes->values data out)))
          ((Fill value) (list (dense-of n default-port (lambda (_) (rounded out value)))))
          ((Elementwise op)
           (list (dense-of n default-port
                           (lambda (index)
                             (operated op (etype-of (arg 0)) out
                                       (map (lambda (a) (element ports a index)) (● n args)))))))
          ((Reduce op axes)
           (list (dense-of n default-port (lambda (index) (reduced ports op axes (arg 0) index)))))
          ((Matmul)
           (list
            (dense-of n default-port (lambda (index) (product-at ports (arg 0) (arg 1) index)))))
          ((Copy) (list (dense-of n default-port (lambda (index) (element ports (arg 0) index)))))
          ((Place accessor)
           (list (placed ports (arg 0) accessor (product (● (car-of (● n ports)) shape)))))
          ((Gather)
           (list (dense-of n default-port
                           (lambda (index)
                             (element ports (arg 0)
                                      (Cons (f64->i64 (element ports (arg 1) (list (car-of index))))
                                            (cdr-of index)))))))
          ((ScatterAdd _)
           (list
            (dense-of n default-port (lambda (index) (scattered ports (arg 0) (arg 1) index)))))
          ((Concat axis)
           (list (dense-of n default-port (lambda (index) (joined ports (● n args) axis index)))))
          ((Sort bits) (sorted ports (arg 0) (arg 1) bits))
          ((PrefixSum) (list (scanned ports (arg 0))))
          ((CustomKind c)
           (panic (string-append "eval: custom node " (● c name) " has no CPU form"))))))

    (define (input-of (inputs (Table (Array F64))) (name String)) (→ (Array F64))
      (match (table-ref inputs name)
        ((Some values) values)
        ((None) (panic (string-append "eval: no input for param " name)))))

    (define (car-of (items (List T))) (→ T) (∀ (T))
      (match items
        ((Cons item _) item)
        ((Nil) (panic "eval: empty list"))))

    (define (cdr-of (items (List T))) (→ (List T)) (∀ (T))
      (match items
        ((Cons _ rest) rest)
        ((Nil) (Nil))))

    ;; Every element of the reduced axes, combined; `index` has 0 there.
    (define (reduced (ports (Table (Array F64)))
                     (op Reduction)
                     (axes (List I64))
                     (a View)
                     (index (List I64)))
      (→ F64)
      (let* ((shape (shape-of a))
             (spans
              (map (lambda (k) (if (member? k axes) (list-ref shape k) 1)) (iota (length shape))))
             (values (map (lambda (j)
                            (element ports a (map (lambda (pair) (+ (● pair first) (● pair second)))
                                                  (zip index (unflatten j spans)))))
                          (iota (product spans)))))
        (rounded (etype-of a)
                 (match op
                   ((Sum) (fold-left + 0.0 values))
                   ((Largest) (fold-left max (car-of values) values))
                   ((Smallest) (fold-left min (car-of values) values))))))

    (define (product-at (ports (Table (Array F64))) (a View) (b View) (index (List I64))) (→ F64)
      (let* ((n (length index))
             (lead (take index (- n 2)))
             (i (list-ref index (- n 2)))
             (j (list-ref index (- n 1)))
             (k (list-ref (shape-of a) (- n 1))))
        (rounded (etype-of a)
                 (fold-left (lambda (sum m)
                              (+ sum (* (element ports a (append lead (list i m)))
                                        (element ports b (append lead (list m j))))))
                            0.0
                            (iota k)))))

    ;; Row `index[0]` gathers every source row whose index names it.
    (define (scattered (ports (Table (Array F64))) (source View) (indices View) (index (List I64)))
      (→ F64)
      (rounded (etype-of source)
               (fold-left (lambda (sum i)
                            (if (= (f64->i64 (element ports indices (list i))) (car-of index))
                                (+ sum (element ports source (Cons i (cdr-of index))))
                                sum))
                          0.0
                          (iota (car-of (shape-of source))))))

    ;; The argument whose span of `axis` holds the index, at the index
    ;; within its span.
    (define (joined (ports (Table (Array F64))) (args (List View)) (axis I64) (index (List I64)))
      (→ F64)
      (let ((at (list-ref index axis)))
        (match args
          ((Cons a rest)
           (let ((size (list-ref (shape-of a) axis)))
             (if (< at size)
                 (element ports a index)
                 (joined ports
                         rest
                         axis
                         (map-indexed (lambda (k i) (if (= k axis) (- i size) i)) index)))))
          ((Nil) (panic "eval: an index past a concat")))))

    ;; Pairs in order of their keys' low bits, equal keys in their order.
    (define (sorted (ports (Table (Array F64))) (keys View) (values View) (bits I64))
      (→ (List (Array F64)))
      (let* ((low (lambda (key)
                    (if (= bits 32) key (i64->f64 (remainder (f64->i64 key) (expt-i 2 bits))))))
             (pairs (list-sort (lambda (a b) (< (low (● a first)) (low (● b first))))
                               (map (lambda (i) (new Pair
                                                  (first (element ports keys (list i)))
                                                  (second (element ports values (list i)))))
                                    (iota (element-count keys))))))
        (list (list->array (map (lambda (pair) (● pair first)) pairs))
              (list->array (map (lambda (pair) (● pair second)) pairs)))))

    ;; Zeros, with each element of `g` at its address under `accessor`.
    (define (placed (ports (Table (Array F64))) (g View) (accessor Accessor) (count I64))
      (→ (Array F64))
      (unsafe-total
       (lambda ()
         (let ((out (make-array count 0.0)))
           (for-each (lambda (i)
                       (let ((index (unflatten i (shape-of g))))
                         (array-set! out
                                     (fold-left + (● accessor offset)
                                                (map
                                                 (lambda (pair) (* (● pair first) (● pair second)))
                                                 (zip index (● accessor pitch))))
                                     (element ports g index))))
                     (iota (element-count g)))
           out))))

    (define (expt-i (base I64) (power I64)) (→ I64)
      (if (= power 0) 1 (* base (expt-i base (- power 1)))))

    (define (scanned (ports (Table (Array F64))) (a View)) (→ (Array F64))
      (list->array (reverse (● (fold-left (lambda (state i)
                                            (new Pair
                                              (first (Cons (● state second) (● state first)))
                                              (second (rounded (Unsigned)
                                                               (+ (● state second)
                                                                  (element ports a (list i)))))))
                                          (new Pair (first (Nil)) (second 0.0))
                                          (iota (element-count a)))
                               first))))

    ;; ---- Elements ----

    ;; An operation on its operands' values, of type `from`, answering
    ;; type `to`.

    (define (operated (op Op) (from Etype) (to Etype) (xs (List F64))) (→ F64)
      (let ((a (car-of xs))
            (b (if (null? (cdr-of xs)) 0.0 (car-of (cdr-of xs))))
            (float (float? from)))
        (rounded to
                 (match op
                   ((Neg) (negate a))
                   ((Exp) (exp a))
                   ((Log) (log a))
                   ((Sqrt) (sqrt a))
                   ((Sin) (sin a))
                   ((Cos) (cos a))
                   ((Abs) (abs a))
                   ((Floor) (floor a))
                   ((Sign) (cond ((> a 0.0) 1.0) ((< a 0.0) -1.0) (else 0.0)))
                   ((Add) (+ a b))
                   ((Sub) (- a b))
                   ((Mul) (* a b))
                   ((Div) (if float (/ a b) (i64->f64 (quotient (f64->i64 a) (f64->i64 b)))))
                   ((Pow) (expt a b))
                   ((Max) (max a b))
                   ((Min) (min a b))
                   ((Less) (truth (< a b)))
                   ((LessEqual) (truth (<= a b)))
                   ((Greater) (truth (> a b)))
                   ((GreaterEqual) (truth (>= a b)))
                   ((Equal) (truth (= a b)))
                   ((NotEqual) (truth (not (= a b))))
                   ((BitAnd) (i64->f64 (i64-and (f64->i64 a) (f64->i64 b))))
                   ((BitOr) (i64->f64 (i64-or (f64->i64 a) (f64->i64 b))))
                   ((BitXor) (i64->f64 (i64-xor (f64->i64 a) (f64->i64 b))))
                   ((ShiftLeft) (i64->f64 (i64-shift-left (f64->i64 a) (f64->i64 b))))
                   ((ShiftRight) (i64->f64 (i64-shift-right (f64->i64 a) (f64->i64 b))))
                   ((Select) (if (= a 0.0) (list-ref xs 2) b))
                   ((Convert _) (if (float? to) a (truncate a)))
                   ((Bitcast _) (bitcast-value from to a))))))

    (define (truth (value Bool)) (→ F64) (if value 1.0 0.0))

    (define (float? (etype Etype)) (→ Bool)
      (match etype
        ((Float) #t)
        (_ #f)))

    ;; A value as its type holds it: single precision, or wrapped to 32
    ;; bits.
    (define (rounded (etype Etype) (value F64)) (→ F64)
      (match etype
        ((Float) (f32->f64 (f64->f32 value)))
        ((Unsigned) (i64->f64 (modulo (f64->i64 value) 4294967296)))
        ((Signed) (i64->f64 (- (modulo (+ (f64->i64 value) 2147483648) 4294967296) 2147483648)))))

    ;; The same 32 bits read as another type.
    (define (bitcast-value (from Etype) (to Etype) (value F64)) (→ F64)
      (let ((bits (match from
                    ((Float) (i32->i64 (f32->bits (f64->f32 value))))
                    (_ (f64->i64 value)))))
        (match to
          ((Float)
           (f32->f64 (bits->f32 (i64->i32 (- (modulo (+ bits 2147483648) 4294967296) 2147483648)))))
          (_ (rounded to (i64->f64 bits))))))

    ;; ---- Bytes ----

    ;; 32-bit little-endian words, as a buffer holds them.

    (define (bytes->values (data Bytes) (etype Etype)) (→ (Array F64))
      (array-generate (quotient (array-length data) 4)
                      (lambda (i)
                        (let ((word (fold-left (lambda (word k)
                                                 (+ (* word 256)
                                                    (i32->i64
                                                     (u8->i32 (array-ref data (+ (* 4 i) k))))))
                                               0
                                               (list 3 2 1 0))))
                          (bitcast-value (Unsigned) etype (i64->f64 word))))))

    (define (values->bytes (values (Array F64)) (etype Etype)) (→ Bytes)
      (array-generate (* 4 (array-length values))
                      (lambda (b)
                        (let ((word (f64->i64 (bitcast-value etype
                                                             (Unsigned)
                                                             (array-ref values (quotient b 4))))))
                          (i32->u8 (i64->i32 (remainder (quotient word (expt-i 256 (remainder b 4)))
                                                        256)))))))

    ))
