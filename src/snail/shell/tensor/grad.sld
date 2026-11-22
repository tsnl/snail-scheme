;; Reverse-mode gradients as more graph: `grad` walks the nodes a scalar
;; depends on from the last to the first, and builds, for each port, the
;; gradient of the scalar with respect to that port's buffer, as views of
;; new nodes. Nothing runs: the gradient is lowered with everything else.
;;
;;   (grad loss (list w b))   ; dloss/dw and dloss/db, shaped as w and b
;;
;; Each kind of node answers the gradient of each argument given the
;; gradient of each port (`adjoints` below): a map back through its body,
;; a reduction over its span and then back through its body; a custom
;; node answers its own.
;; A view's gradient reaches its port through the view's accessor: summed
;; over the axes it broadcasts, then a view of the port when the view
;; reads all of it in some order of its axes, and placed at the addresses
;; it reads otherwise.
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
      (let ((grads (fold-left backward
                              (accumulate (empty-table) loss (ones-like loss))
                              (reverse (toposort (list loss))))))
        (map (lambda (w) (gradient-of grads w)) wrt)))

    (define (port-key (n Node) (port String)) (→ String) (string-append (● n key) "." port))

    ;; Each argument's share of a node's port gradients, added in.

    (define (backward (grads (Table View)) (n Node)) (→ (Table View))
      (let ((outs (map (lambda (port) (table-ref grads (port-key n (● port name)))) (● n ports))))
        (if (every? none? outs)
            grads
            (fold-left (lambda (grads pair)
                         (match (● pair second)
                           ((Some g) (accumulate grads (● pair first) g))
                           ((None) grads)))
                       grads
                       (zip (● n args) (adjoints n outs))))))

    (define (none? (value (Option View))) (→ Bool)
      (match value
        ((Some _) #f)
        ((None) #t)))

    ;; The gradient `g` of a view, as its port sees it, added to the
    ;; port's.
    (define (accumulate (grads (Table View)) (view View) (g View)) (→ (Table View))
      (let ((key (port-key (● view node) (● view port))) (share (through-accessor view g)))
        (table-set grads
                   key
                   (match (table-ref grads key)
                     ((Some existing) (+ existing share))
                     ((None) share)))))

    ;; The gradient of a view's port given the view's: summed over the
    ;; axes the view broadcasts, then the port's shape. A view that reads
    ;; its whole port, in its port's order or another order of its axes,
    ;; passes the gradient back as a view, its axes put back in the port's
    ;; order; any other places it.

    (define (through-accessor (view View) (g View)) (→ View)
      (let* ((a (● view accessor))
             (spread (filter (lambda (k)
                               (and (= (list-ref (● a pitch) k) 0) (> (list-ref (● a shape) k) 1)))
                             (iota (length (● a shape)))))
             (summed (if (null? spread) g (sum g spread)))
             (seen
              (new Accessor (offset (● a offset)) (shape (shape-of summed)) (pitch (● a pitch))))
             (shape (● (port-of (● view node) (● view port)) shape)))
        (match (port-order seen shape)
          ((Some order) (shaped (permute summed order) shape))
          ((None) (place summed seen shape)))))

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
    (define (gradient-of (grads (Table View)) (w View)) (→ View)
      (match (table-ref grads (port-key (● w node) (● w port)))
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
        (_ (single-port-adjoints n (first-gradient outs)))))

    ;; A node of one port, `out`, whose gradient is g.
    (define (single-port-adjoints (n Node) (g View)) (→ (List (Option View)))
      (let ((args (● n args)) (y (node-view n default-port)))
        (match (● n kind)
          ((Map body) (map-adjoints body args y g))
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
             (spread (lambda (v)
                       (broadcast-to (fold-left (lambda (v _) (unsqueeze v (rank v))) v span)
                                     shape)))
             (share (match op
                      ((Sum) (spread g))
                      (_ (* (spread g) (equal value (spread y)))))))
        (map-adjoints body args value share)))

    ;; ---- Maps ----

    ;; The gradient of each argument of a map whose port's gradient is g,
    ;; back through its body from the top, whose value is the port's, y:
    ;; each operation hands each operand its share of the operation's
    ;; gradient, and each load adds its share to its argument's. An
    ;; operand that is itself an operation is built again as a node of its
    ;; own, for the rules that need its value.

    (define (map-adjoints (body Expr) (args (List View)) (y View) (g View)) (→ (List (Option View)))
      (let ((shares (expr-adjoints body y g args (empty-table))))
        (map (lambda (k) (table-ref shares (show k))) (iota (length args)))))

    (define (expr-adjoints (e Expr) (value View) (g View) (args (List View)) (shares (Table View)))
      (→ (Table View))
      (match e
        ((Load k _)
         (table-set shares
                    (show k)
                    (match (table-ref shares (show k))
                      ((Some share) (+ share g))
                      ((None) g))))
        ((Literal _ _) shares)
        ((Apply op operands _)
         (let ((values (map (lambda (o) (expr-view o args (shape-of value))) operands)))
           (fold-left (lambda (shares pair)
                        (match (● pair second)
                          ((Some share)
                           (expr-adjoints (list-ref operands (● pair first))
                                          (list-ref values (● pair first))
                                          share
                                          args
                                          shares))
                          ((None) shares)))
                      shares
                      (zip (iota (length operands)) (op-adjoints op values value g)))))))

    ;; What an expression of a map's body computes, as a view of `shape`:
    ;; an argument itself for a load.
    (define (expr-view (e Expr) (args (List View)) (shape (List I64))) (→ View)
      (match e
        ((Load k _) (list-ref args k))
        ((Literal value etype) (fill value (Nil) etype))
        ((Apply op operands etype)
         (mapped (Apply op
                        (map-indexed (lambda (k o) (Load k (expr-etype o))) operands)
                        etype)
                 (map (lambda (o) (expr-view o args shape)) operands)
                 shape))))

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

    ))
