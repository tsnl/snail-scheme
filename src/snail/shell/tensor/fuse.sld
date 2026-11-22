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
;; to the port's axes (`seen-through`). A map of tiles, as a small matrix
;; product is, computes a tile once, so the view must read whole tiles of
;; it, and a map of values reading one so becomes a map of those tiles to
;; take it in (`at-tiles`). Bodies stay within 256 expressions, and a
;; kernel within the eight storage buffers every device allows. A
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

    ;; A map or a reduction being fused: the axes its body is computed at,
    ;; a map's port's leading axes or a reduction's port's and its span's;
    ;; the body; and the arguments it loads.
    (record Fusing
      ((node Node)
       (lead (List I64))
       (body Expr)
       (args (List View))))

    ;; What fusing decided, from the roots down: the nodes still read, by
    ;; key, and what each such map or reduction took in.
    (record Plan
      ((read (Table Bool))
       (bodies (Table Fusing))))

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
             (let ((taken (absorbed graph
                                    (● plan read)
                                    (place-in (● graph places) n)
                                    (new Fusing
                                      (node n)
                                      (lead (lead-of n))
                                      (body body)
                                      (args (● n args))))))
               (new Plan
                 (read (marked (● plan read) (● taken args)))
                 (bodies (table-set (● plan bodies) (● n key) taken)))))
            ((None) (Plan-read-set plan (marked (● plan read) (● n args)))))
          plan))

    (define (body-of (n Node)) (→ (Option Expr))
      (match (● n kind)
        ((Map body) (Some body))
        ((Reduce _ _ body) (Some body))
        (_ (None))))

    ;; The axes a body is computed at: a map's port's leading axes, before
    ;; its body's tile; a reduction's port's axes and its span's.
    (define (lead-of (n Node)) (→ (List I64))
      (let ((shape (● (port-of n default-port) shape)))
        (match (● n kind)
          ((Map body) (take shape (- (length shape) (length (expr-tile body)))))
          ((Reduce _ span _) (append shape span))
          (_ shape))))

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
                                 (● taken body)
                                 (map (lambda (a) (rewritten done a)) (● taken args))))
                       ((None) (with-args n (map (lambda (a) (rewritten done a)) (● n args))))))
          done))

    ;; A map or a reduction as `n` is, over `body` and `args`: a map at
    ;; its port's axes before the body's tile, which may now be larger.
    (define (rebuilt (n Node) (body Expr) (args (List View))) (→ Node)
      (let ((shape (● (port-of n default-port) shape)))
        (● (match (● n kind)
             ((Map _) (mapped body args (take shape (- (length shape) (length (expr-tile body))))))
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

    ;; A body, of the kernel at `place`, with each producer it can take
    ;; in taken in, until none can be; `kept` holds the nodes the kernels
    ;; planned before it read.
    (define (absorbed (graph Graph) (kept (Table Bool)) (place I64) (f Fusing)) (→ Fusing)
      (match (first-taken graph kept place f 0)
        ((Some next) (absorbed graph kept place next))
        ((None) f)))

    ;; The body with the first producer from argument k on that fits and
    ;; is worth taking in taken in.
    (define (first-taken (graph Graph) (kept (Table Bool)) (place I64) (f Fusing) (k I64))
      (→ (Option Fusing))
      (if (>= k (length (● f args)))
          (None)
          (match (taking-in f k)
            ((Some next)
             (if (worth-taking? graph
                                kept
                                place
                                (● (list-ref (● f args) k) node)
                                (● f args)
                                (● next args))
                 (Some next)
                 (first-taken graph kept place f (+ k 1))))
            ((None) (first-taken graph kept place f (+ k 1))))))

    ;; The body with argument k's producer inlined, each load of it a tile
    ;; of the axes after the body's: computed a tile at a time first, when
    ;; it reads a map of tiles a whole tile at a time (`at-tiles`).
    (define (taking-in (f Fusing) (k I64)) (→ (Option Fusing))
      (let* ((at (at-tiles f (list-ref (● f args) k)))
             (tile (list-drop (shape-of (list-ref (● f args) k)) (length (● at lead)))))
        (match (inlined (● at body) (● f args) k tile)
          ((Some next) (Some (Fusing-args-set (Fusing-body-set at (● next first)) (● next second))))
          ((None) (None)))))

    ;; The body and arguments with argument k's producer inlined, when it
    ;; is a map whose loads can be seen through the view of it, which is
    ;; loaded as `tile`s, and the result keeps within the limits. Argument
    ;; k's loads become the producer's body, whose loads read the
    ;; producer's arguments as the view sees them, after the others.
    (define (inlined (body Expr) (args (List View)) (k I64) (tile (List I64)))
      (→ (Option (Pair Expr (List View))))
      (let ((v (list-ref args k)))
        (match (● v node kind)
          ((Map inner)
           (match (as-loaded v inner tile)
             ((Some through)
              (let* ((base (- (length args) 1))
                     (moved (map-loads (● through first)
                                       (lambda (j etype tile) (Load (+ base j) etype tile))))
                     (combined
                      (distinct (map-loads body
                                           (lambda (j etype tile)
                                             (cond ((= j k) moved)
                                                   ((> j k) (Load (- j 1) etype tile))
                                                   (else (Load j etype tile)))))
                                (append (append (take args k) (list-drop args (+ k 1)))
                                        (● through second)))))
                (if (within-limits? combined) (Some combined) (None))))
             ((None) (None))))
          (_ (None)))))

    ;; ---- Tiles ----

    ;; A map of values that reads a map of tiles a whole tile at a time,
    ;; over its port's last axes, computed a tile of those axes at a time,
    ;; so that it can take that map in; any other body as it is.
    (define (at-tiles (f Fusing) (a View)) (→ Fusing)
      (match (if (and (map-kind? (● f node)) (untiled? (● f body)))
                 (tile-reading (● f lead) a)
                 (None))
        ((Some tile)
         (Fusing-body-set
          (Fusing-lead-set f (take (● f lead) (- (length (● f lead)) (length tile))))
          (lifted (● f body) tile)))
        ((None) f)))

    ;; The fewest of `lead`'s last axes at which a view of a map of tiles
    ;; reads whole tiles of it.
    (define (tile-reading (lead (List I64)) (a View)) (→ (Option (List I64)))
      (match (● a node kind)
        ((Map inner)
         (if (null? (expr-tile inner))
             (None)
             (find (lambda (tile)
                     (match (tile-view (● a accessor) (product (expr-tile inner)) tile)
                       ((Some _) #t)
                       ((None) #f)))
                   (map (lambda (j) (list-drop lead (- (length lead) (+ j 1))))
                        (iota (length lead))))))
        (_ (None))))

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

    ;; A body of at most 256 expressions, as Resin bounds a fused tree,
    ;; since a producer read twice is inlined twice; and arguments in at
    ;; most seven buffers, for the eight storage buffers every device
    ;; lets a kernel bind, its port being the eighth.

    (define (within-limits? (fused (Pair Expr (List View)))) (→ Bool)
      (and (<= (expr-size (● fused first)) 256) (<= (buffer-count (● fused second)) 7)))

    (define (expr-size (e Expr)) (→ I64)
      (match e
        ((Apply _ operands _ _) (+ 1 (fold-left + 0 (map expr-size operands))))
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
                            (lambda (k etype tile)
                              (match (table-ref index (view-key (list-ref args k)))
                                ((Some j) (Load j etype tile))
                                ((None) (panic "fuse: a load of no argument"))))))
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
