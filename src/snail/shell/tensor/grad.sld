;; Reverse-mode gradients as more graph: `grad` walks the nodes a scalar
;; depends on from the last to the first, and builds, for each port, the
;; gradient of the scalar with respect to that port's buffer, as views of
;; new nodes. Nothing runs: the gradient is lowered with everything else.
;;
;;   (grad loss (list w b))   ; dloss/dw and dloss/db, shaped as w and b
;;
;; Each kind of node answers the gradient of each argument given the
;; gradient of each port, none for a port nothing the loss depends on
;; reads (`adjoints` below): a map back through each of its bodies, a body
;; of several operations as one expression, so that its gradient is one
;; map for each argument; a reduction over its span and then back through
;; its body; a custom node answers its own.
;; A view's gradient reaches its port through the view's accessor: summed
;; over the axes it broadcasts, then a view of the port when the view
;; reads all of it in some order of its axes, and a part, with the
;; addresses it reads, otherwise. Once every reader has handed back its
;; share, parts that split one axis of the port between them are joined
;; along it, zeros where none reads, as a concat; any other part is placed
;; among zeros and added.
(define-library (snail shell tensor grad)
  (export
   grad)
  (import
   (snail core base)
   (snail core table)
   (snail shell tensor))
  (begin

    ;; ---- Walking back ----

    ;; The gradient of `loss`, a scalar, with respect to each view.

    (define (grad (loss View) (wrt (List View))) (→ (List View))
      (unless (null? (shape-of loss)) (panic "grad: the loss must be a scalar"))
      (let ((shares (fold-left backward
                               (accumulate (empty-table) loss (ones-like loss))
                               (reverse (toposort (list loss))))))
        (map (lambda (w) (gradient-of shares w)) wrt)))

    (define (port-key (n Node) (port String)) (→ String) (string-append (● n key) "." port))

    ;; Each argument's share of a node's port gradients, handed back. Every
    ;; node reading a port comes later, so its port's shares are all in.

    (define (backward (shares (Table Shares)) (n Node)) (→ (Table Shares))
      (let ((outs (map (lambda (port) (port-gradient shares n port)) (● n ports))))
        (if (every? none? outs)
            shares
            (fold-left (lambda (shares pair)
                         (match (● pair second)
                           ((Some g) (accumulate shares (● pair first) g))
                           ((None) shares)))
                       shares
                       (zip (● n args) (adjoints n outs))))))

    (define (none? (value (Option View))) (→ Bool)
      (match value
        ((Some _) #f)
        ((None) #t)))

    ;; ---- Shares ----

    ;; What a port's readers have handed back: the sum of the shares of
    ;; those that read all of it, and the shares of those that read part of
    ;; it, each with the addresses it read. The port's gradient is made
    ;; from them once all are in, so that parts splitting the port between
    ;; them are joined, where each placed among zeros and the places added
    ;; would write and read the whole port once a part.
    (record Shares
      ((whole (Option View))
       (parts (List Part))))

    (record Part
      ((g View)
       (seen Accessor)))

    ;; The gradient `g` of a view, as its port sees it, among the port's
    ;; shares. A view reading no elements hands back nothing: the loss
    ;; depends on none of the port through it. So every share below reads
    ;; at least one element, and every port it reads has no empty axis.
    (define (accumulate (shares (Table Shares)) (view View) (g View)) (→ (Table Shares))
      (if (= (product (● view accessor shape)) 0)
          shares
          (let ((key (port-key (● view node) (● view port))))
            (table-set shares
                       key
                       (with-share (match (table-ref shares key)
                                     ((Some s) s)
                                     ((None) (new Shares (whole (None)) (parts (Nil)))))
                                   view
                                   g)))))

    ;; A view's gradient as its port sees it: summed over the axes the view
    ;; broadcasts, then the port's shape. A view that reads its whole port,
    ;; in its port's order or another order of its axes, passes the
    ;; gradient back as a view, its axes put back in the port's order; any
    ;; other hands back a part.

    (define (with-share (s Shares) (view View) (g View)) (→ Shares)
      (let* ((a (● view accessor))
             (spread (filter (lambda (k)
                               (and (= (list-ref (● a pitch) k) 0) (> (list-ref (● a shape) k) 1)))
                             (iota (length (● a shape)))))
             (summed (if (null? spread) g (sum g spread)))
             (seen
              (new Accessor (offset (● a offset)) (shape (shape-of summed)) (pitch (● a pitch))))
             (shape (● (port-of (● view node) (● view port)) shape)))
        (match (port-order seen shape)
          ((Some order)
           (let ((share (shaped (permute summed order) shape)))
             (Shares-whole-set s
                               (Some (match (● s whole)
                                       ((Some total) (+ total share))
                                       ((None) share))))))
          ((None) (Shares-parts-set s (Cons (new Part (g summed) (seen seen)) (● s parts)))))))

    ;; A port's gradient, when any reader handed back a share.
    (define (port-gradient (shares (Table Shares)) (n Node) (port Port)) (→ (Option View))
      (match (table-ref shares (port-key n (● port name)))
        ((Some s) (Some (gathered s (● port shape))))
        ((None) (None))))

    (define (gathered (s Shares) (shape (List I64))) (→ View)
      (match (● s parts)
        ((Nil) (match (● s whole)
                 ((Some whole) whole)
                 ((None) (panic "grad: a port with no shares"))))
        (_ (let ((joined (parts-joined (by-addresses (● s parts)) shape)))
             (match (● s whole)
               ((Some whole) (+ whole joined))
               ((None) joined))))))

    ;; Parts at the same addresses as one, their gradients added, in the
    ;; order each first appears: in the first's shape, since a view may
    ;; hold axes of 1 another lacks. A part finds its group by its
    ;; addresses without those axes, so a port read in many parts costs
    ;; one lookup a part.
    (define (by-addresses (parts (List Part))) (→ (List Part))
      (let ((groups (fold-left grouped (new Groups (order (Nil)) (found (empty-table))) parts)))
        (map (lambda (key) (group-of groups key)) (reverse (● groups order)))))

    ;; The groups so far: each one's key, the newest first, and its part.
    (record Groups
      ((order (List String))
       (found (Table Part))))

    (define (grouped (groups Groups) (part Part)) (→ Groups)
      (let ((key (addresses-key (without-ones (● part seen)))))
        (match (table-ref (● groups found) key)
          ((Some k)
           (Groups-found-set
            groups
            (table-set (● groups found)
                       key
                       (Part-g-set k (+ (● k g) (shaped (● part g) (shape-of (● k g))))))))
          ((None)
           (new Groups
             (order (Cons key (● groups order)))
             (found (table-set (● groups found) key part)))))))

    (define (group-of (groups Groups) (key String)) (→ Part)
      (match (table-ref (● groups found) key)
        ((Some part) part)
        ((None) (panic "grad: a group with no part"))))

    (define (addresses-key (a Accessor)) (→ String)
      (string-append (show (● a offset))
                     " "
                     (string-join (map show (● a shape)) ",")
                     " "
                     (string-join (map show (● a pitch)) ",")))

    (define (same-addresses? (a Accessor) (b Accessor)) (→ Bool)
      (and (= (● a offset) (● b offset))
           (equal-lists? (● a shape) (● b shape))
           (equal-lists? (● a pitch) (● b pitch))))

    ;; Parts that split one axis of the port between them, joined along it
    ;; in order with zeros where none reads: a concat, which a kernel reading
    ;; the gradient takes in when the axis is the last and narrow. Any
    ;; others are each placed among zeros and added.
    (define (parts-joined (parts (List Part)) (shape (List I64))) (→ View)
      (match (find (lambda (axis) (split-along? parts shape axis)) (iota (length shape)))
        ((Some axis) (joined-runs (runs-along parts shape axis) axis shape))
        ((None)
         (let ((placed (map (lambda (p) (place (● p g) (● p seen) shape)) parts)))
           (fold-left (lambda (total v) (+ total v)) (list-ref placed 0) (list-tail placed 1))))))

    ;; A part's run of a port along one axis: where it starts on the axis,
    ;; how far it goes, and its gradient.
    (record Run
      ((start I64)
       (size I64)
       (g View)))

    (define (split-along? (parts (List Part)) (shape (List I64)) (axis I64)) (→ Bool)
      (and (every? (lambda (p) (some-span? (span-of (● p seen) shape axis))) parts)
           (apart? (runs-along parts shape axis))))

    (define (some-span? (span (Option (Pair I64 I64)))) (→ Bool)
      (match span
        ((Some _) #t)
        ((None) #f)))

    ;; Where the run along `axis` that an accessor reads of a port of
    ;; `shape` starts on the axis and how far it goes, when it reads one:
    ;; all of every other axis, in the port's order. Axes of 1 address
    ;; nothing, so they are left out of the comparison: a view may hold
    ;; more of them than the port, unsqueezed or summed.
    (define (span-of (a Accessor) (shape (List I64)) (axis I64)) (→ (Option (Pair I64 I64)))
      (let* ((pitch (contiguous-pitch shape))
             (start (quotient (● a offset) (list-ref pitch axis)))
             (size
              (quotient (product (● a shape)) (quotient (product shape) (list-ref shape axis))))
             (run (new Accessor
                    (offset (* start (list-ref pitch axis)))
                    (shape (run-shape shape axis size))
                    (pitch pitch))))
        (if (and (> size 0)
                 (<= (+ start size) (list-ref shape axis))
                 (same-addresses? (without-ones run) (without-ones a)))
            (Some (new Pair (first start) (second size)))
            (None))))

    (define (run-shape (shape (List I64)) (axis I64) (size I64)) (→ (List I64))
      (map-indexed (lambda (k n) (if (= k axis) size n)) shape))

    ;; An accessor without its axes of 1.
    (define (without-ones (a Accessor)) (→ Accessor)
      (let ((kept (filter (lambda (k) (> (list-ref (● a shape) k) 1)) (iota (length (● a shape))))))
        (new Accessor
          (offset (● a offset))
          (shape (map (lambda (k) (list-ref (● a shape) k)) kept))
          (pitch (map (lambda (k) (list-ref (● a pitch) k)) kept)))))

    ;; Each part's run along `axis`, first to last, its gradient in the
    ;; shape of the port's run.
    (define (runs-along (parts (List Part)) (shape (List I64)) (axis I64)) (→ (List Run))
      (list-sort (lambda (x y) (< (● x start) (● y start)))
                 (map (lambda (p)
                        (match (span-of (● p seen) shape axis)
                          ((Some span)
                           (new Run
                             (start (● span first))
                             (size (● span second))
                             (g (shaped (● p g) (run-shape shape axis (● span second))))))
                          ((None) (panic "grad: a part with no run"))))
                      parts)))

    ;; Whether each run ends before the next starts.
    (define (apart? (runs (List Run))) (→ Bool)
      (match runs
        ((Cons x (Cons y rest))
         (and (<= (+ (● x start) (● x size)) (● y start)) (apart? (Cons y rest))))
        (_ #t)))

    ;; The runs along `axis`, zeros before, between and after them. The
    ;; pieces gather last first, and are put in order once.
    (define (joined-runs (runs (List Run)) (axis I64) (shape (List I64))) (→ View)
      (let* ((etype (etype-of (● (list-ref runs 0) g)))
             (gap (lambda (size) (fill 0.0 (run-shape shape axis size) etype)))
             (end (fold-left (lambda (state run)
                               (new Pair
                                 (first (Cons (● run g)
                                              (if (> (● run start) (● state second))
                                                  (Cons (gap (- (● run start) (● state second)))
                                                        (● state first))
                                                  (● state first))))
                                 (second (+ (● run start) (● run size)))))
                             (new Pair (first (Nil)) (second 0))
                             runs))
             (pieces (if (< (● end second) (list-ref shape axis))
                         (Cons (gap (- (list-ref shape axis) (● end second))) (● end first))
                         (● end first))))
        (concat (reverse pieces) axis)))

    ;; The order of an accessor's axes, largest pitch first, when in that
    ;; order it reads every element of a port of `shape` in order.
    (define (port-order (a Accessor) (shape (List I64))) (→ (Option (List I64)))
      (let* ((order (list-sort (lambda (j k) (> (list-ref (● a pitch) j) (list-ref (● a pitch) k)))
                               (iota (length (● a shape)))))
             (pick (lambda (items) (map (lambda (k) (list-ref items k)) order))))
        (if (whole? (new Accessor
                      (offset (● a offset))
                      (shape (pick (● a shape)))
                      (pitch (pick (● a pitch))))
                    shape)
            (Some order)
            (None))))

    ;; A view in `shape`, reshaped only when its own shape is another.
    (define (shaped (v View) (shape (List I64))) (→ View)
      (if (and (= (length (shape-of v)) (length shape))
               (every? (lambda (pair) (= (● pair first) (● pair second))) (zip (shape-of v) shape)))
          v
          (reshape v shape)))

    ;; Whether an accessor reads every element of a port of `shape` in
    ;; order, apart from axes of 1.
    (define (whole? (a Accessor) (shape (List I64))) (→ Bool)
      (let* ((kept (filter (lambda (k) (not (= (list-ref (● a shape) k) 1)))
                           (iota (length (● a shape)))))
             (sizes (map (lambda (k) (list-ref (● a shape) k)) kept))
             (pitches (map (lambda (k) (list-ref (● a pitch) k)) kept)))
        (and (= (● a offset) 0)
             (= (product sizes) (product shape))
             (every? (lambda (pair) (= (● pair first) (● pair second)))
                     (zip pitches (contiguous-pitch sizes))))))

    ;; A port's gradient seen through a view of it: the view's own
    ;; accessor over the gradient made dense; zeros when the loss does not
    ;; depend on it.
    (define (gradient-of (shares (Table Shares)) (w View)) (→ View)
      (match (port-gradient shares (● w node) (port-of (● w node) (● w port)))
        ((Some g)
         (let ((dense (if (identity? g) g (copy g))))
           (if (identity? w) dense (View-accessor-set dense (● w accessor)))))
        ((None) (zeros-like w))))

    ;; ---- Adjoints ----

    ;; The gradient of each argument of a node, given the gradient of each
    ;; port, or None where an argument has none.

    (define (adjoints (n Node) (outs (List (Option View)))) (→ (List (Option View)))
      (match (● n kind)
        ((CustomKind c) ((● c adjoint) (● n args) outs))
        ((Sort _) (map (lambda (_) (None)) (● n args)))
        ((Map bodies) (map-node-adjoints n bodies outs))
        (_ (single-port-adjoints n (first-gradient outs)))))

    ;; A node of one port, `out`, whose gradient is g.
    (define (single-port-adjoints (n Node) (g View)) (→ (List (Option View)))
      (let ((args (● n args)) (y (node-view n default-port)))
        (match (● n kind)
          ((Reduce op span body) (reduce-adjoints op span body args y g))
          ((Place accessor)
           (list (Some (View-accessor-set (if (identity? g) g (copy g)) accessor))))
          ((Gather)
           (list (Some (scatter-add g (list-ref args 1) (list-ref (shape-of (list-ref args 0)) 0)))
                 (None)))
          ((ScatterAdd _) (list (Some (gather g (list-ref args 1))) (None)))
          ((Concat axis) (concat-adjoints args axis g))
          (_ (map (lambda (_) (None)) args)))))

    ;; Each argument's span of the joined axis.
    (define (concat-adjoints (args (List View)) (axis I64) (g View)) (→ (List (Option View)))
      (reverse (● (fold-left (lambda (state a)
                               (let ((size (list-ref (shape-of a) axis)))
                                 (new Pair
                                   (first (Cons (Some (narrow g axis (● state second) size))
                                                (● state first)))
                                   (second (+ (● state second) size)))))
                             (new Pair (first (Nil)) (second 0))
                             args)
                  first)))

    (define (first-gradient (outs (List (Option View)))) (→ View)
      (match (find (lambda (out) (not (none? out))) outs)
        ((Some (Some g)) g)
        (_ (panic "grad: a node with no port gradient"))))

    ;; A reduction's gradient reaches each element of its span: all of g
    ;; for a sum, and for the largest or smallest, g where the element is
    ;; the one chosen. It goes on back through the body, as a map's does.
    (define (reduce-adjoints (op Reduction)
                             (span (List I64))
                             (body Expr)
                             (args (List View))
                             (y View)
                             (g View))
      (→ (List (Option View)))
      (let* ((shape (append (shape-of y) span))
             (value (expr-view body args shape))
             (share (match op
                      ((Sum) (spread g shape))
                      (_ (* (spread g shape) (equal value (spread y shape)))))))
        (map-adjoints body args value share)))

    ;; `v` at each element of the trailing axes of `shape` it lacks.
    (define (spread (v View) (shape (List I64))) (→ View)
      (broadcast-to (fold-left (lambda (v _) (unsqueeze v (rank v))) v (list-drop shape (rank v)))
                    shape))

    ;; ---- Maps ----

    ;; Each argument's gradient from every port of a map: each port's body
    ;; carries the port's gradient back, and the shares add up. A port with
    ;; no gradient, which nothing the loss depends on reads, adds nothing,
    ;; as a gradient of zeros would.
    (define (map-node-adjoints (n Node) (bodies (List Expr)) (outs (List (Option View))))
      (→ (List (Option View)))
      (fold-left (lambda (sums p)
                   (match (list-ref outs p)
                     ((Some g)
                      (map (lambda (pair) (added (● pair first) (● pair second)))
                           (zip sums (body-adjoints n (list-ref bodies p) (map-port-name p) g))))
                     ((None) sums)))
                 (map (lambda (_) (None)) (● n args))
                 (iota (length bodies))))

    (define (added (a (Option View)) (b (Option View))) (→ (Option View))
      (match a
        ((Some x)
         (match b
           ((Some y) (Some (+ x y)))
           ((None) a)))
        ((None) b)))

    ;; One port's share for each argument: a body of one operation back
    ;; through that operation's rule, over the arguments' views; a body of
    ;; several operations as one expression (`expression-adjoints`).
    (define (body-adjoints (n Node) (body Expr) (port String) (g View)) (→ (List (Option View)))
      (let ((y (node-view n port)))
        (if (one-operation? body)
            (map-adjoints body (● n args) y g)
            (expression-adjoints body
                                 (● n args)
                                 (take (shape-of y) (- (rank y) (length (expr-tile body))))
                                 g))))

    ;; Whether a body is one operation of loads and constants, such as a
    ;; fill's tile of literals.
    (define (one-operation? (body Expr)) (→ Bool)
      (match body
        ((Apply _ operands _ _) (every? (lambda (o) (not (computed? o))) operands))
        (_ #t)))

    ;; Whether an expression is an operation of something loaded.
    (define (computed? (e Expr)) (→ Bool)
      (match e
        ((Apply _ operands _ _) (any? loads? operands))
        (_ #f)))

    (define (loads? (e Expr)) (→ Bool)
      (match e
        ((Load _ _ _) #t)
        ((Literal _ _) #f)
        ((Apply _ operands _ _) (any? loads? operands))))

    ;; The gradient of each argument of a map whose port's gradient is g,
    ;; back through its body from the top, whose value is the port's, y:
    ;; each operation hands each operand its share of the operation's
    ;; gradient, and each load adds its share to its argument's. An
    ;; operand that is itself an operation is built again as a node of its
    ;; own, for the rules that need its value. Each expression's value,
    ;; and its gradient, is a view of the map's leading axes followed by
    ;; the expression's tile.

    (define (map-adjoints (body Expr) (args (List View)) (y View) (g View)) (→ (List (Option View)))
      (let* ((lead (take (shape-of y) (- (rank y) (length (expr-tile body)))))
             (shares (expr-adjoints body y g args lead (empty-table))))
        (map (lambda (k) (table-ref shares (show k))) (iota (length args)))))

    (define (expr-adjoints (e Expr)
                           (value View)
                           (g View)
                           (args (List View))
                           (lead (List I64))
                           (shares (Table View)))
      (→ (Table View))
      (match e
        ((Load k _ _)
         (table-set shares
                    (show k)
                    (match (table-ref shares (show k))
                      ((Some share) (+ share g))
                      ((None) g))))
        ((Literal _ _) shares)
        ((Apply op operands _ _)
         (let ((values (map (lambda (o) (expr-view o args lead)) operands)))
           (fold-left (lambda (shares pair)
                        (match (● pair second)
                          ((Some share)
                           (expr-adjoints (list-ref operands (● pair first))
                                          (list-ref values (● pair first))
                                          share
                                          args
                                          lead
                                          shares))
                          ((None) shares)))
                      shares
                      (zip (iota (length operands))
                           (operation-adjoints op operands values value g)))))))

    ;; What an expression of a map's body computes, as a view of `lead`
    ;; followed by its tile: an argument itself for a load.
    (define (expr-view (e Expr) (args (List View)) (lead (List I64))) (→ View)
      (match e
        ((Load k _ _) (list-ref args k))
        ((Literal value etype) (fill value (Nil) etype))
        ((Apply op operands etype tile)
         (mapped (Apply op
                        (map-indexed (lambda (k o) (Load k (expr-etype o) (expr-tile o))) operands)
                        etype
                        tile)
                 (map (lambda (o) (expr-view o args lead)) operands)
                 lead))))

    ;; ---- Tiles ----

    ;; The share of each operand of a tile's own operation, then of the
    ;; elementwise ones. Fusing makes picks, after gradients are built.
    (define (operation-adjoints (op Op)
                                (operands (List Expr))
                                (values (List View))
                                (y View)
                                (g View))
      (→ (List (Option View)))
      (match op
        ((Pack) (pack-adjoints operands g))
        ((Pick _) (panic "grad: a pick in a body not yet fused"))
        ((Product) (product-adjoints (list-ref values 0) (list-ref values 1) g))
        ((Fold combining)
         (let ((a (list-ref values 0)))
           (list (Some (match combining
                         ((Sum) (spread g (shape-of a)))
                         (_ (* (spread g (shape-of a)) (equal a (spread y (shape-of a))))))))))
        (_ (op-adjoints op values y g))))

    ;; Each operand's elements of g, in order along its tile's one axis. A
    ;; literal takes none, so a fill's tile of literals, which may have
    ;; more axes, is never narrowed.
    (define (pack-adjoints (operands (List Expr)) (g View)) (→ (List (Option View)))
      (let ((axis (- (rank g) 1)))
        (reverse (● (fold-left (lambda (state o)
                                 (let ((size (product (expr-tile o))) (at (● state second)))
                                   (new Pair
                                     (first (Cons (match o
                                                    ((Literal _ _) (None))
                                                    (_ (Some (shaped (narrow g axis at size)
                                                                     (append
                                                                      (take (shape-of g) axis)
                                                                      (expr-tile o))))))
                                                  (● state first)))
                                     (second (+ at size)))))
                               (new Pair (first (Nil)) (second 0))
                               operands)
                    first))))

    ;; d/da = g b^T and d/db = a^T g, for a of (m, k) and b of (k, c); for
    ;; a row of k, d/db is the row's outer product with g. Each is a
    ;; product of tiles again.
    (define (product-adjoints (a View) (b View) (g View)) (→ (List (Option View)))
      (if (= (rank a) (rank b))
          (list (Some (matmul g (transpose b))) (Some (matmul (transpose a) g)))
          (list (Some (squeeze (matmul (unsqueeze g (- (rank g) 1)) (transpose b)) (- (rank g) 1)))
                (Some (matmul (unsqueeze a (rank a)) (unsqueeze g (- (rank g) 1)))))))

    ;; ---- Operations ----

    ;; d/da and d/db of y = op(a, b), each times g; operations that are
    ;; flat or not continuous pass no gradient.

    (define (op-adjoints (op Op) (args (List View)) (y View) (g View))
      (→ (List (Option View)))
      (let ((a (list-ref args 0))
            (b (if (> (length args) 1) (list-ref args 1) y))
            (two (scalar 2.0)))
        (match op
          ((Neg) (list (Some (negate g))))
          ((Exp) (list (Some (* g y))))
          ((Log) (list (Some (/ g a))))
          ((Sqrt) (list (Some (/ g (* two y)))))
          ((Sin) (list (Some (* g (cos a)))))
          ((Cos) (list (Some (negate (* g (sin a))))))
          ((Abs) (list (Some (* g (sign a)))))
          ((Add) (list (Some g) (Some g)))
          ((Sub) (list (Some g) (Some (negate g))))
          ((Mul) (list (Some (* g b)) (Some (* g a))))
          ((Div) (list (Some (/ g b)) (Some (negate (/ (* g y) b)))))
          ((Pow) (list (Some (/ (* g (* b y)) a)) (Some (* g (* (log a) y)))))
          ((Max) (list (Some (* g (greater-equal a b))) (Some (* g (less a b)))))
          ((Min) (list (Some (* g (less-equal a b))) (Some (* g (greater a b)))))
          ((Select)
           (let ((zero (zeros-like g)))
             (list (None) (Some (where a g zero)) (Some (where a zero g)))))
          ((Convert _)
           (list (match (etype-of a)
                   ((Float) (Some g))
                   (_ (None)))))
          (_ (map (lambda (_) (None)) args)))))

    ;; ---- Bodies of several operations ----

    ;; A body of several operations is differentiated as one expression,
    ;; so that its gradient is one map for each argument, where a body of
    ;; one operation gets a node for each share. The port's gradient,
    ;; loaded after the arguments, is carried back through each operation
    ;; to the loads, and each argument's gradient is the sum of its loads'
    ;; shares. A rule that needs an operand's value uses the operand's own
    ;; expression, which the map computes again; lowering computes each
    ;; distinct value once, however many shares use it. A load picked
    ;; apart, as a row's elements, takes each element's share at its place.
    (define (expression-adjoints (body Expr) (args (List View)) (lead (List I64)) (g View))
      (→ (List (Option View)))
      (let ((shares (carried body
                             (Load (length args) (expr-etype body) (expr-tile body))
                             (empty-table)))
            (tiles (load-tiles body (empty-table)))
            (operands (append args (list g))))
        (map (lambda (k)
               (match (load-share shares k (tile-of tiles k) (etype-of (list-ref args k)))
                 ((Some e) (Some (body-map e operands lead)))
                 ((None) (None))))
             (iota (length args)))))

    ;; `shares` with those of the loads in `e`, whose gradient is `g`.
    (define (carried (e Expr) (g Expr) (shares (Table Expr))) (→ (Table Expr))
      (match e
        ((Load k _ _) (share-added shares (show k) g))
        ((Literal _ _) shares)
        ((Apply (Pick indices) (Cons (Load k _ _) (Nil)) _ _)
         (fold-left (lambda (shares pair)
                      (share-added shares
                                   (element-key k (● pair second))
                                   (element-of g (● pair first))))
                    shares
                    (zip (iota (length indices)) indices)))
        ((Apply op operands _ _)
         (fold-left (lambda (shares pair)
                      (match (● pair second)
                        ((Some share) (carried (list-ref operands (● pair first)) share shares))
                        ((None) shares)))
                    shares
                    (zip (iota (length operands)) (expression-shares op operands e g))))))

    (define (share-added (shares (Table Expr)) (key String) (g Expr)) (→ (Table Expr))
      (table-set shares
                 key
                 (match (table-ref shares key)
                   ((Some share) (operation (Add) (list share g)))
                   ((None) g))))

    (define (element-key (k I64) (place I64)) (→ String)
      (string-append (show k) "." (show place)))

    ;; Element i of a tile, or a value itself.
    (define (element-of (e Expr) (i I64)) (→ Expr)
      (if (null? (expr-tile e))
          e
          (Apply (Pick (list i)) (list e) (expr-etype e) (Nil))))

    ;; Argument k's gradient: its whole loads' shares, and its elements'
    ;; at their places in its tile, zero where none was picked.
    (define (load-share (shares (Table Expr)) (k I64) (tile (List I64)) (etype Etype))
      (→ (Option Expr))
      (let ((picked (map (lambda (p) (table-ref shares (element-key k p))) (iota (product tile))))
            (whole (table-ref shares (show k))))
        (if (every? none-share? picked)
            whole
            (let ((elements (Apply (Pack)
                                   (map (lambda (share)
                                          (match share
                                            ((Some e) e)
                                            ((None) (Literal 0.0 etype))))
                                        picked)
                                   etype
                                   tile)))
              (match whole
                ((Some e) (Some (operation (Add) (list e elements))))
                ((None) (Some elements)))))))

    (define (none-share? (share (Option Expr))) (→ Bool)
      (match share
        ((Some _) #f)
        ((None) #t)))

    ;; The tile each argument is loaded at, by its number.
    (define (load-tiles (e Expr) (tiles (Table (List I64)))) (→ (Table (List I64)))
      (match e
        ((Load k _ tile) (table-set tiles (show k) tile))
        ((Literal _ _) tiles)
        ((Apply _ operands _ _)
         (fold-left (lambda (tiles o) (load-tiles o tiles)) tiles operands))))

    (define (tile-of (tiles (Table (List I64))) (k I64)) (→ (List I64))
      (match (table-ref tiles (show k))
        ((Some tile) tile)
        ((None) (Nil))))

    ;; A map of `e` over the operands it loads, in their order.
    (define (body-map (e Expr) (operands (List View)) (lead (List I64))) (→ View)
      (let* ((loaded (loads-of e (Nil)))
             (kept (filter (lambda (k) (member? k loaded)) (iota (length operands)))))
        (mapped (map-loads e (lambda (k etype tile) (Load (position-in kept k) etype tile)))
                (map (lambda (k) (list-ref operands k)) kept)
                lead)))

    (define (loads-of (e Expr) (found (List I64))) (→ (List I64))
      (match e
        ((Load k _ _) (Cons k found))
        ((Literal _ _) found)
        ((Apply _ operands _ _) (fold-left (lambda (found o) (loads-of o found)) found operands))))

    (define (position-in (items (List I64)) (k I64)) (→ I64)
      (match (list-index (lambda (j) (= j k)) items)
        ((Some at) at)
        ((None) (panic "grad: a load of no operand"))))

    ;; An operation on expressions, a value broadcasting against a tile:
    ;; its type its operands', a choice's that of what it chooses, and its
    ;; tile the widest of theirs.
    (define (operation (op Op) (operands (List Expr))) (→ Expr)
      (Apply op
             operands
             (expr-etype (list-ref operands
                                   (match op
                                     ((Select) 1)
                                     (_ 0))))
             (fold-left (lambda (tile o)
                          (if (> (length (expr-tile o)) (length tile)) (expr-tile o) tile))
                        (Nil)
                        operands)))

    ;; The share of each operand of an operation, given the operation's
    ;; value `y` and gradient `g`, by the rules a body of one operation's
    ;; shares follow (`op-adjoints`); a share wider than its operand, a
    ;; value broadcast against a tile, is summed over the tile. A tile's
    ;; own operations hand each operand its elements of g, put back at the
    ;; places a pick took, or g at each element a fold combined.
    (define (expression-shares (op Op) (operands (List Expr)) (y Expr) (g Expr))
      (→ (List (Option Expr)))
      (let* ((a (list-ref operands 0))
             (b (if (> (length operands) 1) (list-ref operands 1) y))
             (times (lambda (u v) (operation (Mul) (list u v))))
             (over (lambda (u v) (operation (Div) (list u v))))
             (minus (lambda (u) (operation (Neg) (list u))))
             (of (lambda (o u) (operation o (list u))))
             (both (lambda (o u v) (operation o (list u v))))
             (fit (lambda (shares) (fitted-shares operands shares))))
        (match op
          ((Neg) (fit (list (minus g))))
          ((Exp) (fit (list (times g y))))
          ((Log) (fit (list (over g a))))
          ((Sqrt) (fit (list (over g (times (Literal 2.0 (expr-etype y)) y)))))
          ((Sin) (fit (list (times g (of (Cos) a)))))
          ((Cos) (fit (list (minus (times g (of (Sin) a))))))
          ((Abs) (fit (list (times g (of (Sign) a)))))
          ((Add) (fit (list g g)))
          ((Sub) (fit (list g (minus g))))
          ((Mul) (fit (list (times g b) (times g a))))
          ((Div) (fit (list (over g b) (minus (over (times g y) b)))))
          ((Pow) (fit (list (over (times g (times b y)) a) (times g (times (of (Log) a) y)))))
          ((Max) (fit (list (times g (both (GreaterEqual) a b)) (times g (both (Less) a b)))))
          ((Min) (fit (list (times g (both (LessEqual) a b)) (times g (both (Greater) a b)))))
          ((Select)
           (let ((zero (Literal 0.0 (expr-etype g))) (condition a))
             (list (None)
                   (Some
                    (fitted (operation (Select) (list condition g zero)) (list-ref operands 1)))
                   (Some
                    (fitted (operation (Select) (list condition zero g)) (list-ref operands 2))))))
          ((Convert _)
           (list (match (expr-etype a)
                   ((Float) (Some g))
                   (_ (None)))))
          ((Pack) (pack-shares operands g))
          ((Pick indices) (list (Some (scattered g indices a))))
          ((Fold combining) (list (Some (folded-share combining a y g))))
          ((Product) (panic "grad: a matrix product in a body of several operations"))
          (_ (map (lambda (_) (None)) operands)))))

    (define (fitted-shares (operands (List Expr)) (shares (List Expr))) (→ (List (Option Expr)))
      (map (lambda (pair) (Some (fitted (● pair second) (● pair first)))) (zip operands shares)))

    ;; A share as wide as its operand: a value's share of a tile, summed.
    (define (fitted (share Expr) (o Expr)) (→ Expr)
      (cond ((= (length (expr-tile share)) (length (expr-tile o))) share)
            ((null? (expr-tile o)) (Apply (Fold (Sum)) (list share) (expr-etype share) (Nil)))
            (else (panic "grad: a share wider than its operand's tile"))))

    ;; Each operand's elements of g, in order, but a literal's, which takes
    ;; none.
    (define (pack-shares (operands (List Expr)) (g Expr)) (→ (List (Option Expr)))
      (reverse
       (● (fold-left (lambda (state o)
                       (let ((size (product (expr-tile o))) (at (● state second)))
                         (new Pair
                           (first (Cons (match o
                                          ((Literal _ _) (None))
                                          (_ (Some
                                              (Apply (Pick (map (lambda (j) (+ at j)) (iota size)))
                                                     (list g)
                                                     (expr-etype g)
                                                     (expr-tile o)))))
                                        (● state first)))
                           (second (+ at size)))))
                     (new Pair (first (Nil)) (second 0))
                     operands)
          first)))

    ;; g put back at the places `indices` took from a's tile: summed where
    ;; a place was taken twice, zero where none took it.
    (define (scattered (g Expr) (indices (List I64)) (a Expr)) (→ Expr)
      (let ((etype (expr-etype g)))
        (Apply (Pack)
               (map (lambda (p)
                      (fold-left (lambda (sum i) (operation (Add) (list sum (element-of g i))))
                                 (Literal 0.0 etype)
                                 (filter (lambda (i) (= (list-ref indices i) p))
                                         (iota (length indices)))))
                    (iota (product (expr-tile a))))
               etype
               (expr-tile a))))

    ;; g at each element a fold combined: all of them for a sum, the chosen
    ;; ones for the largest or smallest.
    (define (folded-share (combining Reduction) (a Expr) (y Expr) (g Expr)) (→ Expr)
      (let ((spread (lambda (v)
                      (Apply (Pack)
                             (map (lambda (_) v) (iota (product (expr-tile a))))
                             (expr-etype v)
                             (expr-tile a)))))
        (match combining
          ((Sum) (spread g))
          (_ (operation (Mul) (list (spread g) (operation (Equal) (list a (spread y)))))))))

    ))
