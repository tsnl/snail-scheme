;; Fusing maps, as Resin's `fuse_elementwise` fuses its dispatches: a map
;; whose argument another map computes takes that map's body in place of
;; the load, so one kernel computes both, and the producer's buffer is not
;; written unless something else reads it. Fusing rewrites a program's
;; graph: it answers views of the same values, computed by fewer nodes,
;; for `lower` to lower as it lowers any graph.
;;
;;   (let ((fused (fuse-program sinks updates)))
;;     (lower gpu "step" (● fused first) (● fused second)))
;;
;; A producer is inlined into each map that reads it, through that map's
;; view of its port: its loads are seen through the view, which must keep
;; to the port's axes (`seen-through`). A map of tiles, as a small matrix
;; product is, computes a tile once, so the view must read whole tiles of
;; it, and a map of values reading one so becomes a map of those tiles to
;; take it in (`at-tiles`). Bodies stay within 256 distinct expressions,
;; and a kernel within the eight storage buffers every device allows. A
;; reduction's body takes in maps as a map's does, so a large matrix
;; product computes its products as it sums them; but nothing takes in a
;; reduction, whose port is written. Any other node reads its arguments'
;; buffers as before, so a gather, a concat, a sort or a custom kernel
;; keeps the map that feeds it.
;;
;; Fusing plans from the roots down: a map takes in what it can, from its
;; first argument on, until nothing more fits, before anything it reads
;; takes in anything, so what it took in never leaves it too wide for the
;; map reading it. A producer that several kernels take in is computed in
;; each, reading what it reads in each, and what it reads stays alive
;; until the last of them, so one read more than once is taken in only
;; where that reads and holds no more than its own kernel and buffer would
;; (`worth-taking?`). That weighs every node reading a producer, so a
;; program's sinks and updates are fused together.
;;
;; A producer whose port is kept anyway, an update's value, a sink, or a
;; buffer a later kernel reads, is computed by its own kernel even where a
;; map reads it. A map reading it whole, at the elements each of its
;; threads computes, takes it in and writes its port too, a port of its
;; own, so the producer needs no kernel, where nothing that runs before
;; that map reads it (`writable?`): Adam's update of a param reads the
;; moments it updates, and the three become one kernel of three ports.
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

    ;; A map or a reduction being fused: the axes its bodies are computed
    ;; at, a map's ports' leading axes or a reduction's port's and its
    ;; span's; its own body, then one for each producer it writes too, in
    ;; `written`'s order; the producers it took in that nothing else
    ;; reads, whose reads are its own; and the arguments the bodies load.
    (record Fusing
      ((node Node)
       (lead (List I64))
       (bodies (List Expr))
       (written (List Node))
       (taken (List Node))
       (args (List View))))

    ;; What fusing decided, from the roots down: the nodes still read, by
    ;; key, what each such map or reduction took in, and the producers a
    ;; kernel writes, which have no kernel of their own.
    (record Plan
      ((read (Table Bool))
       (bodies (Table Fusing))
       (written (Table Bool))))

    ;; A node as fusing built it, and the port of it that sees what a view
    ;; of the old node's port saw: a producer a kernel writes is a port of
    ;; that kernel's node.
    (record Made
      ((node Node)
       (port (Option String))))

    ;; The roots, each a view of its node fused, in order: planned from the
    ;; roots down, then built from the leaves up.
    (define (fuse (roots (List View))) (→ (List View)) (fused-with roots (empty-table)))

    ;; A program's sinks and updates fused as one graph: each update's
    ;; value fused, its param, a leaf, kept.
    (define (fuse-program (sinks (List View)) (updates (List (Pair View View))))
      (→ (Pair (List View) (List (Pair View View))))
      (let ((fused (fused-with (append sinks (map (lambda (u) (● u second)) updates))
                               (update-targets updates))))
        (new Pair
          (first (take fused (length sinks)))
          (second
           (map (lambda (pair) (new Pair (first (● pair first first)) (second (● pair second))))
                (zip updates (list-drop fused (length sinks))))))))

    (define (fused-with (roots (List View)) (targets (Table Node))) (→ (List View))
      (let* ((order (toposort roots))
             (graph (graph-of order roots targets))
             (plan (fold-left (lambda (plan n) (planned graph plan n))
                              (new Plan
                                (read (marked (empty-table) roots))
                                (bodies (empty-table))
                                (written (empty-table)))
                              (reverse order)))
             (done (fold-left (lambda (done n) (built plan done n)) (empty-table) order)))
        (map (lambda (r) (rewritten done r)) roots)))

    ;; The param each update writes, by the key of the node whose whole
    ;; port is its value: what a kernel writing that port may write in
    ;; place (`bindings`).
    (define (update-targets (updates (List (Pair View View)))) (→ (Table Node))
      (fold-left (lambda (t u)
                   (if (identity? (● u second))
                       (table-set t (● u second node key) (● u first node))
                       t))
                 (empty-table)
                 updates))

    ;; A node still read, planned after all that read it: a map or a
    ;; reduction takes in what its body can, and then what it reads is
    ;; read; any other reads its arguments. A producer a kernel writes was
    ;; planned with that kernel.
    (define (planned (graph Graph) (plan Plan) (n Node)) (→ Plan)
      (if (and (table-contains? (● plan read) (● n key))
               (not (table-contains? (● plan written) (● n key))))
          (match (body-of n)
            ((Some body)
             (let ((taken (absorbed graph
                                    (● plan read)
                                    (place-in (● graph places) n)
                                    (new Fusing
                                      (node n)
                                      (lead (lead-of n))
                                      (bodies (list body))
                                      (written (Nil))
                                      (taken (Nil))
                                      (args (● n args))))))
               (new Plan
                 (read (marked (● plan read) (● taken args)))
                 (bodies (table-set (● plan bodies) (● n key) taken))
                 (written (fold-left (lambda (t w) (table-set t (● w key) #t))
                                     (● plan written)
                                     (● taken written))))))
            ((None) (Plan-read-set plan (marked (● plan read) (● n args)))))
          plan))

    ;; The body a node fuses from: a map's, when it has one, or a
    ;; reduction's. A map of several bodies is fusing's own making.
    (define (body-of (n Node)) (→ (Option Expr))
      (match (● n kind)
        ((Map bodies) (one-body bodies))
        ((Reduce _ _ body) (Some body))
        (_ (None))))

    (define (one-body (bodies (List Expr))) (→ (Option Expr))
      (match bodies
        ((Cons body (Nil)) (Some body))
        (_ (None))))

    ;; The axes a body is computed at: a map's port's leading axes, before
    ;; its body's tile; a reduction's port's axes and its span's.
    (define (lead-of (n Node)) (→ (List I64))
      (let ((shape (● (port-of n default-port) shape)))
        (match (● n kind)
          ((Map bodies) (take shape (- (length shape) (length (expr-tile (list-ref bodies 0))))))
          ((Reduce _ span _) (append shape span))
          (_ shape))))

    (define (marked (read (Table Bool)) (views (List View))) (→ (Table Bool))
      (fold-left (lambda (t v) (table-set t (● v node key) #t)) read views))

    ;; A node still read, built after what it reads: a map or a reduction
    ;; over the bodies it took in, any other over its arguments rebuilt.
    ;; A producer a kernel writes is read by nothing before that kernel,
    ;; which makes it a port when it is built.
    (define (built (plan Plan) (done (Table Made)) (n Node)) (→ (Table Made))
      (cond ((table-contains? (● plan written) (● n key)) done)
            ((not (table-contains? (● plan read) (● n key))) done)
            (else
             (match (table-ref (● plan bodies) (● n key))
               ((Some taken) (built-fused done n taken))
               ((None)
                (table-set done
                           (● n key)
                           (new Made
                             (node (with-args n (map (lambda (a) (rewritten done a)) (● n args))))
                             (port (None)))))))))

    ;; A kernel's node, and each producer it writes as its port k + 1.
    (define (built-fused (done (Table Made)) (n Node) (taken Fusing)) (→ (Table Made))
      (let ((m (rebuilt n (● taken bodies) (map (lambda (a) (rewritten done a)) (● taken args)))))
        (fold-left (lambda (done pair)
                     (table-set done
                                (● pair second key)
                                (new Made (node m) (port (Some (map-port-name (● pair first)))))))
                   (table-set done (● n key) (new Made (node m) (port (None))))
                   (zip (map (lambda (k) (+ k 1)) (iota (length (● taken written))))
                        (● taken written)))))

    ;; A map or a reduction as `n` is, over `bodies` and `args`: a map at
    ;; its port's axes before the first body's tile, which may now be
    ;; larger, with a port for each body.
    (define (rebuilt (n Node) (bodies (List Expr)) (args (List View))) (→ Node)
      (let ((shape (● (port-of n default-port) shape)) (body (list-ref bodies 0)))
        (match (● n kind)
          ((Map _)
           (mapped-ports bodies args (take shape (- (length shape) (length (expr-tile body))))))
          ((Reduce op span _) (● (reduced op body args shape span) node))
          (_ (panic "fuse: only a map or a reduction takes in a body")))))

    ;; A view of a node, now of its rewritten node: a rewritten map has
    ;; the same port, so the view sees the same elements, and a producer a
    ;; kernel writes is that kernel's port.
    (define (rewritten (done (Table Made)) (view View)) (→ View)
      (match (table-ref done (● view node key))
        ((Some made)
         (new View
           (node (● made node))
           (port (match (● made port)
                   ((Some port) port)
                   ((None) (● view port))))
           (accessor (● view accessor))))
        ((None) (panic "fuse: a node rewritten before its arguments"))))

    ;; ---- The graph as given ----

    ;; Each node's place in the order lowering runs it, and what reads
    ;; each, by key: what sharing weighs. The roots are read at `end`,
    ;; after every node, and `targets` holds the param each update writes,
    ;; by its value's node.
    (record Graph
      ((places (Table I64))
       (readers (Table (List Reader)))
       (end I64)
       (targets (Table Node))))

    ;; A node reading another: its place, and how many of the other's
    ;; elements its views of it see. The roots are read whole at the end,
    ;; since their ports are kept.
    (record Reader
      ((place I64)
       (seen I64)))

    (define (graph-of (order (List Node)) (roots (List View)) (targets (Table Node))) (→ Graph)
      (let* ((places (fold-left (lambda (t pair) (table-set t (● pair second key) (● pair first)))
                                (empty-table)
                                (zip (iota (length order)) order)))
             (read (fold-left (lambda (t n) (read-by t (place-in places n) (● n args)))
                              (empty-table)
                              order)))
        (new Graph
          (places places)
          (readers (read-by read (length order) roots))
          (end (length order))
          (targets targets))))

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

    ;; A body, of the kernel at `place`, with each producer it can take
    ;; in taken in, until none can be; `kept` holds the nodes the kernels
    ;; planned before it read.
    (define (absorbed (graph Graph) (kept (Table Bool)) (place I64) (f Fusing)) (→ Fusing)
      (match (first-taken graph kept place f 0)
        ((Some next) (absorbed graph kept place next))
        ((None) f)))

    ;; The bodies with the first producer from argument k on taken in
    ;; that the kernel can write, or that fits and is worth taking in.
    (define (first-taken (graph Graph) (kept (Table Bool)) (place I64) (f Fusing) (k I64))
      (→ (Option Fusing))
      (if (>= k (length (● f args)))
          (None)
          (or-taken (taken-at graph kept place f k)
                    (lambda () (first-taken graph kept place f (+ k 1))))))

    ;; Argument k's producer written as well as taken in where the kernel
    ;; can write it, which computes nothing twice and spares its kernel;
    ;; else taken in where that fits and is worth it.
    (define (taken-at (graph Graph) (kept (Table Bool)) (place I64) (f Fusing) (k I64))
      (→ (Option Fusing))
      (or-taken (if (writable? graph kept place f k) (written-in graph kept place f k) (None))
                (lambda ()
                  (match (taking-in graph place f k (None))
                    ((Some next)
                     (if (worth-taking? graph
                                        kept
                                        place
                                        (● (list-ref (● f args) k) node)
                                        (● f args)
                                        (● next args))
                         (Some next)
                         (None)))
                    ((None) (None))))))

    ;; Argument k's producer taken in and written, fused first as its own
    ;; kernel would be: what it takes in that nothing else reads comes in
    ;; with it, so the kernel's limits weigh what the kernel will bind,
    ;; and the reads of what it took in are the kernel's.
    (define (written-in (graph Graph) (kept (Table Bool)) (place I64) (f Fusing) (k I64))
      (→ (Option Fusing))
      (let* ((v (list-ref (● f args) k))
             (p (● v node))
             (own (absorbed graph kept (place-in (● graph places) p) (unfused p))))
        (taking-in graph
                   place
                   (if (null? (● own written))
                       (new Fusing
                         (node (● f node))
                         (lead (● f lead))
                         (bodies (● f bodies))
                         (written (● f written))
                         (taken (append (● f taken) (● own taken)))
                         (args (map-indexed (lambda (j a)
                                              (if (= j k)
                                                  (new View
                                                    (node (rebuilt p (● own bodies) (● own args)))
                                                    (port (● v port))
                                                    (accessor (● v accessor)))
                                                  a))
                                            (● f args))))
                       f)
                   k
                   (Some p))))

    ;; A map of one body as it is, before it takes anything in.
    (define (unfused (n Node)) (→ Fusing)
      (new Fusing
        (node n)
        (lead (lead-of n))
        (bodies (match (body-of n)
                  ((Some body) (list body))
                  ((None) (panic "fuse: a producer written has no body"))))
        (written (Nil))
        (taken (Nil))
        (args (● n args))))

    (define (or-taken (taken (Option Fusing)) (otherwise (Fn → (Option Fusing))))
      (→ (Option Fusing))
      (match taken
        ((Some _) taken)
        ((None) (otherwise))))

    ;; The bodies with argument k's producer inlined, each load of it a
    ;; tile of the axes after the bodies': computed a tile at a time first,
    ;; when it reads a map of tiles a whole tile at a time (`at-tiles`).
    ;; Written, as `writes` says, the producer's body is one more, its port
    ;; the kernel's; taken in and read by nothing else, its reads are the
    ;; kernel's.
    (define (taking-in (graph Graph) (place I64) (f Fusing) (k I64) (writes (Option Node)))
      (→ (Option Fusing))
      (let* ((v (list-ref (● f args) k))
             (at (at-tiles f v))
             (tile (list-drop (shape-of v) (length (● at lead)))))
        (match (inlined (● at bodies) (● f args) k tile (some-node? writes))
          ((Some next)
           (let ((taken (new Fusing
                          (node (● f node))
                          (lead (● at lead))
                          (bodies (● next first))
                          (written (match writes
                                     ((Some w) (append (● f written) (list w)))
                                     ((None) (● f written))))
                          (taken (if (and (not (some-node? writes))
                                          (read-only-by? graph place f (● v node)))
                                     (append (● f taken) (list (● v node)))
                                     (● f taken)))
                          (args (● next second)))))
             (if (within-limits? graph place taken) (Some taken) (None))))
          ((None) (None)))))

    (define (some-node? (n (Option Node))) (→ Bool)
      (match n
        ((Some _) #t)
        ((None) #f)))

    ;; The bodies and arguments with argument k's producer inlined, when
    ;; it is a map whose loads can be seen through the view of it, which
    ;; is loaded as `tile`s. Argument k's loads become the producer's body,
    ;; whose loads read the producer's arguments as the view sees them,
    ;; after the others; `writing` adds that body as the last.
    (define (inlined (bodies (List Expr))
                     (args (List View))
                     (k I64)
                     (tile (List I64))
                     (writing Bool))
      (→ (Option (Pair (List Expr) (List View))))
      (let ((v (list-ref args k)))
        (match (single-body (● v node))
          ((Some inner)
           (match (as-loaded v inner tile)
             ((Some through)
              (let* ((base (- (length args) 1))
                     (moved (map-loads (● through first)
                                       (lambda (j etype tile) (Load (+ base j) etype tile))))
                     (renumbered (lambda (body)
                                   (map-loads body
                                              (lambda (j etype tile)
                                                (cond ((= j k) moved)
                                                      ((> j k) (Load (- j 1) etype tile))
                                                      (else (Load j etype tile))))))))
                (Some (distinct (append (map renumbered bodies) (if writing (list moved) (Nil)))
                                (append (append (take args k) (list-drop args (+ k 1)))
                                        (● through second))))))
             ((None) (None))))
          ((None) (None)))))

    ;; A map's body, when it has one.
    (define (single-body (n Node)) (→ (Option Expr))
      (match (● n kind)
        ((Map bodies) (one-body bodies))
        (_ (None))))

    ;; ---- Writing producers ----

    ;; Whether the map at `place` can write argument k's producer as well
    ;; as take it in, so that the producer needs no kernel of its own: a
    ;; map of one body, read whole and in order, so that each thread
    ;; computes the producer's elements it loads; through no other view;
    ;; kept, its port read by a kernel planned before or by the roots; and
    ;; read by nothing but what the kernel takes in or writes already and
    ;; what runs after it, which reads the port the kernel wrote. So the
    ;; backward pass reads what the forward pass computed for itself
    ;; anyway, from the forward's kernel, and the step of bicycle's
    ;; training at 7,000 runs 25 fewer kernels.
    (define (writable? (graph Graph) (kept (Table Bool)) (place I64) (f Fusing) (k I64)) (→ Bool)
      (let* ((v (list-ref (● f args) k))
             (producer (● v node))
             (readers (readers-of (● graph readers) producer)))
        (and (map-kind? (● f node))
             (some-body? producer)
             (identity? v)
             (every? (lambda (a)
                       (or (string=? (view-key a) (view-key v))
                           (not (string=? (● a node key) (● producer key)))))
                     (● f args))
             (every? (lambda (r) (or (> (● r place) place) (in-kernel? graph place f (● r place))))
                     readers)
             (table-contains? kept (● producer key)))))

    (define (some-body? (n Node)) (→ Bool)
      (match (single-body n)
        ((Some _) #t)
        ((None) #f)))

    ;; Whether a reader at `at` is the kernel at `place`: the kernel
    ;; itself, a producer it writes, or one it took in that nothing else
    ;; reads.
    (define (in-kernel? (graph Graph) (place I64) (f Fusing) (at I64)) (→ Bool)
      (or (= at place)
          (any? (lambda (n) (= at (place-in (● graph places) n)))
                (append (● f written) (● f taken)))))

    ;; Whether nothing but the kernel at `place` reads a node.
    (define (read-only-by? (graph Graph) (place I64) (f Fusing) (n Node)) (→ Bool)
      (every? (lambda (r) (in-kernel? graph place f (● r place))) (readers-of (● graph readers) n)))

    ;; ---- Tiles ----

    ;; A map of values that reads a map of tiles a whole tile at a time,
    ;; over its port's last axes, computed a tile of those axes at a time,
    ;; so that it can take that map in; any other body as it is.
    (define (at-tiles (f Fusing) (a View)) (→ Fusing)
      (match (if (and (map-kind? (● f node)) (every? untiled? (● f bodies)))
                 (tile-reading (● f lead) a)
                 (None))
        ((Some tile)
         (Fusing-bodies-set
          (Fusing-lead-set f (take (● f lead) (- (length (● f lead)) (length tile))))
          (map (lambda (body) (lifted body tile)) (● f bodies))))
        ((None) f)))

    ;; The fewest of `lead`'s last axes at which a view of a map of tiles
    ;; reads whole tiles of it.
    (define (tile-reading (lead (List I64)) (a View)) (→ (Option (List I64)))
      (match (single-body (● a node))
        ((Some inner)
         (if (null? (expr-tile inner))
             (None)
             (find (lambda (tile)
                     (match (tile-view (● a accessor) (product (expr-tile inner)) tile)
                       ((Some _) #t)
                       ((None) #f)))
                   (map (lambda (j) (list-drop lead (- (length lead) (+ j 1))))
                        (iota (length lead))))))
        ((None) (None))))

    ;; A producer's body as a load of `tile`s through `v` sees it, with
    ;; the producer's arguments as that load sees them. A body of values,
    ;; with no tile in it, is computed at each element the load reads, so
    ;; it becomes the same operations on tiles, its arguments seen through
    ;; the load's view. A body of tiles is computed once a tile, so the
    ;; view must read whole tiles of the port and, within each, the same
    ;; places, which a pick takes; its arguments are seen through the
    ;; view's steps over the port's leading axes, each keeping its tile.
    (define (as-loaded (v View) (inner Expr) (tile (List I64))) (→ (Option (Pair Expr (List View))))
      (let ((args (● v node args)) (shape (● (port-of (● v node) (● v port)) shape)))
        (if (untiled? inner)
            (match (seen-all args (lambda (a) (seen-through (● a accessor) (● v accessor) shape)))
              ((Some views) (Some (new Pair (first (lifted inner tile)) (second views))))
              ((None) (None)))
            (let ((lead (take shape (- (length shape) (length (expr-tile inner))))))
              (match (tile-view (● v accessor) (product (expr-tile inner)) tile)
                ((Some split)
                 (match (seen-all args
                                  (lambda (a) (seen-leading (● a accessor) (● split first) lead)))
                   ((Some views)
                    (Some (new Pair (first (picked inner (● split second) tile)) (second views))))
                   ((None) (None))))
                ((None) (None)))))))

    ;; Whether no expression of a body is a tile.
    (define (untiled? (e Expr)) (→ Bool)
      (and (null? (expr-tile e))
           (match e
             ((Apply _ operands _ _) (every? untiled? operands))
             (_ #t))))

    ;; A body of values as the same operations on tiles, each load reading
    ;; a tile and each literal standing for every element.
    (define (lifted (e Expr) (tile (List I64))) (→ Expr)
      (match e
        ((Load k etype _) (Load k etype tile))
        ((Literal _ _) e)
        ((Apply op operands etype _)
         (Apply op (map (lambda (o) (lifted o tile)) operands) etype tile))))

    ;; A body of tiles as a load reading `places` of each, as `tile`s.
    (define (picked (e Expr) (places (List I64)) (tile (List I64))) (→ Expr)
      (if (and (same-list? tile (expr-tile e)) (same-list? places (iota (length places))))
          e
          (Apply (Pick places) (list e) (expr-etype e) tile)))

    ;; A view, read as `tile`s, of a port of tiles of `size` elements: its
    ;; steps over the port's leading axes, which must be whole tiles, an
    ;; axis of one element taking no step, and the places in a tile its
    ;; tile reads, which must stay inside one.
    (define (tile-view (a Accessor) (size I64) (tile (List I64)))
      (→ (Option (Pair Accessor (List I64))))
      (let* ((lead (- (length (● a shape)) (length tile)))
             (steps (map (lambda (pair) (if (= (● pair second) 1) 0 (● pair first)))
                         (zip (take (● a pitch) lead) (take (● a shape) lead))))
             (places (map (lambda (t)
                            (+ (remainder (● a offset) size) (dot (list-drop (● a pitch) lead) t)))
                          (tile-indices tile))))
        (if (and (every? (lambda (p) (= (remainder p size) 0)) steps)
                 (every? (lambda (p) (< p size)) places))
            (Some (new Pair
                    (first (new Accessor
                             (offset (quotient (● a offset) size))
                             (shape (take (● a shape) lead))
                             (pitch (map (lambda (p) (quotient p size)) steps))))
                    (second places)))
            (None))))

    ;; An argument a producer of tiles reads through `inner`, at `lead`
    ;; followed by its own tile, seen through `outer`'s steps over `lead`.
    (define (seen-leading (inner Accessor) (outer Accessor) (lead (List I64))) (→ (Option Accessor))
      (let ((r (length lead)))
        (match (seen-through (new Accessor
                               (offset (● inner offset))
                               (shape lead)
                               (pitch (take (● inner pitch) r)))
                             outer
                             lead)
          ((Some s)
           (Some (new Accessor
                   (offset (● s offset))
                   (shape (append (● s shape) (list-drop (● inner shape) r)))
                   (pitch (append (● s pitch) (list-drop (● inner pitch) r))))))
          ((None) (None)))))

    ;; The producer's arguments, each seen as `see` sees it, if each can be.
    (define (seen-all (inner (List View)) (see (Fn View → (Option Accessor))))
      (→ (Option (List View)))
      (fold-right (lambda (a rest)
                    (match rest
                      ((Some views)
                       (match (see a)
                         ((Some accessor) (Some (Cons (View-accessor-set a accessor) views)))
                         ((None) (None))))
                      ((None) (None))))
                  (Some (Nil))
                  inner))

    ;; ---- Sharing ----

    ;; A kernel taking in a producer reads what the producer reads, in
    ;; place of its port, and that may be more: a pick of one element of
    ;; each tile of a product reads every tile the product reads. It is
    ;; worth it where, were every reader to take the producer in, so that
    ;; its own kernel goes, they would read no more than they save: what
    ;; one adds to its reads, times the readers, is at most what the
    ;; producer's kernel reads and writes. A producer a kernel planned
    ;; before keeps is computed anyway, at its first place in the fused
    ;; order, so it is taken in only where that reads less than its port.
    ;;
    ;; Taking in a producer whose readers see each of its elements at most
    ;; once computes nothing twice. One read more is computed in each
    ;; kernel taking it in, and the buffers it reads stay alive until that
    ;; kernel: from the producer's place, where it would read them as a
    ;; kernel of its own, to the reader's. It is taken in only where those
    ;; buffers hold no more bytes for those steps than its own would. A
    ;; buffer the kernel binds already, or that a node there or later
    ;; reads, costs nothing.
    (define (worth-taking? (graph Graph)
                           (kept (Table Bool))
                           (place I64)
                           (producer Node)
                           (args (List View))
                           (taken (List View)))
      (→ Bool)
      (and (reads-no-more? graph kept producer args taken)
           (or (not (shared? graph producer)) (holds-no-more? graph place producer args))))

    (define (reads-no-more? (graph Graph)
                            (kept (Table Bool))
                            (producer Node)
                            (args (List View))
                            (taken (List View)))
      (→ Bool)
      (let ((added (- (reads taken) (reads args))))
        (if (table-contains? kept (● producer key))
            (< added 0)
            (<= (* added (reader-count graph producer))
                (+ (reads (● producer args)) (port-elements producer))))))

    (define (holds-no-more? (graph Graph) (place I64) (producer Node) (args (List View))) (→ Bool)
      (let ((made (place-in (● graph places) producer)))
        (<= (kept-alive graph made place producer args) (* (port-bytes producer) (- place made)))))

    ;; The kernels reading a node, each counted once however many views
    ;; of it it reads.
    (define (reader-count (graph Graph) (n Node)) (→ I64)
      (length (delete-duplicates (lambda (a b) (= a b))
                                 (map (lambda (r) (● r place)) (readers-of (● graph readers) n)))))

    ;; Whether what reads a node sees more elements than it has.
    (define (shared? (graph Graph) (n Node)) (→ Bool)
      (> (fold-left + 0 (map (lambda (r) (● r seen)) (readers-of (● graph readers) n)))
         (port-elements n)))

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
    ;; it alone reads, which are taken in with it. A map others read too
    ;; is a buffer here: whether it is taken in is weighed in its own
    ;; turn, but each kernel reading it keeps what it reads alive.
    (define (buffers-under (graph Graph) (n Node) (found (Table Node))) (→ (Table Node))
      (fold-left (lambda (found a)
                   (let ((m (● a node)))
                     (cond ((or (table-contains? found (● m key)) (not (pooled? m))) found)
                           ((and (map-kind? m) (not (shared? graph m)))
                            (buffers-under graph m found))
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

    (define (port-elements (n Node)) (→ I64)
      (fold-left + 0 (map (lambda (p) (product (● p shape))) (● n ports))))

    (define (port-bytes (n Node)) (→ I64) (* 4 (port-elements n)))

    ;; ---- Reads ----

    ;; The elements a kernel reads of the buffers its arguments view, each
    ;; buffer once, as far as its views of it span: a view stepping a few
    ;; elements at a time touches every line of memory it passes, so a
    ;; pick of one element of each tile reads all of them.
    (define (reads (args (List View))) (→ I64)
      (fold-left + 0 (table-values (fold-left widest (empty-table) args))))

    (define (widest (spans (Table I64)) (a View)) (→ (Table I64))
      (let ((name (port-name a)))
        (table-set spans
                   name
                   (match (table-ref spans name)
                     ((Some s) (max s (span a)))
                     ((None) (span a))))))

    ;; The elements from a view's first to its last, within its port.
    (define (span (v View)) (→ I64)
      (min (product (● (port-of (● v node) (● v port)) shape))
           (fold-left + 1
                      (map (lambda (pair) (* (abs (● pair first)) (max 0 (- (● pair second) 1))))
                           (zip (● v accessor pitch) (● v accessor shape))))))

    ;; ---- Limits ----

    ;; Bodies of at most 256 distinct expressions in all, an expression
    ;; inlined twice counted once, since lowering names each once: so the
    ;; text a kernel holds is bounded, as Resin bounds a fused tree, and a
    ;; producer read by several of a body's expressions, as the harmonics'
    ;; basis by each degree's product, is still taken in. And at most the
    ;; eight storage buffers every device lets a kernel bind, its ports
    ;; among them (`bindings`).

    (define (within-limits? (graph Graph) (place I64) (f Fusing)) (→ Bool)
      (and (<= (distinct-size (● f bodies)) 256) (<= (bindings graph place f) 8)))

    ;; The buffers a kernel binds: one a port, and one for each buffer its
    ;; arguments see, but for a param a port writes in place, which is
    ;; that port's. Lowering writes an update's port into its param in
    ;; place where the param is read only by that kernel, as it reads it
    ;; here, at the elements each thread writes (lower.sld, "In place");
    ;; counting on that only for a param nothing else reads, such as
    ;; Adam's moments, keeps the count no lower than lowering's.
    (define (bindings (graph Graph) (place I64) (f Fusing)) (→ I64)
      (let ((owners (Cons (● f node) (● f written))))
        (+ (length owners)
           (buffer-count
            (filter (lambda (a) (not (written-in-place? graph place f owners a))) (● f args))))))

    ;; Whether argument `a` is a param one of the kernel's ports writes in
    ;; place: the target of an update whose value is that port, seen whole
    ;; in the port's shape, and read only by the kernel.
    (define (written-in-place? (graph Graph) (place I64) (f Fusing) (owners (List Node)) (a View))
      (→ Bool)
      (and (whole-buffer? a)
           (any? (lambda (owner)
                   (match (table-ref (● graph targets) (● owner key))
                     ((Some param)
                      (and (string=? (● param key) (● a node key))
                           (equal-lists? (shape-of a) (● (port-of owner default-port) shape))
                           (read-only-by? graph place f param)))
                     ((None) #f)))
                 owners)))


    ;; The expressions of the bodies, each counted once however often it
    ;; occurs, as lowering names each distinct value once.
    (define (distinct-size (bodies (List Expr))) (→ I64)
      (● (fold-left (lambda (names body) (● (expression-name body names) first))
                    (new Names (numbers (empty-table)) (count 0))
                    bodies)
         count))

    ;; The distinct expressions met so far, each numbered by its text.
    (record Names
      ((numbers (Table I64))
       (count I64)))

    ;; An expression's name among `names`, which knows each distinct
    ;; expression by its operation and its operands' names: a new number
    ;; the first time, so a name stays short however deep the expression.
    (define (expression-name (e Expr) (names Names)) (→ (Pair Names String))
      (match e
        ((Apply op operands _ tile)
         (let ((inner (fold-left (lambda (state o)
                                   (let ((next (expression-name o (● state first))))
                                     (new Pair
                                       (first (● next first))
                                       (second (Cons (● next second) (● state second))))))
                                 (new Pair (first names) (second (Nil)))
                                 operands)))
           (named-once (● inner first)
                       (string-append (op-text op)
                                      " "
                                      (string-join (reverse (● inner second)) " ")
                                      ":"
                                      (string-join (map show tile) "x")))))
        ((Load k _ tile)
         (named-once names (string-append "$" (show k) ":" (string-join (map show tile) "x"))))
        ((Literal value etype)
         (named-once names (string-append (f64->string value) (etype-wgsl etype))))))

    (define (named-once (names Names) (text String)) (→ (Pair Names String))
      (match (table-ref (● names numbers) text)
        ((Some number) (new Pair (first names) (second (string-append "#" (show number)))))
        ((None)
         (new Pair
           (first (new Names
                    (numbers (table-set (● names numbers) text (● names count)))
                    (count (+ (● names count) 1))))
           (second (string-append "#" (show (● names count))))))))

    (define (buffer-count (args (List View))) (→ I64)
      (length
       (table-keys (fold-left (lambda (t a) (table-set t (port-name a) #t)) (empty-table) args))))

    (define (port-name (view View)) (→ String)
      (string-append (● view node key) "." (● view port)))

    ;; ---- Loads in order ----

    ;; Bodies and their arguments with each view loaded once: equal views
    ;; are one argument, numbered in the order the bodies first load them,
    ;; depth first, as Resin numbers a fused tree's free loads.
    (define (distinct (bodies (List Expr)) (args (List View))) (→ (Pair (List Expr) (List View)))
      (let* ((order (fold-left (lambda (seen body) (first-loads body args seen)) (Nil) bodies))
             (index
              (fold-left (lambda (t pair) (table-set t (view-key (● pair second)) (● pair first)))
                         (empty-table)
                         (zip (iota (length order)) order))))
        (new Pair
          (first (map (lambda (body)
                        (map-loads body
                                   (lambda (k etype tile)
                                     (match (table-ref index (view-key (list-ref args k)))
                                       ((Some j) (Load j etype tile))
                                       ((None) (panic "fuse: a load of no argument"))))))
                      bodies))
          (second order))))

    ;; The views a body loads, each once, in the order it first loads them.
    (define (first-loads (e Expr) (args (List View)) (seen (List View))) (→ (List View))
      (match e
        ((Load k _ _)
         (let ((v (list-ref args k)))
           (if (any? (lambda (s) (string=? (view-key s) (view-key v))) seen)
               seen
               (append seen (list v)))))
        ((Literal _ _) seen)
        ((Apply _ operands _ _)
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
