;; Fusing maps, as Resin's `fuse_elementwise` fuses its dispatches: a map
;; whose argument another map computes takes that map's body in place of
;; the load, so one kernel computes both, and the producer's buffer is not
;; written unless something else reads it. Fusing rewrites a program's
;; graph: it answers views of the same values, computed by fewer nodes,
;; for `lower` to lower as it lowers any graph.
;;
;;   (let ((fused (fuse-program sinks updates)))
;;     (lower "step" (● fused first) (● fused second)))
;;
;; A producer is inlined into each map that reads it, through that map's
;; view of its port: its loads are seen through the view, which must keep
;; to the port's axes (`seen-through`). Bodies stay within 256
;; expressions, and a kernel within the eight storage buffers every device
;; allows. A reduction's body takes in maps as a map's does, so a matrix
;; product computes its products as it sums them; but nothing takes in a
;; reduction, whose port is written. Any other node reads its arguments'
;; buffers as before, so a gather, a concat, a sort or a custom kernel
;; keeps the map that feeds it.
;;
;; Fusing plans from the roots down: a map takes in what it can, from its
;; first argument on, until nothing more fits, before anything it reads
;; takes in anything, so what it took in never leaves it too wide for the
;; map reading it. A producer that several kernels take in is computed in
;; each, and what it reads stays alive until the last of them, so one
;; read more than once is taken in only where that holds no more than its
;; own buffer would (`worth-taking?`). That weighs every node reading a
;; producer, so a program's sinks and updates are fused together.
(define-library (snail shell tensor fuse)
  (export
   fuse
   fuse-program)
  (import
   (snail core base)
   (snail core table)
   (snail shell tensor))
  (begin

    ;; ---- Rewriting ----

    ;; What fusing decided, from the roots down: the nodes still read, by
    ;; key, and the body and arguments each such map or reduction took in.
    (record Plan
      ((read (Table Bool))
       (bodies (Table (Pair Expr (List View))))))

    ;; The roots, each a view of its node fused, in order: planned from the
    ;; roots down, then built from the leaves up.
    (define (fuse (roots (List View))) (→ (List View))
      (let* ((order (toposort roots))
             (graph (graph-of order roots))
             (plan (fold-left (lambda (plan n) (planned graph plan n))
                              (new Plan (read (marked (empty-table) roots)) (bodies (empty-table)))
                              (reverse order)))
             (done (fold-left (lambda (done n) (built plan done n)) (empty-table) order)))
        (map (lambda (r) (rewritten done r)) roots)))

    ;; A program's sinks and updates fused as one graph: each update's
    ;; value fused, its param, a leaf, kept.
    (define (fuse-program (sinks (List View)) (updates (List (Pair View View))))
      (→ (Pair (List View) (List (Pair View View))))
      (let ((fused (fuse (append sinks (map (lambda (u) (● u second)) updates)))))
        (new Pair
          (first (take fused (length sinks)))
          (second
           (map (lambda (pair) (new Pair (first (● pair first first)) (second (● pair second))))
                (zip updates (list-drop fused (length sinks))))))))

    ;; A node still read, planned after all that read it: a map or a
    ;; reduction takes in what its body can, and then what it reads is
    ;; read; any other reads its arguments.
    (define (planned (graph Graph) (plan Plan) (n Node)) (→ Plan)
      (if (table-contains? (● plan read) (● n key))
          (match (body-of n)
            ((Some body)
             (let ((taken (absorbed graph (place-in (● graph places) n) body (● n args))))
               (new Plan
                 (read (marked (● plan read) (● taken second)))
                 (bodies (table-set (● plan bodies) (● n key) taken)))))
            ((None) (Plan-read-set plan (marked (● plan read) (● n args)))))
          plan))

    (define (body-of (n Node)) (→ (Option Expr))
      (match (● n kind)
        ((Map body) (Some body))
        ((Reduce _ _ body) (Some body))
        (_ (None))))

    (define (marked (read (Table Bool)) (views (List View))) (→ (Table Bool))
      (fold-left (lambda (t v) (table-set t (● v node key) #t)) read views))

    ;; A node still read, built after what it reads: a map or a reduction
    ;; over the body it took in, any other over its arguments rebuilt.
    (define (built (plan Plan) (done (Table Node)) (n Node)) (→ (Table Node))
      (if (table-contains? (● plan read) (● n key))
          (table-set done
                     (● n key)
                     (match (table-ref (● plan bodies) (● n key))
                       ((Some taken)
                        (rebuilt n
                                 (● taken first)
                                 (map (lambda (a) (rewritten done a)) (● taken second))))
                       ((None) (with-args n (map (lambda (a) (rewritten done a)) (● n args))))))
          done))

    ;; A map or a reduction as `n` is, over `body` and `args`.
    (define (rebuilt (n Node) (body Expr) (args (List View))) (→ Node)
      (let ((shape (● (port-of n default-port) shape)))
        (● (match (● n kind)
             ((Map _) (mapped body args shape))
             ((Reduce op span _) (reduced op body args shape span))
             (_ (panic "fuse: only a map or a reduction takes in a body")))
           node)))

    ;; A view of a node, now of its rewritten node: a rewritten map has
    ;; the same port, so the view sees the same elements.
    (define (rewritten (done (Table Node)) (view View)) (→ View)
      (match (table-ref done (● view node key))
        ((Some n) (new View (node n) (port (● view port)) (accessor (● view accessor))))
        ((None) (panic "fuse: a node rewritten before its arguments"))))

    ;; ---- The graph as given ----

    ;; Each node's place in the order lowering runs it, and what reads
    ;; each, by key: what sharing weighs.
    (record Graph
      ((places (Table I64))
       (readers (Table (List Reader)))))

    ;; A node reading another: its place, and how many of the other's
    ;; elements its views of it see. The roots are read whole at the end,
    ;; since their ports are kept.
    (record Reader
      ((place I64)
       (seen I64)))

    (define (graph-of (order (List Node)) (roots (List View))) (→ Graph)
      (let* ((places (fold-left (lambda (t pair) (table-set t (● pair second key) (● pair first)))
                                (empty-table)
                                (zip (iota (length order)) order)))
             (read (fold-left (lambda (t n) (read-by t (place-in places n) (● n args)))
                              (empty-table)
                              order)))
        (new Graph (places places) (readers (read-by read (length order) roots)))))

    ;; `readers` with a node at `place` reading `views`, each distinct view
    ;; once.
    (define (read-by (readers (Table (List Reader))) (place I64) (views (List View)))
      (→ (Table (List Reader)))
      (fold-left (lambda (t v)
                   (table-set t
                              (● v node key)
                              (Cons (new Reader (place place) (seen (product (shape-of v))))
                                    (readers-of t (● v node)))))
                 readers
                 (fold-left (lambda (seen v)
                              (if (any? (lambda (s) (string=? (view-key s) (view-key v))) seen)
                                  seen
                                  (append seen (list v))))
                            (Nil)
                            views)))

    (define (readers-of (readers (Table (List Reader))) (n Node)) (→ (List Reader))
      (match (table-ref readers (● n key))
        ((Some those) those)
        ((None) (Nil))))

    (define (place-in (places (Table I64)) (n Node)) (→ I64)
      (match (table-ref places (● n key))
        ((Some place) place)
        ((None) (panic "fuse: a node out of order"))))

    ;; ---- Taking in producers ----

    ;; A body over `args`, of the kernel at `place`, with each producer it
    ;; can take in taken in, until none can be.
    (define (absorbed (graph Graph) (place I64) (body Expr) (args (List View)))
      (→ (Pair Expr (List View)))
      (match (first-taken graph place body args 0)
        ((Some next) (absorbed graph place (● next first) (● next second)))
        ((None) (new Pair (first body) (second args)))))

    ;; The body and arguments with the first producer from argument k on
    ;; that fits and is worth taking in taken in.
    (define (first-taken (graph Graph) (place I64) (body Expr) (args (List View)) (k I64))
      (→ (Option (Pair Expr (List View))))
      (if (>= k (length args))
          (None)
          (match (inlined body args k)
            ((Some next)
             (if (worth-taking? graph place (● (list-ref args k) node) args)
                 (Some next)
                 (first-taken graph place body args (+ k 1))))
            ((None) (first-taken graph place body args (+ k 1))))))

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

    ;; ---- Sharing ----

    ;; Taking in a producer whose readers see each of its elements at most
    ;; once computes nothing twice, so it is taken in wherever it fits.
    ;; One read more is computed in each kernel taking it in, and the
    ;; buffers it reads stay alive until that kernel: from the producer's
    ;; place, where it would read them as a kernel of its own, to the
    ;; reader's. It is taken in only where those buffers hold no more
    ;; bytes for those steps than its own would. A buffer the kernel binds
    ;; already, or that a node there or later reads, costs nothing.
    (define (worth-taking? (graph Graph) (place I64) (producer Node) (args (List View))) (→ Bool)
      (let ((made (place-in (● graph places) producer)))
        (or (not (shared? graph producer))
            (<= (kept-alive graph made place producer args)
                (* (port-bytes producer) (- place made))))))

    ;; Whether what reads a node sees more elements than it has.
    (define (shared? (graph Graph) (n Node)) (→ Bool)
      (> (fold-left + 0 (map (lambda (r) (● r seen)) (readers-of (● graph readers) n)))
         (fold-left + 0 (map (lambda (p) (product (● p shape))) (● n ports)))))

    ;; Bytes times steps: what the buffers under `producer` add, kept
    ;; alive from `made` to `place` by a kernel binding `args`.
    (define (kept-alive (graph Graph) (made I64) (place I64) (producer Node) (args (List View)))
      (→ I64)
      (fold-left + 0
                 (map (lambda (n)
                        (if (any? (lambda (a) (string=? (● a node key) (● n key))) args)
                            0
                            (* (port-bytes n) (max 0 (- place (max made (last-read graph n)))))))
                      (table-values (buffers-under graph producer (empty-table))))))

    (define (last-read (graph Graph) (n Node)) (→ I64)
      (fold-left (lambda (last r) (max last (● r place))) -1 (readers-of (● graph readers) n)))

    ;; The pooled buffers a map reads, by key, directly or through the maps
    ;; it alone reads, which are taken in with it; a map others read too is
    ;; weighed in its own turn.
    (define (buffers-under (graph Graph) (n Node) (found (Table Node))) (→ (Table Node))
      (fold-left (lambda (found a)
                   (let ((m (● a node)))
                     (cond ((or (table-contains? found (● m key)) (not (pooled? m))) found)
                           ((map-kind? m)
                            (if (shared? graph m) found (buffers-under graph m found)))
                           (else (table-set found (● m key) m)))))
                 found
                 (● n args)))

    (define (map-kind? (n Node)) (→ Bool)
      (match (● n kind)
        ((Map _) #t)
        (_ #f)))

    ;; Whether a node's ports are in buffers lowering pools: a param's,
    ;; a constant's and a fill's are not.
    (define (pooled? (n Node)) (→ Bool)
      (match (● n kind)
        ((Param _) #f)
        ((Constant _ _) #f)
        ((Fill _) #f)
        (_ #t)))

    (define (port-bytes (n Node)) (→ I64)
      (fold-left + 0 (map (lambda (p) (* 4 (product (● p shape)))) (● n ports))))

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
