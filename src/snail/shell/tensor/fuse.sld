;; Fusing maps, as Resin's `fuse_elementwise` fuses its dispatches: a map
;; whose argument another map computes takes that map's body in place of
;; the load, so one kernel computes both, and the producer's buffer is not
;; written unless something else reads it. Fusing rewrites the graph: it
;; answers views of the same values, computed by fewer nodes, for
;; `lower` to lower as it lowers any graph.
;;
;;   (lower gpu "step" (fuse (list loss)) (fuse-updates updates))
;;
;; A producer is inlined into each map that reads it, through that map's
;; view of its port: its loads are seen through the view, which must keep
;; to the port's axes (`seen-through`). Bodies stay within 256
;; expressions, and a kernel within the eight storage buffers every device
;; allows. Each map takes in what it can, from its first argument on,
;; until nothing more fits. A node that is not a map reads its arguments'
;; buffers as before, so a reduction, a matrix product, a gather, a concat,
;; a sort or a custom kernel keeps the map that feeds it. Fusing depends
;; only on a node and what it reads, so fusing twice gives the same nodes,
;; and the sinks and updates of one program may be fused apart.
(define-library (snail shell tensor fuse)
  (export
   fuse
   fuse-updates)
  (import
   (snail core base)
   (snail core table)
   (snail shell tensor))
  (begin

    ;; ---- Rewriting ----

    ;; The roots, each a view of its node fused, in order.
    (define (fuse (roots (List View))) (→ (List View))
      (let ((done (fold-left fused-node (empty-table) (toposort roots))))
        (map (lambda (r) (rewritten done r)) roots)))

    ;; Each update's value fused; its param, a leaf, stays.
    (define (fuse-updates (updates (List (Pair View View)))) (→ (List (Pair View View)))
      (map (lambda (pair) (new Pair (first (● pair first first)) (second (● pair second))))
           (zip updates (fuse (map (lambda (u) (● u second)) updates)))))

    ;; A node rewritten after its arguments: a map with what it can take
    ;; in, any other over its rewritten arguments.
    (define (fused-node (done (Table Node)) (n Node)) (→ (Table Node))
      (let ((args (map (lambda (a) (rewritten done a)) (● n args))))
        (table-set done
                   (● n key)
                   (match (● n kind)
                     ((Map body) (● (absorbed body args (● (port-of n default-port) shape)) node))
                     (_ (with-args n args))))))

    ;; A view of a node, now of its rewritten node: a rewritten map has
    ;; the same port, so the view sees the same elements.
    (define (rewritten (done (Table Node)) (view View)) (→ View)
      (match (table-ref done (● view node key))
        ((Some n) (new View (node n) (port (● view port)) (accessor (● view accessor))))
        ((None) (panic "fuse: a node rewritten before its arguments"))))

    ;; ---- Taking in producers ----

    ;; A map over `args` with each producer it can take in taken in,
    ;; until none can be.
    (define (absorbed (body Expr) (args (List View)) (shape (List I64))) (→ View)
      (match (first-inlined body args 0)
        ((Some next) (absorbed (● next first) (● next second) shape))
        ((None) (mapped body args shape))))

    (define (first-inlined (body Expr) (args (List View)) (k I64))
      (→ (Option (Pair Expr (List View))))
      (if (>= k (length args))
          (None)
          (match (inlined body args k)
            ((Some next) (Some next))
            ((None) (first-inlined body args (+ k 1))))))

    ;; The body and arguments with argument k's producer inlined, when it
    ;; is a map whose loads can be seen through the view of it and the
    ;; result keeps within the limits. Argument k's loads become the
    ;; producer's body, whose loads read the producer's arguments as the
    ;; view sees them, after the others.
    (define (inlined (body Expr) (args (List View)) (k I64)) (→ (Option (Pair Expr (List View))))
      (let ((v (list-ref args k)))
        (match (● v node kind)
          ((Map inner)
           (match (seen-all (● v node args)
                            (● v accessor)
                            (● (port-of (● v node) (● v port)) shape))
             ((Some views)
              (let* ((base (- (length args) 1))
                     (moved (map-loads inner (lambda (j etype) (Load (+ base j) etype))))
                     (combined
                      (distinct (map-loads body
                                           (lambda (j etype)
                                             (cond ((= j k) moved)
                                                   ((> j k) (Load (- j 1) etype))
                                                   (else (Load j etype)))))
                                (append (append (take args k) (list-drop args (+ k 1))) views))))
                (if (within-limits? combined) (Some combined) (None))))
             ((None) (None))))
          (_ (None)))))

    ;; The producer's arguments as the consumer sees them, if each can be.
    (define (seen-all (inner (List View)) (outer Accessor) (shape (List I64)))
      (→ (Option (List View)))
      (fold-right (lambda (a rest)
                    (match rest
                      ((Some views)
                       (match (seen-through (● a accessor) outer shape)
                         ((Some accessor) (Some (Cons (View-accessor-set a accessor) views)))
                         ((None) (None))))
                      ((None) (None))))
                  (Some (Nil))
                  inner))

    ;; ---- Limits ----

    ;; A body of at most 256 expressions, as Resin bounds a fused tree,
    ;; since a producer read twice is inlined twice; and arguments in at
    ;; most seven buffers, for the eight storage buffers every device
    ;; lets a kernel bind, its port being the eighth.

    (define (within-limits? (fused (Pair Expr (List View)))) (→ Bool)
      (and (<= (expr-size (● fused first)) 256) (<= (buffer-count (● fused second)) 7)))

    (define (expr-size (e Expr)) (→ I64)
      (match e
        ((Apply _ operands _) (+ 1 (fold-left + 0 (map expr-size operands))))
        (_ 1)))

    (define (buffer-count (args (List View))) (→ I64)
      (length
       (table-keys (fold-left (lambda (t a) (table-set t (port-name a) #t)) (empty-table) args))))

    (define (port-name (view View)) (→ String)
      (string-append (● view node key) "." (● view port)))

    ;; ---- Loads in order ----

    ;; A body and its arguments with each view loaded once: equal views
    ;; are one argument, numbered in the order the body first loads them,
    ;; depth first, as Resin numbers a fused tree's free loads.
    (define (distinct (body Expr) (args (List View))) (→ (Pair Expr (List View)))
      (let* ((order (first-loads body args (Nil)))
             (index
              (fold-left (lambda (t pair) (table-set t (view-key (● pair second)) (● pair first)))
                         (empty-table)
                         (zip (iota (length order)) order))))
        (new Pair
          (first (map-loads body
                            (lambda (k etype)
                              (match (table-ref index (view-key (list-ref args k)))
                                ((Some j) (Load j etype))
                                ((None) (panic "fuse: a load of no argument"))))))
          (second order))))

    ;; The views a body loads, each once, in the order it first loads them.
    (define (first-loads (e Expr) (args (List View)) (seen (List View))) (→ (List View))
      (match e
        ((Load k _)
         (let ((v (list-ref args k)))
           (if (any? (lambda (s) (string=? (view-key s) (view-key v))) seen)
               seen
               (append seen (list v)))))
        ((Literal _ _) seen)
        ((Apply _ operands _)
         (fold-left (lambda (seen o) (first-loads o args seen)) seen operands))))

    ;; ---- Views of views ----

    ;; A consumer sees a producer's port, dense in `shape`, through
    ;; `outer`; the producer read an argument through `inner`, of that
    ;; shape. The consumer's element is the producer's at the coordinate
    ;; outer's address names, so it reads the argument through inner at
    ;; that coordinate: a view of a view. That is an accessor when each
    ;; axis of outer steps along the port's axes without carrying from one
    ;; into the next, as broadcasting, permuting, narrowing, squeezing and
    ;; splitting an axis do; or when inner is dense, so that every address
    ;; passes through unchanged. A view that merges axes of a port its
    ;; producer read through a strided view is not an accessor, and that
    ;; producer stays a node.
    (define (seen-through (inner Accessor) (outer Accessor) (shape (List I64)))
      (→ (Option Accessor))
      (if (same-list? (● inner pitch) (contiguous-pitch shape))
          (Some (new Accessor
                  (offset (+ (● inner offset) (● outer offset)))
                  (shape (● outer shape))
                  (pitch (● outer pitch))))
          (let ((start (coordinates (● outer offset) shape))
                (steps (map (lambda (p) (coordinates p shape)) (● outer pitch))))
            (if (inside? start steps (● outer shape) shape)
                (Some (new Accessor
                        (offset (+ (● inner offset) (dot (● inner pitch) start)))
                        (shape (● outer shape))
                        (pitch (map (lambda (s) (dot (● inner pitch) s)) steps))))
                (None)))))

    ;; An address as a coordinate of a dense port of `shape`, each axis
    ;; its digit; the first takes all that is left, so an address past the
    ;; port shows as a coordinate past its first axis.
    (define (coordinates (x I64) (shape (List I64))) (→ (List I64))
      (map-indexed (lambda (a pitch)
                     (if (= a 0)
                         (quotient x pitch)
                         (remainder (quotient x pitch) (list-ref shape a))))
                   (contiguous-pitch shape)))

    ;; Whether every coordinate a walk from `start` reaches is inside the
    ;; port: on each axis, the start and each step times the last index
    ;; of its axis of `sizes` stay under the axis's size, so no digit
    ;; carries.
    (define (inside? (start (List I64))
                     (steps (List (List I64)))
                     (sizes (List I64))
                     (shape (List I64)))
      (→ Bool)
      (every? (lambda (a)
                (< (fold-left + (list-ref start a)
                              (map
                               (lambda (pair) (* (list-ref (● pair first) a) (- (● pair second) 1)))
                               (zip steps sizes)))
                   (list-ref shape a)))
              (iota (length shape))))

    (define (dot (a (List I64)) (b (List I64))) (→ I64)
      (fold-left + 0 (map (lambda (pair) (* (● pair first) (● pair second))) (zip a b))))

    (define (same-list? (a (List I64)) (b (List I64))) (→ Bool)
      (and (= (length a) (length b))
           (every? (lambda (pair) (= (● pair first) (● pair second))) (zip a b))))

    ))
