;; Tensors as a graph, built lazily and compiled explicitly, in the shape of
;; Resin's DSL: a program composes nodes, each writing one dense buffer a
;; port, and works with views of those ports. Symbolic passes rewrite the
;; graph: (snail shell tensor grad) builds the gradient as more nodes, and
;; (snail shell tensor adam) builds an optimizer's update the same way.
;; (snail shell tensor compile) turns the nodes a program asks for into
;; buffers and WebGPU dispatches, once, and runs them as often as it likes;
;; (snail shell tensor eval) evaluates the same graph on the CPU, as the
;; specification the kernels are tested against.
;;
;;   (let* ((x (param "x" (list 64 3) (Float)))
;;          (w (param "w" (list 3 1) (Float)))
;;          (loss (mean (square (- (matmul x w) (param "y" (list 64 1) (Float)))))))
;;     (grad loss (list w)))                       ; one view: dloss/dw
;;
;; A view is an accessor over a port: an offset, a shape, and a pitch per
;; axis in elements, so slicing, transposing and broadcasting (pitch 0)
;; make no node. An operation on views makes a node whose arguments are
;; those views; one that needs dense input, such as a sort, densifies a
;; view with a copy first.
;;
;; A node is known by its key, a hash of what it computes: its kind and
;; parameters and its arguments' keys and accessors. Building the same
;; computation twice builds the same node, so a graph shares its common
;; parts; a param is known by its name. Keys are 64-bit, so two different
;; nodes collide with odds of about 2^-64 a pair.
(define-library (snail shell tensor)
  (export
   Etype
   Float
   Unsigned
   Signed
   etype-wgsl
   same-etype?
   Accessor
   dense-accessor
   contiguous-pitch
   product
   Port
   Op
   Neg
   Exp
   Log
   Sqrt
   Sin
   Cos
   Abs
   Floor
   Sign
   Add
   Sub
   Mul
   Div
   Pow
   Max
   Min
   Less
   LessEqual
   Greater
   GreaterEqual
   Equal
   NotEqual
   BitAnd
   BitOr
   BitXor
   ShiftLeft
   ShiftRight
   Select
   Convert
   Bitcast
   Reduction
   Sum
   Largest
   Smallest
   Kernel
   Custom
   Kind
   Param
   Constant
   Fill
   Elementwise
   Reduce
   Matmul
   Copy
   Place
   Gather
   Concat
   ScatterAdd
   Sort
   PrefixSum
   CustomKind
   Node
   View
   View-accessor-set
   default-port
   view-key
   port-of
   shape-of
   etype-of
   rank
   element-count
   identity?
   dense?
   param
   constant
   fill
   scalar
   zeros-like
   ones-like
   unary
   binary
   exp
   log
   sin
   cos
   sign
   absolute
   square
   sigmoid
   maximum
   minimum
   power
   less
   less-equal
   greater
   greater-equal
   equal
   not-equal
   where
   convert
   bitcast
   reduce
   sum
   sum-all
   mean
   amax
   amin
   matmul
   copy
   place
   reshape
   permute
   transpose
   narrow
   broadcast-to
   squeeze
   unsqueeze
   gather
   concat
   stack
   scatter-add
   sort-pairs
   exclusive-scan
   custom
   node-view
   toposort)
  (import
   (snail core base)
   (snail core table))
  (begin

    ;; ---- Element types ----

    (enum Etype
      (Float)
      (Unsigned)
      (Signed))

    (define (etype-wgsl (etype Etype)) (→ String)
      (match etype
        ((Float) "f32")
        ((Unsigned) "u32")
        ((Signed) "i32")))

    (define (same-etype? (a Etype) (b Etype)) (→ Bool)
      (string=? (etype-wgsl a) (etype-wgsl b)))

    ;; ---- Accessors ----

    ;; Where a view's elements sit in its port's buffer: element
    ;; (i0, i1, ...) at offset + i0 p0 + i1 p1 + ..., counted in elements.
    (record Accessor
      ((offset I64)
       (shape (List I64))
       (pitch (List I64))))

    (define (product (shape (List I64))) (→ I64) (fold-left * 1 shape))

    ;; Row-major pitches: the last axis is adjacent.
    (define (contiguous-pitch (shape (List I64))) (→ (List I64))
      (match shape
        ((Nil) (Nil))
        ((Cons _ rest) (Cons (product rest) (contiguous-pitch rest)))))

    (define (dense-accessor (shape (List I64))) (→ Accessor)
      (new Accessor (offset 0) (shape shape) (pitch (contiguous-pitch shape))))

    (define (accessor-text (accessor Accessor)) (→ String)
      (string-append (show (● accessor offset))
                     ":"
                     (string-join (map show (● accessor shape)) ",")
                     ":"
                     (string-join (map show (● accessor pitch)) ",")))

    ;; ---- Operations ----

    ;; Elementwise operations. A comparison answers 1 or 0 in its operands'
    ;; type; `Select` takes a condition, then the value where it is not 0,
    ;; then the value where it is.
    (enum Op
      (Neg)
      (Exp)
      (Log)
      (Sqrt)
      (Sin)
      (Cos)
      (Abs)
      (Floor)
      (Sign)
      (Add)
      (Sub)
      (Mul)
      (Div)
      (Pow)
      (Max)
      (Min)
      (Less)
      (LessEqual)
      (Greater)
      (GreaterEqual)
      (Equal)
      (NotEqual)
      (BitAnd)
      (BitOr)
      (BitXor)
      (ShiftLeft)
      (ShiftRight)
      (Select)
      (Convert ((to Etype)))
      (Bitcast ((to Etype))))

    (define (op-text (op Op)) (→ String)
      (match op
        ((Neg) "neg")
        ((Exp) "exp")
        ((Log) "log")
        ((Sqrt) "sqrt")
        ((Sin) "sin")
        ((Cos) "cos")
        ((Abs) "abs")
        ((Floor) "floor")
        ((Sign) "sign")
        ((Add) "add")
        ((Sub) "sub")
        ((Mul) "mul")
        ((Div) "div")
        ((Pow) "pow")
        ((Max) "max")
        ((Min) "min")
        ((Less) "lt")
        ((LessEqual) "le")
        ((Greater) "gt")
        ((GreaterEqual) "ge")
        ((Equal) "eq")
        ((NotEqual) "ne")
        ((BitAnd) "and")
        ((BitOr) "or")
        ((BitXor) "xor")
        ((ShiftLeft) "shl")
        ((ShiftRight) "shr")
        ((Select) "select")
        ((Convert to) (string-append "convert " (etype-wgsl to)))
        ((Bitcast to) (string-append "bitcast " (etype-wgsl to)))))

    (enum Reduction
      (Sum)
      (Largest)
      (Smallest))

    (define (reduction-text (op Reduction)) (→ String)
      (match op
        ((Sum) "sum")
        ((Largest) "max")
        ((Smallest) "min")))

    ;; ---- Custom kernels ----

    ;; One dispatch of a custom node: WGSL whose bindings 0, 1, ... are the
    ;; node's arguments, dense, then its ports, as `array<T>` storage, and
    ;; whose entry runs `workgroups` workgroups. More than 65535 are laid
    ;; out in rows, so a kernel finds its workgroup's index as
    ;; `wid.y * nwg.x + wid.x` from `workgroup_id` and `num_workgroups`.
    ;; `bindings` are those its entry uses, since a pipeline's layout has
    ;; only those. Every port is zeros when the first kernel starts.
    (record Kernel
      ((code String)
       (entry String)
       (bindings (List I64))
       (workgroups I64)))

    ;; A node whose kernels a library writes: its name and parameters make
    ;; its key; its kernels run in order; `adjoint` answers the gradient of
    ;; each argument, given the arguments and the gradient of each port,
    ;; or None for one with no gradient, such as an index.
    (record Custom
      ((name String)
       (kernels (List Kernel))
       (adjoint (Fn (List View) (List (Option View)) → (List (Option View))))))

    ;; ---- Nodes ----

    ;; What a node computes. A `Fill` is every element one value; a
    ;; `Place` writes its argument into zeros at the addresses an accessor
    ;; gives, the adjoint of seeing a port through that accessor; a
    ;; `Gather` takes the rows of its first argument at the indices of its
    ;; second; a `ScatterAdd` adds each row of its first argument to row
    ;; `index` of `rows` zero rows; a `Concat` joins its arguments along an
    ;; axis; a `Sort` sorts u32 keys and values on
    ;; their low `bits` bits, stably; a `PrefixSum` replaces each u32
    ;; number by the sum of those before it.
    (enum Kind
      (Param ((name String)))
      (Constant ((name String) (data Bytes)))
      (Fill ((value F64)))
      (Elementwise ((op Op)))
      (Reduce ((op Reduction) (axes (List I64))))
      (Matmul)
      (Copy)
      (Place ((accessor Accessor)))
      (Gather)
      (ScatterAdd ((rows I64)))
      (Concat ((axis I64)))
      (Sort ((bits I64)))
      (PrefixSum)
      (CustomKind ((custom Custom))))

    (define (kind-text (kind Kind)) (→ String)
      (match kind
        ((Param name) (string-append "param " name))
        ((Constant name _) (string-append "constant " name))
        ((Fill value) (string-append "fill " (f64->string value)))
        ((Elementwise op) (op-text op))
        ((Reduce op axes) (string-append (reduction-text op) " " (string-join (map show axes) ",")))
        ((Matmul) "matmul")
        ((Copy) "copy")
        ((Place accessor) (string-append "place " (accessor-text accessor)))
        ((Gather) "gather")
        ((ScatterAdd rows) (string-append "scatter-add " (show rows)))
        ((Concat axis) (string-append "concat " (show axis)))
        ((Sort bits) (string-append "sort " (show bits)))
        ((PrefixSum) "scan")
        ((CustomKind c) (string-append "custom " (● c name)))))

    ;; A port: what one buffer of a node holds.
    (record Port
      ((name String)
       (shape (List I64))
       (etype Etype)))

    (record Node
      ((key String)
       (kind Kind)
       (args (List View))
       (ports (List Port))))

    (record View
      ((node Node)
       (port String)
       (accessor Accessor)))

    (define default-port (→ String) "out")

    (define (hash-step (hash I64) (word I64)) (→ I64)
      (* (i64-xor hash word) 1099511628211))

    (define (view-key (view View)) (→ String)
      (string-append (● view node key) "." (● view port) "@" (accessor-text (● view accessor))))

    (define (port-text (port Port)) (→ String)
      (string-append (● port name)
                     ":"
                     (etype-wgsl (● port etype))
                     ":"
                     (string-join (map show (● port shape)) ",")))

    ;; Constants also hash the bytes they supply to the CPU and GPU.
    (define (node-key (kind Kind) (args (List View)) (ports (List Port))) (→ String)
      (let* ((parts (Cons (kind-text kind) (append (map port-text ports) (map view-key args))))
             (hash (fold-left (lambda (h c) (hash-step h (char->integer c)))
                              -3750763034362895579
                              (string->list (string-join parts "|")))))
        (show (match kind
                ((Constant _ data)
                 (array-fold (lambda (h byte) (hash-step h (i32->i64 (u8->i32 byte)))) hash data))
                (_ hash)))))

    (define (node (kind Kind) (args (List View)) (ports (List Port))) (→ Node)
      (new Node (key (node-key kind args ports)) (kind kind) (args args) (ports ports)))

    (define (port-of (node Node) (name String)) (→ Port)
      (match (find (lambda (port) (string=? (● port name) name)) (● node ports))
        ((Some port) port)
        ((None) (panic (string-append "tensor: no port " name)))))

    ;; A port's whole buffer, dense.
    (define (node-view (node Node) (name String)) (→ View)
      (new View
        (node node)
        (port name)
        (accessor (dense-accessor (● (port-of node name) shape)))))

    ;; A node with one port, `out`, seen whole.
    (define (single (kind Kind) (args (List View)) (shape (List I64)) (etype Etype)) (→ View)
      (node-view (node kind args (list (new Port (name default-port) (shape shape) (etype etype))))
                 default-port))

    (define (shape-of (view View)) (→ (List I64)) (● view accessor shape))

    (define (etype-of (view View)) (→ Etype) (● (port-of (● view node) (● view port)) etype))

    (define (rank (view View)) (→ I64) (length (shape-of view)))

    (define (element-count (view View)) (→ I64) (product (shape-of view)))

    ;; Whether a view is its port's whole buffer in order.
    (define (identity? (view View)) (→ Bool)
      (let ((port (port-of (● view node) (● view port))) (a (● view accessor)))
        (and (= (● a offset) 0)
             (equal-lists? (● a shape) (● port shape))
             (equal-lists? (● a pitch) (contiguous-pitch (● a shape))))))

    ;; Whether a view reads its port's buffer in order, every element once,
    ;; in any shape.
    (define (whole-buffer? (view View)) (→ Bool)
      (and (= (● view accessor offset) 0)
           (dense? view)
           (= (element-count view) (product (● (port-of (● view node) (● view port)) shape)))))

    ;; Whether a view's elements are adjacent and in order, from its offset.
    (define (dense? (view View)) (→ Bool)
      (equal-lists? (● view accessor pitch) (contiguous-pitch (shape-of view))))

    (define (equal-lists? (a (List I64)) (b (List I64))) (→ Bool)
      (and (= (length a) (length b))
           (every? (lambda (pair) (= (● pair first) (● pair second))) (zip a b))))

    ;; ---- Sources ----

    (define (param (name String) (shape (List I64)) (etype Etype)) (→ View)
      (single (Param name) (Nil) shape etype))

    ;; Keep the row-major bytes that established the constant's key.
    (define (constant (name String) (shape (List I64)) (etype Etype) (data Bytes)) (→ View)
      (single (Constant name (array-copy data)) (Nil) shape etype))

    (define (fill (value F64) (shape (List I64)) (etype Etype)) (→ View)
      (single (Fill value) (Nil) shape etype))

    (define (scalar (value F64)) (→ View) (fill value (Nil) (Float)))

    (define (zeros-like (view View)) (→ View) (fill 0.0 (shape-of view) (etype-of view)))

    (define (ones-like (view View)) (→ View) (fill 1.0 (shape-of view) (etype-of view)))

    ;; ---- Broadcasting ----

    ;; Shapes aligned at their last axes; an axis of 1 stretches to the
    ;; other's size, as NumPy's do.

    (define (broadcast-shape (a (List I64)) (b (List I64))) (→ (List I64))
      (let ((n (max (length a) (length b))))
        (map (lambda (pair)
               (let ((x (● pair first)) (y (● pair second)))
                 (cond ((= x y) x)
                       ((= x 1) y)
                       ((= y 1) x)
                       (else (panic (string-append "tensor: shapes "
                                                   (string-join (map show a) "x")
                                                   " and "
                                                   (string-join (map show b) "x")
                                                   " do not broadcast"))))))
             (zip (padded a n) (padded b n)))))

    (define (padded (shape (List I64)) (n I64)) (→ (List I64))
      (append (map (lambda (_) 1) (iota (- n (length shape)))) shape))

    ;; A view stretched to `shape`: new leading axes and axes of 1 take
    ;; pitch 0, so every index reads the same element.

    (define (broadcast-to (view View) (shape (List I64))) (→ View)
      (let* ((a (● view accessor))
             (n (length shape))
             (from-shape (padded (● a shape) n))
             (from-pitch
              (append (map (lambda (_) 0) (iota (- n (length (● a shape))))) (● a pitch))))
        (View-accessor-set view
                           (new Accessor
                             (offset (● a offset))
                             (shape shape)
                             (pitch (map (lambda (k)
                                           (if (and (= (list-ref from-shape k) 1)
                                                    (not (= (list-ref shape k) 1)))
                                               0
                                               (list-ref from-pitch k)))
                                         (iota n)))))))

    ;; ---- Elementwise ----

    ;; The type a result has: a comparison's and an arithmetic's are their
    ;; operands', a conversion's the one asked for.

    (define (result-etype (op Op) (first View)) (→ Etype)
      (match op
        ((Convert to) to)
        ((Bitcast to) to)
        (_ (etype-of first))))

    (define (unary (op Op) (a View)) (→ View)
      (single (Elementwise op) (list a) (shape-of a) (result-etype op a)))

    ;; Operands broadcast together and of one type.
    (define (binary (op Op) (a View) (b View)) (→ View)
      (unless (same-etype? (etype-of a) (etype-of b))
        (panic (string-append "tensor: "
                              (op-text op)
                              " of "
                              (etype-wgsl (etype-of a))
                              " and "
                              (etype-wgsl (etype-of b)))))
      (let ((shape (broadcast-shape (shape-of a) (shape-of b))))
        (single (Elementwise op)
                (list (broadcast-to a shape) (broadcast-to b shape))
                shape
                (etype-of a))))

    (define (exp (a View)) (→ View) (unary (Exp) a))
    (define (log (a View)) (→ View) (unary (Log) a))
    (define (sin (a View)) (→ View) (unary (Sin) a))
    (define (cos (a View)) (→ View) (unary (Cos) a))
    (define (sign (a View)) (→ View) (unary (Sign) a))
    (define (absolute (a View)) (→ View) (unary (Abs) a))
    (define (square (a View)) (→ View) (binary (Mul) a a))
    (define (sigmoid (a View)) (→ View) (/ (ones-like a) (+ (ones-like a) (exp (negate a)))))
    (define (maximum (a View) (b View)) (→ View) (binary (Max) a b))
    (define (minimum (a View) (b View)) (→ View) (binary (Min) a b))
    (define (power (a View) (b View)) (→ View) (binary (Pow) a b))
    (define (less (a View) (b View)) (→ View) (binary (Less) a b))
    (define (less-equal (a View) (b View)) (→ View) (binary (LessEqual) a b))
    (define (greater (a View) (b View)) (→ View) (binary (Greater) a b))
    (define (greater-equal (a View) (b View)) (→ View) (binary (GreaterEqual) a b))
    (define (equal (a View) (b View)) (→ View) (binary (Equal) a b))
    (define (not-equal (a View) (b View)) (→ View) (binary (NotEqual) a b))
    (define (convert (a View) (to Etype)) (→ View) (unary (Convert to) a))
    (define (bitcast (a View) (to Etype)) (→ View) (unary (Bitcast to) a))

    ;; `a` where `condition` is not 0, `b` where it is.
    (define (where (condition View) (a View) (b View)) (→ View)
      (let ((shape
             (broadcast-shape (shape-of condition) (broadcast-shape (shape-of a) (shape-of b)))))
        (single (Elementwise (Select))
                (list (broadcast-to condition shape) (broadcast-to a shape) (broadcast-to b shape))
                shape
                (etype-of a))))

    (instance (Num View)
      (define + (lambda (a b) (binary (Add) a b)))
      (define - (lambda (a b) (binary (Sub) a b)))
      (define * (lambda (a b) (binary (Mul) a b)))
      (define negate (lambda (a) (unary (Neg) a))))

    (instance (Fractional View)
      (define / (lambda (a b) (binary (Div) a b)))
      (define sqrt (lambda (a) (unary (Sqrt) a)))
      (define floor (lambda (a) (unary (Floor) a)))
      (define ceiling (lambda (a) (negate (unary (Floor) (negate a)))))
      (define round (lambda (a) (unary (Floor) (+ a (fill 0.5 (Nil) (etype-of a))))))
      (define truncate (lambda (a) (* (sign a) (unary (Floor) (absolute a))))))

    ;; ---- Reductions ----

    ;; The reduced axes keep size 1, so the result broadcasts back against
    ;; its operand; `squeeze` drops them.

    (define (reduce (op Reduction) (a View) (axes (List I64))) (→ View)
      (single (Reduce op axes)
              (list a)
              (map-indexed (lambda (k size) (if (member? k axes) 1 size)) (shape-of a))
              (etype-of a)))

    (define (sum (a View) (axes (List I64))) (→ View) (reduce (Sum) a axes))
    (define (amax (a View) (axes (List I64))) (→ View) (reduce (Largest) a axes))
    (define (amin (a View) (axes (List I64))) (→ View) (reduce (Smallest) a axes))

    ;; Every element summed, as a scalar.
    (define (sum-all (a View)) (→ View)
      (reshape (sum a (iota (rank a))) (Nil)))

    (define (mean (a View)) (→ View)
      (/ (sum-all a) (fill (i64->f64 (element-count a)) (Nil) (etype-of a))))

    ;; ---- Matrices ----

    ;; (..., m, k) by (..., k, n), the leading axes equal.
    (define (matmul (a View) (b View)) (→ View)
      (let ((sa (shape-of a)) (sb (shape-of b)))
        (unless (and (>= (length sa) 2)
                     (= (length sa) (length sb))
                     (= (list-ref sa (- (length sa) 1)) (list-ref sb (- (length sb) 2))))
          (panic "tensor: matmul needs (..., m, k) and (..., k, n)"))
        (single (Matmul)
                (list a b)
                (append (take sa (- (length sa) 1)) (list (list-ref sb (- (length sb) 1))))
                (etype-of a))))

    ;; ---- Views ----

    ;; A view's elements written densely, in order.
    (define (copy (a View)) (→ View) (single (Copy) (list a) (shape-of a) (etype-of a)))

    ;; Zeros of `shape`, with `g`'s elements at `accessor`'s addresses,
    ;; whose shape is g's.
    (define (place (g View) (accessor Accessor) (shape (List I64))) (→ View)
      (single (Place accessor) (list g) shape (etype-of g)))

    ;; The same elements in another shape of the same count: a new
    ;; accessor when the view is dense, a copy first when it is not.
    (define (reshape (a View) (shape (List I64))) (→ View)
      (unless (= (product shape) (element-count a))
        (panic "tensor: reshape changes the element count"))
      (let ((dense (if (dense? a) a (copy a))))
        (View-accessor-set dense
                           (new Accessor
                             (offset (● dense accessor offset))
                             (shape shape)
                             (pitch (contiguous-pitch shape))))))

    (define (permute (a View) (order (List I64))) (→ View)
      (let ((x (● a accessor)))
        (View-accessor-set a
                           (new Accessor
                             (offset (● x offset))
                             (shape (map (lambda (k) (list-ref (● x shape) k)) order))
                             (pitch (map (lambda (k) (list-ref (● x pitch) k)) order))))))

    ;; The last two axes swapped.
    (define (transpose (a View)) (→ View)
      (let ((n (rank a)))
        (permute a (append (iota (- n 2)) (list (- n 1) (- n 2))))))

    ;; `count` elements of `axis` from `start`.
    (define (narrow (a View) (axis I64) (start I64) (count I64)) (→ View)
      (let ((x (● a accessor)))
        (unless (<= (+ start count) (list-ref (● x shape) axis))
          (panic "tensor: narrow past the end of its axis"))
        (View-accessor-set a
                           (new Accessor
                             (offset (+ (● x offset) (* start (list-ref (● x pitch) axis))))
                             (shape (map-indexed (lambda (k size) (if (= k axis) count size))
                                                 (● x shape)))
                             (pitch (● x pitch))))))

    (define (squeeze (a View) (axis I64)) (→ View)
      (let ((x (● a accessor)))
        (unless (= (list-ref (● x shape) axis) 1) (panic "tensor: squeeze of an axis not 1"))
        (View-accessor-set a
                           (new Accessor
                             (offset (● x offset))
                             (shape (without (● x shape) axis))
                             (pitch (without (● x pitch) axis))))))

    (define (unsqueeze (a View) (axis I64)) (→ View)
      (let ((x (● a accessor)))
        (View-accessor-set a
                           (new Accessor
                             (offset (● x offset))
                             (shape (inserted (● x shape) axis 1))
                             (pitch (inserted (● x pitch) axis 0))))))

    (define (without (items (List I64)) (k I64)) (→ (List I64))
      (append (take items k) (list-drop items (+ k 1))))

    (define (inserted (items (List I64)) (k I64) (value I64)) (→ (List I64))
      (append (take items k) (Cons value (list-drop items k))))

    ;; ---- Rows ----

    ;; Row `indices[i]` of `source` as row i: (n, ...) at m u32 indices
    ;; gives (m, ...).
    (define (gather (source View) (indices View)) (→ View)
      (single (Gather)
              (list source indices)
              (Cons (element-count indices) (list-tail (shape-of source) 1))
              (etype-of source)))

    ;; Each row i of `source` added to row `indices[i]` of `rows` zero rows.
    (define (scatter-add (source View) (indices View) (rows I64)) (→ View)
      (single (ScatterAdd rows)
              (list source indices)
              (Cons rows (list-tail (shape-of source) 1))
              (etype-of source)))

    ;; ---- Joining ----

    ;; The views joined along `axis`, of one type and equal on every other
    ;; axis. A node joins at most six, so its kernel binds at most the
    ;; eight storage buffers every device allows; more are joined in a
    ;; tree.
    (define (concat (views (List View)) (axis I64)) (→ View)
      (if (<= (length views) 6)
          (joined views axis)
          (concat (map (lambda (k)
                         (joined (take (list-drop views (* 6 k)) (min 6 (- (length views) (* 6 k))))
                                 axis))
                       (iota (quotient (+ (length views) 5) 6)))
                  axis)))

    (define (joined (views (List View)) (axis I64)) (→ View)
      (let* ((first-view (list-ref views 0))
             (shape (shape-of first-view)))
        (unless (every? (lambda (v)
                          (and (same-etype? (etype-of v) (etype-of first-view))
                               (equal-lists? (without (shape-of v) axis) (without shape axis))))
                        views)
          (panic "tensor: concat of views that differ off its axis"))
        (single (Concat axis)
                views
                (map-indexed (lambda (k size)
                               (if (= k axis)
                                   (fold-left +
                                              0
                                              (map (lambda (v) (list-ref (shape-of v) axis)) views))
                                   size))
                             shape)
                (etype-of first-view))))

    ;; Views of one shape along a new axis.
    (define (stack (views (List View)) (axis I64)) (→ View)
      (concat (map (lambda (v) (unsqueeze v axis)) views) axis))

    ;; ---- Sorting and scanning ----

    ;; u32 keys and their u32 values sorted by the keys' low `bits` bits,
    ;; 8, 16, 24 or 32, equal keys keeping their order.
    (define (sort-pairs (keys View) (values View) (bits I64)) (→ (Pair View View))
      (let ((n (node (Sort bits)
                     (list keys values)
                     (list (new Port (name "keys") (shape (shape-of keys)) (etype (Unsigned)))
                           (new Port
                             (name "values")
                             (shape (shape-of values))
                             (etype (Unsigned)))))))
        (new Pair (first (node-view n "keys")) (second (node-view n "values")))))

    ;; Each u32 number replaced by the sum of those before it.
    (define (exclusive-scan (a View)) (→ View)
      (single (PrefixSum) (list a) (shape-of a) (Unsigned)))

    ;; ---- Custom nodes ----

    ;; A custom node's ports, each seen whole, in order; an argument that is
    ;; not a whole port's buffer in order is copied into one first.
    (define (custom (c Custom) (args (List View)) (ports (List Port))) (→ (List View))
      (let ((n
             (node (CustomKind c) (map (lambda (a) (if (whole-buffer? a) a (copy a))) args) ports)))
        (map (lambda (port) (node-view n (● port name))) ports)))

    ;; ---- Order ----

    ;; Every node the roots depend on, each after its arguments, once.

    (define (toposort (roots (List View))) (→ (List Node))
      (reverse (● (fold-left visit (new Pair (first (Nil)) (second (empty-table))) roots) first)))

    (define (visit (seen (Pair (List Node) (Table Bool))) (view View))
      (→ (Pair (List Node) (Table Bool)))
      (let ((n (● view node)))
        (if (table-contains? (● seen second) (● n key))
            seen
            (let ((after (fold-left visit
                                    (new Pair
                                      (first (● seen first))
                                      (second (table-set (● seen second) (● n key) #t)))
                                    (● n args))))
              (new Pair (first (Cons n (● after first))) (second (● after second)))))))

    ))
