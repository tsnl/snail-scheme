;; Reverse-mode gradients as more graph: `grad` walks the nodes a scalar
;; depends on from the last to the first, and builds, for each port, the
;; gradient of the scalar with respect to that port's buffer, as views of
;; new nodes. Nothing runs: the gradient is compiled with everything else.
;;
;;   (grad loss (list w b))   ; dloss/dw and dloss/db, shaped as w and b
;;
;; Each kind of node answers the gradient of each argument given the
;; gradient of each port (`adjoints` below); a custom node answers its own.
;; A view's gradient reaches its port through the view's accessor: summed
;; over the axes it broadcasts, then placed at the addresses it reads.
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
    ;; axes the view broadcasts, then the port's shape, by a reshape when
    ;; the view reads its whole port in order and by placing it otherwise.

    (define (through-accessor (view View) (g View)) (→ View)
      (let* ((a (● view accessor))
             (spread (filter (lambda (k)
                               (and (= (list-ref (● a pitch) k) 0) (> (list-ref (● a shape) k) 1)))
                             (iota (length (● a shape)))))
             (summed (if (null? spread) g (sum g spread)))
             (reduced (new Accessor
                        (offset (● a offset))
                        (shape (shape-of summed))
                        (pitch (● a pitch))))
             (port (port-of (● view node) (● view port))))
        (if (whole? reduced (● port shape))
            (reshape summed (● port shape))
            (place summed reduced (● port shape)))))

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
      (let ((g (first-gradient outs)) (args (● n args)) (y (node-view n default-port)))
        (match (● n kind)
          ((Elementwise op) (elementwise-adjoints op args y g))
          ((Reduce op _) (list (Some (reduce-adjoint op (list-ref args 0) y g))))
          ((Matmul)
           (list (Some (matmul g (transpose (list-ref args 1))))
                 (Some (matmul (transpose (list-ref args 0)) g))))
          ((Copy) (list (Some g)))
          ((Place accessor)
           (list (Some (View-accessor-set (if (identity? g) g (copy g)) accessor))))
          ((Gather)
           (list (Some (scatter-add g (list-ref args 1) (list-ref (shape-of (list-ref args 0)) 0)))
                 (None)))
          ((ScatterAdd _) (list (Some (gather g (list-ref args 1))) (None)))
          ((CustomKind c) ((● c adjoint) args outs))
          (_ (map (lambda (_) (None)) args)))))

    (define (first-gradient (outs (List (Option View)))) (→ View)
      (match (find (lambda (out) (not (none? out))) outs)
        ((Some (Some g)) g)
        (_ (panic "grad: a node with no port gradient"))))

    (define (reduce-adjoint (op Reduction) (a View) (y View) (g View)) (→ View)
      (match op
        ((Sum) (broadcast-to g (shape-of a)))
        (_ (* (broadcast-to g (shape-of a)) (equal a (broadcast-to y (shape-of a)))))))

    ;; d/da and d/db of y = op(a, b), each times g; operations that are
    ;; flat or not continuous pass no gradient.

    (define (elementwise-adjoints (op Op) (args (List View)) (y View) (g View))
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
