;; Lowering a tensor graph to plain WebGPU objects, explicitly and once:
;; a buffer for each port the program needs, a compute pipeline and bind
;; group for each dispatch, and the order to run them in. Everything it
;; makes is the caller's: a `Program` lists its steps, each with its WGSL
;; text, pipeline, bind group and workgroups, and every buffer it made, by
;; use and size. The caller encodes the steps into a compute pass of its
;; own, or lets `run-program` do that in a pass by itself, as often as it
;; likes, with nothing built again; and releases the program when done.
;;
;;   (let ((program (lower gpu "fit" (list loss) (list (new Pair (first w) (second w')))))) ...)
;;   (write-param gpu program "x" bytes)   ; a param's elements, 32-bit words
;;   (run-program gpu program)             ; every sink computed, then w := w'
;;   (read-sink gpu program 0)             ; the loss's bytes
;;
;; A program has sinks, views it computes for reading back, and updates,
;; pairs of a param and the value it takes once everything else ran, so a
;; step of training reads the params it started with and leaves the next.
;;
;; Each node is a kernel generated for it, whose shapes, pitches and
;; offsets are literals, so two nodes computing alike share a pipeline. A
;; `Fill` argument of a generated kernel is a literal too and has no
;; buffer. A port's buffer returns to a pool once the last node reading it
;; ran, for a later port of its size; params, constants, sinks and updates
;; keep theirs. Sorts and scans run on (snail shell graphics radix-sort)
;; and (snail shell graphics scan), and a custom node's kernels run as
;; written, on zeroed ports.
;;
;; A caller may give buffers of its own (`lower-with`): a param's, which
;; the program reads and writes in place of making one, and scratch to
;; start the pool with. Programs that take turns on one set of params, as
;; a training step and densification do, are lowered with what the first
;; one has (`given-by`). A host grows a program through a stash of its
;; params, and `profile-program` times each step alone.
(define-library (snail shell tensor lower)
  (export
   Program
   Step
   Dispatch
   Sorting
   Scanning
   Binding
   Sink
   Made
   Given
   lower
   lower-with
   nothing-given
   given-by
   bound
   encode-steps
   run-program
   write-param
   read-param
   read-sink
   param-buffer
   sink-buffer
   Stash
   stash-params
   unstash-params
   profile-program
   program-memory
   release-program)
  (import
   (snail core base)
   (snail core table)
   (only (snail shell gpu)
         Gpu
         submit-timed
         elapsed-seconds
         GpuBuffer
         GpuShaderModule
         GpuComputePipeline
         GpuBindGroup
         GpuComputePass
         GpuCommandEncoder
         GpuQuerySet
         GpuObject
         BufferObject
         ModuleObject
         ComputePipelineObject
         BindGroupObject
         QuerySetObject
         ComputePipeline
         BufferDescriptor
         QuerySetDescriptor
         TimestampWrites
         MapRead
         CopySrc
         CopyDst
         Storage
         ShaderModuleDescriptor
         ComputePipelineDescriptor
         BufferEntry
         BindGroupDescriptor)
   (snail shell graphics scan)
   (snail shell graphics radix-sort)
   (snail shell tensor))
  (begin

    ;; ---- Programs ----

    ;; One thing a program does in its pass: a dispatch of a pipeline over
    ;; a bind group, in rows of workgroups, or a sort or a scan in place. A
    ;; dispatch keeps its kernel's code and entry, which name it in a
    ;; profile.
    (enum Step
      (Dispatch ((pipeline GpuComputePipeline)
                 (group GpuBindGroup)
                 (x I64)
                 (y I64)
                 (code String)
                 (entry String)))
      (Sorting ((sorter Sorter)))
      (Scanning ((scan Scan))))

    ;; A param: its buffer and what it holds.
    (record Binding
      ((buffer GpuBuffer)
       (port Port)))

    ;; A sink: its dense buffer, and one the host can map to read it.
    (record Sink
      ((buffer GpuBuffer)
       (readback GpuBuffer)
       (size I64)))

    ;; A buffer the program made, and so releases: what it is for, "param",
    ;; "constant", "scratch", "sink" or "readback", and its size in bytes.
    (record Made
      ((use String)
       (size I64)
       (buffer GpuBuffer)))

    ;; What a caller gives a program: buffers for params by name, which the
    ;; caller keeps, and free scratch buffers by size in bytes, which hold
    ;; nothing between runs.
    (record Given
      ((params (Table Binding))
       (scratch (Table (List GpuBuffer)))))

    ;; A program's steps, params and sinks; its scratch, the pool's free
    ;; buffers by size once it is lowered; every buffer it made; and every
    ;; object it made, to release.
    (record Program
      ((steps (List Step))
       (params (Table Binding))
       (sinks (List Sink))
       (scratch (Table (List GpuBuffer)))
       (made (List Made))
       (objects (List GpuObject))))

    ;; What lowering has made so far: every port's buffer by node key and
    ;; port, the pool of free buffers by size in bytes, pipelines by their
    ;; code and entry, the steps in reverse, the params, those given, and
    ;; everything to release; whether the pool began with given scratch;
    ;; and the ports that write an update into its param's buffer, with
    ;; the param (In place).
    (record Build
      ((label String)
       (buffers (Table GpuBuffer))
       (pool (Table (List GpuBuffer)))
       (pipelines (Table GpuComputePipeline))
       (steps (List Step))
       (params (Table Binding))
       (given (Table Binding))
       (objects (List GpuObject))
       (made (List Made))
       (borrowing Bool)
       (in-place (Table View))))

    ;; ---- Lowering ----

    (define (lower (gpu Gpu) (label String) (sinks (List View)) (updates (List (Pair View View))))
      (→ Program)
      (lower-with gpu label sinks updates nothing-given))

    (define nothing-given (→ Given) (new Given (params (empty-table)) (scratch (empty-table))))

    ;; What `program` has for another program that takes turns with it: its
    ;; params, and its scratch, which holds nothing between runs. `program`
    ;; keeps them, so the other releases none of them and is released no
    ;; later than `program`; the other's sinks are copied out of the scratch,
    ;; since `program`'s runs reuse it.
    (define (given-by (program Program)) (→ Given)
      (new Given (params (● program params)) (scratch (● program scratch))))

    ;; `given` with the caller's `buffer` for the param that `view` sees
    ;; whole: a program lowered with it reads and writes that buffer.
    (define (bound (given Given) (view View) (buffer GpuBuffer)) (→ Given)
      (match (● view node kind)
        ((Param name)
         (unless (identity? view)
           (panic (string-append "tensor lower: bound must see the whole param " name)))
         (Given-params-set given
                           (table-set (● given params)
                                      name
                                      (new Binding
                                        (buffer buffer)
                                        (port (port-of (● view node) (● view port)))))))
        (_ (panic "tensor lower: only a param can be bound to a buffer"))))

    ;; Every node the sinks and updates need, in order, each one's ports
    ;; given buffers and its kernels dispatched; then each sink made dense
    ;; and each update not written in place copied to its param. An
    ;; update's param is a root too, so one only written, never read, still
    ;; has its buffer. A param `given` has is read and written in the
    ;; caller's buffer, which must be its size, and the pool starts with the
    ;; scratch it has.
    (define (lower-with (gpu Gpu) (label String)
                        (sinks (List View))
                        (updates (List (Pair View View)))
                        (given Given))
      (→ Program)
      (let* ((targets (map (lambda (u) (● u first)) updates))
             (written (pinned-keys targets))
             (assignments (map (lambda (u) (prepare-update u written)) updates))
             (roots (append targets (append sinks (map (lambda (u) (● u second)) assignments))))
             (order (toposort roots))
             (last (last-uses order))
             (pinned (pinned-keys roots))
             (in-place (in-place-ports assignments sinks order last))
             (built
              (fold-left
               (lambda (b pair) (node-built gpu b (● pair second) (● pair first) last pinned))
               (new Build
                 (label label)
                 (buffers (empty-table))
                 (pool (● given scratch))
                 (pipelines (empty-table))
                 (steps (Nil))
                 (params (empty-table))
                 (given (● given params))
                 (objects (Nil))
                 (made (Nil))
                 (borrowing (not (null? (table-keys (● given scratch)))))
                 (in-place in-place))
               (zip (iota (length order)) order)))
             (sunk (fold-left (lambda (state view) (sink-built gpu state view))
                              (new Pair (first built) (second (Nil)))
                              sinks))
             (done
              (fold-left (lambda (b u)
                           (if (written-in-place? in-place u)
                               b
                               (copied-into gpu b (● u second) (view-buffer b (● u first)))))
                         (● sunk first)
                         assignments)))
        (new Program
          (steps (reverse (● done steps)))
          (params (● done params))
          (sinks (reverse (● sunk second)))
          (scratch (● done pool))
          (made (● done made))
          (objects (● done objects)))))

    (define (port-key (n Node) (port String)) (→ String) (string-append (● n key) "." port))

    (define (fill? (view View)) (→ Bool)
      (match (● view node kind)
        ((Fill _) #t)
        (_ #f)))

    ;; The arguments of a node that are buffers: every kernel generated
    ;; here reads a `Fill` as a literal, and only a custom one cannot.
    (define (buffer-args (n Node)) (→ (List View))
      (match (● n kind)
        ((CustomKind _) (● n args))
        (_ (filter (lambda (a) (not (fill? a))) (● n args)))))

    ;; The step after which no node reads each node's ports.
    (define (last-uses (order (List Node))) (→ (Table I64))
      (fold-left (lambda (last pair)
                   (fold-left (lambda (last a) (table-set last (● a node key) (● pair first)))
                              last
                              (buffer-args (● pair second))))
                 (empty-table)
                 (zip (iota (length order)) order)))

    (define (pinned-keys (roots (List View))) (→ (Table Bool))
      (fold-left (lambda (pinned r) (table-set pinned (● r node key) #t)) (empty-table) roots))

    ;; A node's ports given buffers and its steps added, then the buffers
    ;; of arguments read for the last time back in the pool.
    (define (node-built (gpu Gpu)
                        (b Build)
                        (n Node)
                        (t I64)
                        (last (Table I64))
                        (pinned (Table Bool)))
      (→ Build)
      ;; Only a custom kernel reads a Fill through a buffer. Sinks and
      ;; assignments, like generated kernels, can copy its literal directly.
      (if (match (● n kind)
            ((Fill _) (not (table-contains? last (● n key))))
            (_ #f))
          b
          (let ((ready (fold-left (lambda (b port) (port-given gpu b n port)) b (● n ports))))
            (fold-left (lambda (b a)
                         (if (and (= (table-ref-or last (● a node key) -1) t)
                                  (not (table-contains? pinned (● a node key)))
                                  (pooled? (● a node kind)))
                             (released-node b (● a node))
                             b))
                       (node-steps gpu ready (reading-own-port ready n))
                       (unique-nodes (buffer-args n))))))

    ;; The values `f` answers for the items it answers one for.
    (define (filter-map (f (Fn T → (Option U))) (items (List T))) (→ (List U)) (∀ (T U))
      (fold-right (lambda (item rest)
                    (match (f item)
                      ((Some value) (Cons value rest))
                      ((None) rest)))
                  (Nil)
                  items))

    (define (table-ref-or (table (Table I64)) (key String) (default I64)) (→ I64)
      (match (table-ref table key)
        ((Some value) value)
        ((None) default)))

    (define (pooled? (kind Kind)) (→ Bool)
      (match kind
        ((Param _) #f)
        ((Constant _ _) #f)
        (_ #t)))

    (define (unique-nodes (views (List View))) (→ (List View))
      (● (fold-left (lambda (seen v)
                      (if (table-contains? (● seen second) (● v node key))
                          seen
                          (new Pair
                            (first (Cons v (● seen first)))
                            (second (table-set (● seen second) (● v node key) #t)))))
                    (new Pair (first (Nil)) (second (empty-table)))
                    views)
         first))

    ;; ---- Buffers ----

    (define (bytes-of (port Port)) (→ I64) (max 4 (* 4 (product (● port shape)))))

    (define (new-buffer (gpu Gpu) (label String) (size I64)) (→ GpuBuffer)
      ((● gpu create-buffer) (new BufferDescriptor
                               (label label)
                               (size (i64->i32 size))
                               (usage (list (Storage) (CopySrc) (CopyDst))))))

    ;; A buffer of `size` bytes: a free one from the pool, or a new one.
    (define (taken (gpu Gpu) (b Build) (label String) (size I64)) (→ (Pair Build GpuBuffer))
      (match (table-ref (● b pool) (show size))
        ((Some (Cons buffer rest))
         (new Pair
           (first (Build-pool-set b (table-set (● b pool) (show size) rest)))
           (second buffer)))
        (_
         (let ((buffer (new-buffer gpu (string-append (● b label) "/" label) size)))
           (new Pair (first (made-buffer b "scratch" buffer size)) (second buffer))))))

    (define (owned (b Build) (object GpuObject)) (→ Build)
      (Build-objects-set b (Cons object (● b objects))))

    ;; A buffer the program made, and so releases, noted with its use and
    ;; size.
    (define (made-buffer (b Build) (use String) (buffer GpuBuffer) (size I64)) (→ Build)
      (Build-made-set (owned b (BufferObject buffer))
                      (Cons (new Made (use use) (size size) (buffer buffer)) (● b made))))

    (define (given-back (b Build) (size I64) (buffer GpuBuffer)) (→ Build)
      (let ((free (match (table-ref (● b pool) (show size))
                    ((Some free) free)
                    ((None) (Nil)))))
        (Build-pool-set b (table-set (● b pool) (show size) (Cons buffer free)))))

    (define (released-node (b Build) (n Node)) (→ Build)
      (fold-left (lambda (b port) (given-back b (bytes-of port) (buffer-of b n (● port name))))
                 b
                 (● n ports)))

    ;; A port's buffer: a param's its own, by name; a constant's written
    ;; with its data; one writing an update in place its param's; any
    ;; other from the pool.
    (define (port-given (gpu Gpu) (b Build) (n Node) (port Port)) (→ Build)
      (let ((key (port-key n (● port name))))
        (match (● n kind)
          ((Param name)
           (let ((made (param-buffer-for gpu b name port)))
             (Build-params-set (buffer-set (● made first) key (● made second))
                               (table-set (● b params)
                                          name
                                          (new Binding (buffer (● made second)) (port port))))))
          ((Constant name data)
           (let ((buffer (new-buffer gpu (string-append (● b label) "/" name) (bytes-of port))))
             ((● gpu write-buffer) buffer 0 data)
             (buffer-set (made-buffer b "constant" buffer (bytes-of port)) key buffer)))
          (_
           (match (table-ref (● b in-place) key)
             ((Some target) (buffer-set b key (view-buffer b target)))
             ((None)
              (let ((pair (taken gpu b key (bytes-of port))))
                (buffer-set (● pair first) key (● pair second)))))))))

    ;; A param's buffer: the given one of its name and size, or its own.
    (define (param-buffer-for (gpu Gpu) (b Build) (name String) (port Port))
      (→ (Pair Build GpuBuffer))
      (match (table-ref (● b given) name)
        ((Some binding)
         (if (= (bytes-of (● binding port)) (bytes-of port))
             (new Pair (first b) (second (● binding buffer)))
             (panic (string-append "tensor lower: given param " name " has another size"))))
        ((None)
         (let ((buffer (new-buffer gpu (string-append (● b label) "/" name) (bytes-of port))))
           (new Pair (first (made-buffer b "param" buffer (bytes-of port))) (second buffer))))))

    (define (buffer-set (b Build) (key String) (buffer GpuBuffer)) (→ Build)
      (Build-buffers-set b (table-set (● b buffers) key buffer)))

    (define (buffer-of (b Build) (n Node) (port String)) (→ GpuBuffer)
      (match (table-ref (● b buffers) (port-key n port))
        ((Some buffer) buffer)
        ((None)
         (panic (string-append "tensor lower: "
                               (● b label)
                               " reads port "
                               (port-key n port)
                               " before it has a buffer")))))

    (define (view-buffer (b Build) (view View)) (→ GpuBuffer)
      (buffer-of b (● view node) (● view port)))

    ;; ---- Dispatches ----

    ;; A dispatch of `entry` in `code` over `entries`, bindings and their
    ;; buffers, in rows of at most 65535 workgroups. Pipelines are shared
    ;; by their code.

    (define (dispatched (gpu Gpu) (b Build)
                        (code String)
                        (entry String)
                        (entries (List (Pair I64 GpuBuffer)))
                        (workgroups I64))
      (→ Build)
      (if (= workgroups 0)
          b
          (let* ((with (pipeline-for gpu b code entry))
                 (pipeline (● with second))
                 (group ((● gpu create-bind-group)
                         (new BindGroupDescriptor
                           (label (string-append (● b label) "/" entry))
                           (pipeline (ComputePipeline pipeline))
                           (group 0)
                           (entries
                            (map (lambda (e)
                                   (BufferEntry (i64->i32 (● e first))
                                                (● e second)
                                                0
                                                0))
                                 entries)))))
                 (x (min workgroups 65535)))
            (Build-steps-set (owned (● with first) (BindGroupObject group))
                             (Cons (Dispatch pipeline
                                             group
                                             x
                                             (quotient (+ workgroups (- x 1)) x)
                                             code
                                             entry)
                                   (● with first steps))))))

    (define (pipeline-for (gpu Gpu) (b Build) (code String) (entry String))
      (→ (Pair Build GpuComputePipeline))
      (let ((key (string-append entry "#" code)))
        (match (table-ref (● b pipelines) key)
          ((Some pipeline) (new Pair (first b) (second pipeline)))
          ((None)
           (let* ((module ((● gpu create-shader-module)
                           (new ShaderModuleDescriptor
                             (label (● b label))
                             (code code))))
                  (pipeline ((● gpu create-compute-pipeline)
                             (new ComputePipelineDescriptor
                               (label (● b label))
                               (module module)
                               (entry entry)))))
             (new Pair
               (first (Build-pipelines-set
                       (owned (owned b (ModuleObject module)) (ComputePipelineObject pipeline))
                       (table-set (● b pipelines) key pipeline)))
               (second pipeline)))))))

    (define (step-added (b Build) (step Step)) (→ Build)
      (Build-steps-set b (Cons step (● b steps))))

    ;; A generated kernel's dispatch: its buffer arguments at their
    ;; bindings, its ports after them.
    (define (generated (gpu Gpu) (b Build) (n Node) (code String) (workgroups I64)) (→ Build)
      (dispatched gpu b code "main" (kernel-entries b n) workgroups))

    (define (kernel-entries (b Build) (n Node)) (→ (List (Pair I64 GpuBuffer)))
      (append (arg-entries b n)
              (map-indexed (lambda (j port)
                             (new Pair
                               (first (+ (first-port-binding n) j))
                               (second (buffer-of b n (● port name)))))
                           (● n ports))))

    (define (arg-entries (b Build) (n Node)) (→ (List (Pair I64 GpuBuffer)))
      (map
       (lambda (pair) (new Pair (first (● pair first)) (second (view-buffer b (● pair second)))))
       (bound-args n)))

    ;; ---- Bindings ----

    ;; The buffers a generated kernel binds, each at its binding. The
    ;; arguments of a node with a body, a map or a reduction, share one
    ;; where they see one port, so a fused body binds each buffer once; any
    ;; other kernel binds each argument that is not a fill at its place
    ;; among the arguments. The node's ports follow.

    (define (bound-args (n Node)) (→ (List (Pair I64 View)))
      (if (bodied? n)
          (let ((ports (map-ports n))) (zip (iota (length ports)) ports))
          (filter (lambda (pair) (not (fill? (● pair second))))
                  (zip (iota (length (● n args))) (● n args)))))

    (define (first-port-binding (n Node)) (→ I64)
      (if (bodied? n) (length (map-ports n)) (length (● n args))))

    (define (arg-binding (n Node) (k I64)) (→ I64)
      (if (bodied? n)
          (let ((name (view-port-key (list-ref (● n args) k))))
            (match (list-index (lambda (v) (string=? (view-port-key v) name)) (map-ports n))
              ((Some j) j)
              ((None) (panic "tensor lower: a body's argument has no binding"))))
          k))

    (define (bodied? (n Node)) (→ Bool)
      (match (● n kind)
        ((Map _) #t)
        ((Reduce _ _ _) #t)
        (_ #f)))

    ;; One view of each port a body's arguments see, in the order they
    ;; first see them, but of the node's own, which it binds as a port.
    (define (map-ports (n Node)) (→ (List View))
      (reverse (fold-left (lambda (seen a)
                            (if (or (own-port? n a)
                                    (any?
                                     (lambda (s) (string=? (view-port-key s) (view-port-key a)))
                                     seen))
                                seen
                                (Cons a seen)))
                          (Nil)
                          (● n args))))

    (define (view-port-key (view View)) (→ String) (port-key (● view node) (● view port)))

    ;; Every word of a buffer set to zero.
    (define (zeroed (gpu Gpu) (b Build) (buffer GpuBuffer) (size I64)) (→ Build)
      (dispatched gpu b
                  zero-code
                  "main"
                  (list (new Pair (first 0) (second buffer)))
                  (tiles (quotient size 4) 256)))

    ;; ---- Nodes ----

    ;; Each kind's dispatches, its ports already given buffers.

    (define (node-steps (gpu Gpu) (b Build) (n Node)) (→ Build)
      (let ((out (lambda () (port-of n default-port))) (arg (lambda (k) (list-ref (● n args) k))))
        (match (● n kind)
          ((Param _) b)
          ((Constant _ _) b)
          ((Reduce op span _) (reduce-steps gpu b n op span))
          ((Place accessor)
           (generated gpu (zeroed gpu b (buffer-of b n default-port) (bytes-of (out)))
                      n
                      (place-code n accessor)
                      (tiles (element-count (arg 0)) 256)))
          ((ScatterAdd _)
           (generated gpu (zeroed gpu b (buffer-of b n default-port) (bytes-of (out)))
                      n
                      (scatter-code n)
                      (tiles (element-count (arg 0)) 256)))
          ((Sort bits) (sort-steps gpu b n bits))
          ((PrefixSum) (scan-steps gpu b n))
          ((CustomKind c) (custom-steps gpu b n c))
          (_ (generated gpu b n (thread-code n) (tiles (threads n) 256))))))

    ;; The threads a node's own kernel runs: one an element of its port,
    ;; but a map's one an element of its leading axes, each computing a
    ;; tile of each port.
    (define (threads (n Node)) (→ I64)
      (let ((shape (● (port-of n default-port) shape)))
        (match (● n kind)
          ((Map bodies)
           (product (take shape (- (length shape) (length (expr-tile (list-ref bodies 0)))))))
          (_ (product shape)))))

    ;; The keys and values sorted into the ports: all of them, or as many
    ;; as the node's count, its third argument, says. The sort's first pass
    ;; reads them where they are, so it copies nothing, unless one is a
    ;; fill or part of a buffer: then both are copied into scratch the pool
    ;; lends for the sort.
    (define (sort-steps (gpu Gpu) (b Build) (n Node) (bits I64)) (→ Build)
      (let* ((keys (list-ref (● n args) 0))
             (values (list-ref (● n args) 1))
             (lent (or (lent? keys) (lent? values)))
             (from (if lent
                       (lent-lane gpu b keys values)
                       (new Pair (first b) (second (read-lane b keys values)))))
             (counted (match (list-tail (● n args) 2)
                        ((Cons count _) (Some (count-buffer b count)))
                        ((Nil) (None))))
             (sorter (make-sorter gpu (string-append (● b label) "/sort")
                                  (● from second)
                                  (new SortLane
                                    (keys (buffer-of b n "keys"))
                                    (values (buffer-of b n "values")))
                                  (element-count keys)
                                  bits
                                  counted))
             (sorted (step-added (● from first) (Sorting sorter))))
        (if lent (lane-returned sorted (● from second) keys values) sorted)))

    ;; Whether a sort reads a view from a copy: a fill has no buffer, and a
    ;; sort reads every element of a buffer from its start.
    (define (lent? (view View)) (→ Bool)
      (or (fill? view) (not (whole-buffer? view))))

    (define (read-lane (b Build) (keys View) (values View)) (→ SortLane)
      (new SortLane (keys (view-buffer b keys)) (values (view-buffer b values))))

    ;; Keys and values copied into two buffers the pool lends.
    (define (lent-lane (gpu Gpu) (b Build) (keys View) (values View)) (→ (Pair Build SortLane))
      (let* ((k (taken gpu b "sort/keys" (* 4 (element-count keys))))
             (v (taken gpu (● k first) "sort/values" (* 4 (element-count values)))))
        (new Pair
          (first
           (copied-into gpu (copied-into gpu (● v first) keys (● k second)) values (● v second)))
          (second (new SortLane (keys (● k second)) (values (● v second)))))))

    ;; The lent buffers back in the pool once the sort's steps are added:
    ;; a later node's steps that write them run after it.
    (define (lane-returned (b Build) (lane SortLane) (keys View) (values View)) (→ Build)
      (given-back (given-back b (* 4 (element-count keys)) (● lane keys))
                  (* 4 (element-count values))
                  (● lane values)))

    ;; A count's buffer: a port of one u32, which the sort reads at its
    ;; start.
    (define (count-buffer (b Build) (count View)) (→ GpuBuffer)
      (if (and (not (fill? count))
               (whole-buffer? count)
               (= (element-count count) 1)
               (same-etype? (etype-of count) (Unsigned)))
          (view-buffer b count)
          (panic "tensor lower: a count is a port of one u32, seen whole")))

    (define (scan-steps (gpu Gpu) (b Build) (n Node)) (→ Build)
      (let* ((out (buffer-of b n default-port))
             (scan (make-scan gpu (string-append (● b label) "/scan")
                              out
                              (element-count (list-ref (● n args) 0)))))
        (step-added (copied-into gpu b (list-ref (● n args) 0) out) (Scanning scan))))

    ;; A view's elements written densely into `buffer`.
    (define (copied-into (gpu Gpu) (b Build) (view View) (buffer GpuBuffer)) (→ Build)
      (if (fill? view)
          (dispatched gpu b
                      (copy-code view)
                      "main"
                      (list (new Pair (first 1) (second buffer)))
                      (tiles (element-count view) 256))
          (dispatched gpu b
                      (copy-code view)
                      "main"
                      (list (new Pair (first 0) (second (view-buffer b view)))
                            (new Pair (first 1) (second buffer)))
                      (tiles (element-count view) 256))))

    ;; Every port zeroed, then each kernel over the bindings it uses: the
    ;; arguments first, then the ports.
    (define (custom-steps (gpu Gpu) (b Build) (n Node) (c Custom)) (→ Build)
      (let ((buffers (append (map (lambda (a) (view-buffer b a)) (● n args))
                             (map (lambda (port) (buffer-of b n (● port name))) (● n ports)))))
        (fold-left (lambda (b kernel)
                     (dispatched gpu b
                                 (● kernel code)
                                 (● kernel entry)
                                 (map
                                  (lambda (k) (new Pair (first k) (second (list-ref buffers k))))
                                  (● kernel bindings))
                                 (● kernel workgroups)))
                   (fold-left
                    (lambda (b port) (zeroed gpu b (buffer-of b n (● port name)) (bytes-of port)))
                    b
                    (● n ports))
                   (● c kernels))))

    ;; A reduction over a span of up to 256 elements: a thread an output.
    ;; Over more: a workgroup reduces each part of 4096, and the parts are
    ;; reduced the same way, level by level, until one part is left.
    (define (reduce-steps (gpu Gpu) (b Build) (n Node) (op Reduction) (span (List I64))) (→ Build)
      (let ((count (product span)) (outputs (product (● (port-of n default-port) shape))))
        (if (<= count 256)
            (generated gpu b n (thread-code n) (tiles outputs 256))
            (reduce-levels gpu b n op outputs count (None)))))

    ;; One level over `span` elements an output, from the node's arguments
    ;; or from the parts a level below wrote, into the port or into parts
    ;; for the level above.
    (define (reduce-levels (gpu Gpu) (b Build)
                           (n Node)
                           (op Reduction)
                           (outputs I64)
                           (span I64)
                           (from (Option GpuBuffer)))
      (→ Build)
      (let* ((parts (tiles span 4096))
             (code (level-code n op outputs span parts (some? from)))
             (source (match from
                       ((Some buffer) (list (new Pair (first 0) (second buffer))))
                       ((None) (arg-entries b n))))
             (into (lambda (buffer)
                     (append source
                             (list (new Pair
                                     (first (if (some? from) 1 (first-port-binding n)))
                                     (second buffer)))))))
        (if (= parts 1)
            (dispatched gpu b code "main" (into (buffer-of b n default-port)) outputs)
            (let* ((pair (taken gpu b "partial" (* 4 (* outputs parts))))
                   (partial (● pair second))
                   (next
                    (dispatched gpu (● pair first) code "main" (into partial) (* outputs parts)))
                   (done (reduce-levels gpu next n op outputs parts (Some partial))))
              (given-back done (* 4 (* outputs parts)) partial)))))

    (define (some? (value (Option GpuBuffer))) (→ Bool)
      (match value
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Sinks and updates ----

    ;; A sink's buffer: its port's when it reads a computed port whole and
    ;; in order, in any shape, a copy otherwise; and a buffer to read it
    ;; back through.
    (define (sink-built (gpu Gpu) (state (Pair Build (List Sink))) (view View))
      (→ (Pair Build (List Sink)))
      (let* ((b (● state first))
             (size (max 4 (* 4 (element-count view))))
             (direct (and (whole-buffer? view)
                          (not (fill? view))
                          (pooled? (● view node kind))
                          (not (● b borrowing))))
             (made (if direct
                       (new Pair (first b) (second (view-buffer b view)))
                       (let ((buffer (new-buffer gpu (string-append (● b label) "/sink") size)))
                         (new Pair
                           (first (copied-into gpu (made-buffer b "sink" buffer size) view buffer))
                           (second buffer)))))
             (readback ((● gpu create-buffer) (new BufferDescriptor
                                                (label (string-append (● b label) "/readback"))
                                                (size (i64->i32 size))
                                                (usage (list (MapRead) (CopyDst)))))))
        (new Pair
          (first (made-buffer (● made first) "readback" readback size))
          (second (Cons (new Sink (buffer (● made second)) (readback readback) (size size))
                        (● state second))))))

    ;; A view of a param written by this step needs its old contents. Make
    ;; that read a graph node, so it runs before any assignment. Computed
    ;; values already have their own buffers.
    (define (prepare-update (update (Pair View View)) (written (Table Bool))) (→ (Pair View View))
      (let ((target (● update first)) (value (● update second)))
        (match (● target node kind)
          ((Param name)
           (unless (identity? target)
             (panic (string-append "tensor lower: update must cover the whole param " name)))
           (unless (same-etype? (etype-of target) (etype-of value))
             (panic (string-append "tensor lower: cannot update " (etype-wgsl (etype-of target))
                                   " param " name " with " (etype-wgsl (etype-of value))))))
          (_ (panic "tensor lower: an update's target must be a whole param")))
        (unless (= (element-count target) (element-count value))
          (panic "tensor lower: an update's value is not its param's size"))
        (if (table-contains? written (● value node key))
            (new Pair (first target) (second (copy value)))
            update)))

    ;; ---- In place ----

    ;; A map computing a whole update writes it into its param's own
    ;; buffer, sparing the copy after every node, where nothing could tell:
    ;; the map reads the param, if at all, only at the elements each thread
    ;; writes, and each thread loads all it needs before it stores (Map
    ;; text); no later node reads the param, whose old value is gone once
    ;; the map runs, and neither does a sink or another update's copy,
    ;; which run after every node; and the param has its buffer before
    ;; then. Training's Adam updates are such maps, and fusing makes each
    ;; param's three one map of three ports, each written in place.
    ;; Answered by the map's port, with the param it writes.
    (define (in-place-ports (assignments (List (Pair View View)))
                            (sinks (List View))
                            (order (List Node))
                            (last (Table I64)))
      (→ (Table View))
      (let ((at (positions order))
            (read-last (pinned-keys (append sinks (map (lambda (u) (● u second)) assignments)))))
        (fold-left (lambda (ports u)
                     (let ((key (port-key (● u second node) (● u second port))))
                       (if (and (not (table-contains? ports key))
                                (not (table-contains? read-last (● u first node key)))
                                (writes-in-place? (● u first) (● u second) at last))
                           (table-set ports key (● u first))
                           ports)))
                   (empty-table)
                   assignments)))

    ;; Each node's step in `order`.
    (define (positions (order (List Node))) (→ (Table I64))
      (fold-left (lambda (at pair) (table-set at (● pair second key) (● pair first)))
                 (empty-table)
                 (zip (iota (length order)) order)))

    (define (writes-in-place? (target View) (value View) (at (Table I64)) (last (Table I64)))
      (→ Bool)
      (let* ((n (● value node))
             (param (● target node key))
             (step (table-ref-or at (● n key) -1))
             (shape (● (port-of n (● value port)) shape)))
        (and (match (● n kind)
               ((Map _) #t)
               (_ #f))
             (whole-buffer? value)
             (< (table-ref-or at param step) step)
             (<= (table-ref-or last param -1) step)
             (every? (lambda (a)
                       (or (not (string=? (● a node key) param))
                           (and (whole-buffer? a) (equal-lists? (shape-of a) shape))))
                     (● n args)))))

    ;; Whether update `u`'s map writes it into its param.
    (define (written-in-place? (ports (Table View)) (u (Pair View View))) (→ Bool)
      (match (table-ref ports (port-key (● u second node) (● u second port)))
        ((Some target) (string=? (● target node key) (● u first node key)))
        ((None) #f)))

    ;; A map writing updates in place, as it is built: reading each param
    ;; through the port that writes it, which is the param's buffer, so its
    ;; kernel binds the buffer once and loads the param from that port
    ;; (`load`). WebGPU forbids a dispatch to bind a buffer it writes any
    ;; other way. Fusing counted on these bindings (fuse.sld, `bindings`),
    ;; so a map of more than eight is refused here, where it would fail.
    (define (reading-own-port (b Build) (n Node)) (→ Node)
      (let ((read (fold-left (lambda (n port) (reading-port b n (● port name))) n (● n ports))))
        (when (and (bodied? read) (> (+ (length (map-ports read)) (length (● read ports))) 8))
          (panic "tensor lower: a fused map binds more than eight buffers"))
        read))

    (define (reading-port (b Build) (n Node) (port String)) (→ Node)
      (match (table-ref (● b in-place) (port-key n port))
        ((Some target)
         (new Node
           (key (● n key))
           (kind (● n kind))
           (args (map (lambda (a)
                        (if (string=? (● a node key) (● target node key))
                            (new View (node n) (port port) (accessor (● a accessor)))
                            a))
                      (● n args)))
           (ports (● n ports))))
        ((None) n)))

    ;; Whether an argument is a port of the node itself, as one a map
    ;; writing an update in place reads its param through.
    (define (own-port? (n Node) (a View)) (→ Bool) (string=? (● a node key) (● n key)))

    ;; ---- Running ----

    (define (write-param (gpu Gpu) (program Program) (name String) (data Bytes)) (→ Unit)
      (match (table-ref (● program params) name)
        ((Some binding)
         (unless (= (array-length data) (* 4 (product (● binding port shape))))
           (panic (string-append "tensor: param " name " written with the wrong number of bytes")))
         ((● gpu write-buffer) (● binding buffer) 0 data))
        ((None) (panic (string-append "tensor: the program has no param " name)))))

    ;; A param's buffer, for a host to copy into on the device, as from a
    ;; texture; and a sink's, for a pass that draws it. Either holds what
    ;; the last run that was submitted left.

    (define (param-buffer (program Program) (name String)) (→ GpuBuffer)
      (match (table-ref (● program params) name)
        ((Some binding) (● binding buffer))
        ((None) (panic (string-append "tensor: the program has no param " name)))))

    (define (sink-buffer (program Program) (k I64)) (→ GpuBuffer)
      (● (list-ref (● program sinks) k) buffer))

    ;; The program's steps encoded into the caller's compute pass, in order.
    (define (encode-steps (gpu Gpu) (pass GpuComputePass) (program Program)) (→ Unit)
      (for-each (lambda (step) (encode-step gpu pass step)) (● program steps)))

    ;; The program's steps in a compute pass of their own, submitted.
    (define (run-program (gpu Gpu) (program Program)) (→ Unit)
      (run-steps gpu (● program steps)))

    (define (run-steps (gpu Gpu) (steps (List Step))) (→ Unit)
      (let* ((encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
        (for-each (lambda (step) (encode-step gpu pass step)) steps)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))))

    (define (encode-step (gpu Gpu) (pass GpuComputePass) (step Step)) (→ Unit)
      (match step
        ((Dispatch pipeline group x y _ _)
         ((● gpu set-compute-pipeline) pass pipeline)
         ((● gpu set-compute-bind-group) pass 0 group)
         ((● gpu dispatch-workgroups) pass (i64->i32 x) (i64->i32 y) 1))
        ((Sorting sorter) (dispatch-sort gpu pass sorter))
        ((Scanning scan) (dispatch-scan gpu pass scan))))

    ;; Sink `k`'s bytes as the last run left them.
    (define (read-sink (gpu Gpu) (program Program) (k I64)) (→ Bytes)
      (let ((sink (list-ref (● program sinks) k)) (encoder ((● gpu create-command-encoder))))
        ((● gpu copy-buffer-to-buffer) encoder
         (● sink buffer)
         0
         (● sink readback)
         0
         (i64->i32 (● sink size)))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        ((● gpu read-buffer) (● sink readback) 0 (i64->i32 (● sink size)))))

    ;; A param's bytes, through a buffer made for the reading.
    (define (read-param (gpu Gpu) (program Program) (name String)) (→ Bytes)
      (match (table-ref (● program params) name)
        ((Some binding)
         (let* ((size (bytes-of (● binding port)))
                (readback ((● gpu create-buffer) (new BufferDescriptor
                                                   (label (string-append "read " name))
                                                   (size (i64->i32 size))
                                                   (usage (list (MapRead) (CopyDst))))))
                (encoder ((● gpu create-command-encoder))))
           ((● gpu copy-buffer-to-buffer) encoder (● binding buffer) 0 readback 0 (i64->i32 size))
           ((● gpu submit) (list ((● gpu finish) encoder)))
           (let ((data
                  ((● gpu read-buffer)
                   readback
                   0
                   (i64->i32 (* 4 (product (● binding port shape)))))))
             ((● gpu destroy) (BufferObject readback))
             data)))
        ((None) (panic (string-append "tensor: the program has no param " name)))))

    (define (release-program (gpu Gpu) (program Program)) (→ Unit)
      (for-each (lambda (step)
                  (match step
                    ((Sorting sorter) (release-sorter gpu sorter))
                    ((Scanning scan) (release-scan gpu scan))
                    (_ (unit))))
                (● program steps))
      (for-each (lambda (object) ((● gpu destroy) object)) (● program objects)))

    ;; ---- Growing ----

    ;; A copy of every param of a program, made on the device, so a host
    ;; can release the program and lower a larger one before giving the
    ;; params back: two programs' scratch need not fit at once.
    (record Stash
      ((params (Table Binding))))

    (define (stash-params (gpu Gpu) (program Program)) (→ Stash)
      (let* ((encoder ((● gpu create-command-encoder)))
             (copies (map (lambda (name)
                            (match (table-ref (● program params) name)
                              ((Some binding)
                               (let ((copy (new-buffer gpu (string-append "stash/" name)
                                                       (bytes-of (● binding port)))))
                                 ((● gpu copy-buffer-to-buffer) encoder
                                  (● binding buffer)
                                  0
                                  copy
                                  0
                                  (i64->i32 (bytes-of (● binding port))))
                                 (new Pair
                                   (first name)
                                   (second (new Binding (buffer copy) (port (● binding port)))))))
                              ((None) (panic "tensor: a param went missing"))))
                          (table-keys (● program params)))))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (new Stash
          (params (fold-left (lambda (t pair) (table-set t (● pair first) (● pair second)))
                             (empty-table)
                             copies)))))

    ;; Each stashed param copied into the program's of the same name, as
    ;; much of it as both hold, and the stash destroyed.
    (define (unstash-params (gpu Gpu) (stash Stash) (program Program)) (→ Unit)
      (let ((encoder ((● gpu create-command-encoder))))
        (for-each (lambda (name)
                    (match (new Pair
                             (first (table-ref (● stash params) name))
                             (second (table-ref (● program params) name)))
                      ((Pair (Some source) (Some target))
                       ((● gpu copy-buffer-to-buffer) encoder
                        (● source buffer)
                        0
                        (● target buffer)
                        0
                        (i64->i32 (min (bytes-of (● source port))
                                       (bytes-of (● target port))))))
                      (_ (unit))))
                  (table-keys (● stash params)))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (for-each (lambda (name)
                    (match (table-ref (● stash params) name)
                      ((Some binding) ((● gpu destroy) (BufferObject (● binding buffer))))
                      ((None) (unit))))
                  (table-keys (● stash params)))))

    ;; ---- Profiling ----

    ;; Each step's time on the device, in seconds, with its kernel's entry
    ;; and code naming a dispatch. Each step runs in a compute pass of its
    ;; own, whose timestamps are written as it begins and as it ends, and
    ;; every pass is in one submission, so the device runs the steps as a
    ;; run does, with nothing waiting between them; a pass boundary costs a
    ;; little that one pass would not. The device must have the
    ;; `timestamp-query` feature, and a browser rounds the times unless its
    ;; WebGPU developer features are on. A query set holds at most 4096
    ;; queries, so the steps are timed 2048 at a time.
    (define (profile-program (gpu Gpu) (program Program)) (→ (List (Pair String F64)))
      (concatenate (map (lambda (steps) (timed-steps gpu steps)) (groups (● program steps) 2048))))

    (define (groups (items (List T)) (size I64)) (→ (List (List T))) (∀ (T))
      (if (null? items)
          (Nil)
          (Cons (take items (min size (length items)))
                (groups (list-drop items (min size (length items))) size))))

    ;; The steps, each in a timed pass of its own, then their times read.
    (define (timed-steps (gpu Gpu) (steps (List Step))) (→ (List (Pair String F64)))
      (let* ((count (length steps))
             (queries ((● gpu create-query-set) (new QuerySetDescriptor
                                                  (label "profile")
                                                  (count (i64->i32 (* 2 count))))))
             (writes (map (lambda (k) (step-writes queries k)) (iota count)))
             (encoder ((● gpu create-command-encoder))))
        (for-each (lambda (pair) (timed-step gpu encoder (● pair first) (● pair second)))
                  (zip writes steps))
        (let ((times (submit-timed gpu encoder queries (i64->i32 (* 2 count)))))
          ((● gpu destroy) (QuerySetObject queries))
          (map (lambda (pair)
                 (new Pair
                   (first (step-name (● pair second)))
                   (second (elapsed-seconds times (● pair first beginning) (● pair first end)))))
               (zip writes steps)))))

    ;; Step `k`'s pass writes query 2k as it begins and 2k + 1 as it ends.
    (define (step-writes (queries GpuQuerySet) (k I64)) (→ TimestampWrites)
      (new TimestampWrites
        (query-set queries)
        (beginning (i64->i32 (* 2 k)))
        (end (i64->i32 (+ (* 2 k) 1)))))

    (define (timed-step (gpu Gpu) (encoder GpuCommandEncoder) (writes TimestampWrites) (step Step))
      (→ Unit)
      (let ((pass ((● gpu begin-timed-compute-pass) encoder writes)))
        (encode-step gpu pass step)
        ((● gpu end-compute-pass) pass)))

    ;; The bytes of the buffers a program made, by use and size, the
    ;; largest first; its sorts and scans hold their own beside these.
    (define (program-memory (program Program)) (→ (List (Pair String I64)))
      (let ((totals (fold-left (lambda (t made)
                                 (let ((key (string-append (● made use)
                                                           " of "
                                                           (show (● made size)))))
                                   (table-set t
                                              key
                                              (+ (● made size)
                                                 (match (table-ref t key)
                                                   ((Some total) total)
                                                   ((None) 0))))))
                               (empty-table)
                               (● program made))))
        (list-sort (lambda (a b) (> (● a second) (● b second)))
                   (map (lambda (key)
                          (new Pair
                            (first key)
                            (second (match (table-ref totals key)
                                      ((Some total) total)
                                      ((None) 0)))))
                        (table-keys totals)))))

    (define (step-name (step Step)) (→ String)
      (match step
        ((Dispatch _ _ x y code entry)
         (string-append entry " over " (show (* x y)) " workgroups\n" code))
        ((Sorting _) "a sort")
        ((Scanning _) "a scan")))

    ;; ---- Kernel text ----

    ;; WGSL for each generated kernel, every size a literal. A thread
    ;; kernel finds its element `i` across rows of workgroups.

    (define (u (value I64)) (→ String) (string-append (show value) "u"))

    (define (storage (binding I64) (name String) (access String) (type String)) (→ String)
      (string-append "@group(0) @binding("
                     (show binding)
                     ") var<storage, "
                     access
                     "> "
                     name
                     ": array<"
                     type
                     ">;\n"))

    (define (thread-kernel (declarations String) (count I64) (body String)) (→ String)
      (string-append declarations
                     "@compute @workgroup_size(256)\n"
                     "fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(num_workgroups) nwg: vec3u) {\n"
                     "  let i = gid.y * nwg.x * 256u + gid.x;\n"
                     "  if (i >= " (u count) ") { return; }\n"
                     body
                     "}\n"))

    (define zero-code
      (→ String)
      (string-append (storage 0 "out" "read_write" "u32")
                     "@compute @workgroup_size(256)\n"
                     "fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(num_workgroups) nwg: vec3u) {\n"
                     "  let i = gid.y * nwg.x * 256u + gid.x;\n"
                     "  if (i < arrayLength(&out)) { out[i] = 0u; }\n"
                     "}\n"))

    ;; A node's buffer arguments, read only, then its ports.
    (define (declared (n Node)) (→ String)
      (string-append
       (string-join (map (lambda (pair)
                           (storage (● pair first)
                                    (string-append "a" (show (● pair first)))
                                    "read"
                                    (etype-wgsl (etype-of (● pair second)))))
                         (bound-args n))
                    "")
       (string-join (map-indexed (lambda (j port)
                                   (storage (+ (first-port-binding n) j)
                                            (● port name)
                                            "read_write"
                                            (etype-wgsl (● port etype))))
                                 (● n ports))
                    "")))

    ;; The index of flat element `var` on each axis of `shape`.
    (define (indices (var String) (shape (List I64))) (→ (List String))
      (map-indexed (lambda (k pair)
                     (let ((over (if (= (● pair second) 1)
                                     var
                                     (string-append "(" var " / " (u (● pair second)) ")"))))
                       (if (= k 0) over (string-append "(" over " % " (u (● pair first)) ")"))))
                   (zip shape (contiguous-pitch shape))))

    ;; The address of the element at `index` under an accessor; an axis of
    ;; pitch 0 adds nothing.
    (define (address (a Accessor) (index (List String))) (→ String)
      (let ((terms (filter-map (lambda (k)
                                 (let ((pitch (list-ref (● a pitch) k)))
                                   (if (= pitch 0)
                                       (None)
                                       (Some (if (= pitch 1)
                                                 (list-ref index k)
                                                 (string-append (list-ref index k)
                                                                " * "
                                                                (u pitch)))))))
                               (iota (length index)))))
        (string-append "(" (string-join (Cons (u (● a offset)) terms) " + ") ")")))

    ;; The address of flat element `var` of a view over its own shape.
    (define (flat-address (a Accessor) (var String)) (→ String)
      (if (equal-pitches? (● a pitch) (contiguous-pitch (● a shape)))
          (string-append "(" (u (● a offset)) " + " var ")")
          (address a (indices var (● a shape)))))

    (define (equal-pitches? (a (List I64)) (b (List I64))) (→ Bool)
      (every? (lambda (pair) (= (● pair first) (● pair second))) (zip a b)))

    ;; Argument `k` of a node at `at`: a literal for a `Fill`, and the
    ;; port's own variable for one of the node's own ports.
    (define (load (n Node) (k I64) (at String)) (→ String)
      (let ((a (list-ref (● n args) k)))
        (match (● a node kind)
          ((Fill value) (literal (etype-of a) value))
          (_ (if (own-port? n a)
                 (string-append (● a port) "[" at "]")
                 (string-append "a" (show (arg-binding n k)) "[" at "]"))))))

    (define (literal (etype Etype) (value F64)) (→ String)
      (match etype
        ((Float) (string-append "f32(" (f64->string value) ")"))
        ((Unsigned) (u (modulo (f64->i64 value) 4294967296)))
        ((Signed) (string-append "i32(" (show (f64->i64 value)) ")"))))

    ;; A copy of a view, dense, from binding 0 to binding 1.
    (define (copy-code (view View)) (→ String)
      (let ((type (etype-wgsl (etype-of view))))
        (thread-kernel (string-append (if (fill? view) "" (storage 0 "a0" "read" type))
                                      (storage 1 "out" "read_write" type))
                       (element-count view)
                       (string-append "  out[i] = "
                                      (match (● view node kind)
                                        ((Fill value) (literal (etype-of view) value))
                                        (_ (string-append "a0["
                                                          (flat-address (● view accessor) "i")
                                                          "]")))
                                      ";\n"))))

    ;; A thread an output element, or a map's tile: maps, fills, gathers,
    ;; concats and small reductions.
    (define (thread-code (n Node)) (→ String)
      (let ((out (port-of n default-port)))
        (thread-kernel (declared n)
                       (threads n)
                       (match (● n kind)
                         ((Fill value)
                          (string-append "  out[i] = " (literal (● out etype) value) ";\n"))
                         ((Map bodies) (map-statements n bodies))
                         ((Gather) (gather-text n))
                         ((Concat axis) (concat-text n axis))
                         ((Reduce op span _) (small-reduce-text n op span))
                         (_ (panic "tensor lower: no thread kernel for this node"))))))

    ;; Argument k of a node at thread i, at index t of its load's tile.
    (define (operand (n Node) (k I64) (t (List I64))) (→ String)
      (load n k (flat-address (tile-element (● (list-ref (● n args) k) accessor) t) "i")))

    ;; Index t of a view's trailing axes, as an accessor over its leading
    ;; ones: its offset moved there.
    (define (tile-element (a Accessor) (t (List I64))) (→ Accessor)
      (let ((lead (- (length (● a shape)) (length t))))
        (new Accessor
          (offset (fold-left +
                             (● a offset)
                             (map (lambda (pair) (* (● pair first) (● pair second)))
                                  (zip (list-drop (● a pitch) lead) t))))
          (shape (take (● a shape) lead))
          (pitch (take (● a pitch) lead)))))

    ;; ---- Map text ----

    ;; The statements so far, the last first; each expression's name by
    ;; its text; and how many names were made, which numbers the next.
    (record Lets
      ((statements (List String))
       (names (Table String))
       (count I64)))

    ;; A map's bodies as statements of element i of its leading axes: a
    ;; `let` for each distinct load and operation of any of them, and for
    ;; each element of its tile, numbered in the order the bodies need
    ;; them; then each element of each port's tile there, body k's into
    ;; port k, every store after every load, so that a port written in
    ;; place has loaded its param. A load reads its argument's elements
    ;; there, through the argument's accessor. An expression fusing copied
    ;; into two places, or two bodies, is computed once, and no expression
    ;; nests another, so a fused body of hundreds stays within what a
    ;; shader compiler parses.
    (define (map-statements (n Node) (bodies (List Expr))) (→ String)
      (let ((done (bodies-text (lambda (k t) (operand n k t)) bodies)))
        (string-append (string-join (● done first) "")
                       (string-join
                        (map (lambda (pair) (port-stores (● pair first) (● pair second)))
                             (zip (● n ports) (● done second)))
                        ""))))

    (define (port-stores (port Port) (names (List String))) (→ String)
      (string-join
       (map-indexed (lambda (j name) (stored (● port name) (length names) j name)) names)
       ""))

    ;; Element j of a tile of `size` elements of `port`, at thread i's tile.
    (define (stored (port String) (size I64) (j I64) (name String)) (→ String)
      (if (= size 1)
          (string-append "  " port "[i] = " name ";\n")
          (string-append "  " port "[i * " (u size) " + " (u j) "] = " name ";\n")))

    ;; A body's statements, in order, and the names of its value's
    ;; elements, each load of argument k at index t of its tile reading
    ;; what `element` answers for k and t.
    (define (body-text (element (Fn I64 (List I64) → String)) (body Expr))
      (→ (Pair (List String) (List String)))
      (let ((done (bodies-text element (list body))))
        (new Pair (first (● done first)) (second (list-ref (● done second) 0)))))

    ;; Bodies' statements, sharing every `let`, and each body's names.
    (define (bodies-text (element (Fn I64 (List I64) → String)) (bodies (List Expr)))
      (→ (Pair (List String) (List (List String))))
      (let ((done (fold-left (lambda (state body)
                               (let ((next (named element body (● state first))))
                                 (new Pair
                                   (first (● next first))
                                   (second (Cons (● next second) (● state second))))))
                             (new Pair
                               (first (new Lets (statements (Nil)) (names (empty-table)) (count 0)))
                               (second (Nil)))
                             bodies)))
        (new Pair
          (first (reverse (● done first statements)))
          (second (reverse (● done second))))))

    ;; What names each element of `e`'s value, with the lets that compute
    ;; them: a literal stands for itself.
    (define (named (element (Fn I64 (List I64) → String)) (e Expr) (lets Lets))
      (→ (Pair Lets (List String)))
      (match e
        ((Load k _ tile) (lets-for lets (map (lambda (t) (element k t)) (tile-indices tile))))
        ((Literal value etype) (new Pair (first lets) (second (list (literal etype value)))))
        ((Apply op operands etype tile)
         (let ((tested (if (guardable? op operands)
                           (Some (named element (list-ref operands 0) lets))
                           (None))))
           (match tested
             ((Some done)
              (if (one-name? (● done second))
                  (guarded element done (list-ref operands 0) (list-ref operands 1) etype)
                  (applied element op operands etype tile lets)))
             ((None) (applied element op operands etype tile lets)))))))

    ;; An operation's elements' names, its operands named first.
    (define (applied (element (Fn I64 (List I64) → String))
                     (op Op)
                     (operands (List Expr))
                     (etype Etype)
                     (tile (List I64))
                     (lets Lets))
      (→ (Pair Lets (List String)))
      (let ((args (fold-left (lambda (state o)
                               (let ((next (named element o (● state first))))
                                 (new Pair
                                   (first (● next first))
                                   (second (append (● state second) (list (● next second)))))))
                             (new Pair (first lets) (second (Nil)))
                             operands)))
        (applied-names (● args first) op (● args second) operands etype tile)))

    ;; ---- Guards ----

    ;; A value where a condition holds and zero where it does not, the
    ;; condition one value however wide the value, as a tile of copies of
    ;; one value is once named: the value is computed inside an `if`, so
    ;; an element the condition culls, such as a gaussian off the screen,
    ;; reads and computes nothing for it, however deep the choice sits in
    ;; a fused body.
    (define (guardable? (op Op) (operands (List Expr))) (→ Bool)
      (match op
        ((Select) (zero-expr? (list-ref operands 2)))
        (_ #f)))

    (define (one-name? (names (List String))) (→ Bool)
      (every? (lambda (n) (string=? n (list-ref names 0))) names))

    (define (zero-expr? (e Expr)) (→ Bool)
      (match e
        ((Literal value _) (= value 0.0))
        ((Apply (Pack) operands _ _) (every? zero-expr? operands))
        (_ #f)))

    ;; The choice's statements: the condition's lets where they were, a
    ;; `var` of zero for each element of the value, and an `if` holding the
    ;; value's lets and setting the vars. The names made inside the `if`
    ;; are its own, so what comes after makes its own again.
    (define (guarded (element (Fn I64 (List I64) → String))
                     (tested (Pair Lets (List String)))
                     (condition Expr)
                     (value Expr)
                     (etype Etype))
      (→ (Pair Lets (List String)))
      (let* ((outer (● tested first))
             (inner (named element
                           value
                           (new Lets
                             (statements (Nil))
                             (names (● outer names))
                             (count (● outer count)))))
             (results (map (lambda (j) (string-append "v" (show (+ (● inner first count) j))))
                           (iota (length (● inner second)))))
             (type (etype-wgsl etype)))
        (new Pair
          (first (new Lets
                   (statements (Cons (string-append
                                      (string-concatenate
                                       (map (lambda (r)
                                              (string-append "  var " r ": " type " = "
                                                             (literal etype 0.0) ";\n"))
                                            results))
                                      "  if ("
                                      (list-ref (● tested second) 0)
                                      " != "
                                      (literal (expr-etype condition) 0.0)
                                      ") {\n"
                                      (string-concatenate (reverse (● inner first statements)))
                                      (string-concatenate
                                       (map (lambda (pair)
                                              (string-append "  "
                                                             (● pair first)
                                                             " = "
                                                             (● pair second)
                                                             ";\n"))
                                            (zip results (● inner second))))
                                      "  }\n")
                                     (● outer statements)))
                   (names (● outer names))
                   (count (+ (● inner first count) (length results)))))
          (second results))))

    ;; An operation's elements' names: a tile's own operations rearrange
    ;; or combine their operands' names; any other applies to each element,
    ;; a value's one name standing for every element.
    (define (applied-names (lets Lets)
                           (op Op)
                           (names (List (List String)))
                           (operands (List Expr))
                           (etype Etype)
                           (tile (List I64)))
      (→ (Pair Lets (List String)))
      (let ((from (expr-etype (list-ref operands 0)))
            (at (lambda (ns j) (if (= (length ns) 1) (list-ref ns 0) (list-ref ns j)))))
        (match op
          ((Pack) (new Pair (first lets) (second (concatenate names))))
          ((Pick indices)
           (new Pair
             (first lets)
             (second (map (lambda (j) (list-ref (list-ref names 0) j)) indices))))
          ((Halves)
           (lets-for lets
                     (concatenate (map (lambda (word)
                                         (list (string-append "unpack2x16float(" word ").x")
                                               (string-append "unpack2x16float(" word ").y")))
                                       (list-ref names 0)))))
          ((Product)
           (lets-for lets
                     (product-texts (list-ref names 0)
                                    (list-ref names 1)
                                    (expr-tile (list-ref operands 1)))))
          ((Fold combining)
           (lets-for lets (list (fold-left (lambda (acc name) (combine combining acc name))
                                           (list-ref (list-ref names 0) 0)
                                           (list-drop (list-ref names 0) 1)))))
          (_ (lets-for lets
                       (map (lambda (j)
                              (applied-text op (map (lambda (ns) (at ns j)) names) from etype))
                            (iota (product tile))))))))

    ;; The names of texts' values, each a new `let` the first time.
    (define (lets-for (lets Lets) (texts (List String))) (→ (Pair Lets (List String)))
      (let ((done (fold-left (lambda (state text)
                               (let ((next (let-for (● state first) text)))
                                 (new Pair
                                   (first (● next first))
                                   (second (Cons (● next second) (● state second))))))
                             (new Pair (first lets) (second (Nil)))
                             texts)))
        (new Pair (first (● done first)) (second (reverse (● done second))))))

    ;; Each element of a's tile, (m, k) or a row of k, by b's, (k, c),
    ;; row by row: a sum of products, in order.
    (define (product-texts (a (List String)) (b (List String)) (tb (List I64))) (→ (List String))
      (let ((k (list-ref tb 0)) (c (list-ref tb 1)))
        (map (lambda (at)
               (string-append
                "("
                (string-join (map (lambda (j)
                                    (string-append (list-ref a (+ (* (quotient at c) k) j))
                                                   " * "
                                                   (list-ref b (+ (* j c) (remainder at c)))))
                                  (iota k))
                             " + ")
                ")"))
             (iota (* (quotient (length a) k) c)))))

    ;; The name of the value `text` computes, a new `let` the first time.
    (define (let-for (lets Lets) (text String)) (→ (Pair Lets String))
      (match (table-ref (● lets names) text)
        ((Some name) (new Pair (first lets) (second name)))
        ((None)
         (let ((name (string-append "v" (show (● lets count)))))
           (new Pair
             (first (new Lets
                      (statements (Cons (string-append "  let " name " = " text ";\n")
                                        (● lets statements)))
                      (names (table-set (● lets names) text name))
                      (count (+ (● lets count) 1))))
             (second name))))))

    ;; An operation on its operands' text, of type `from-etype`, answering
    ;; `to-etype`.
    (define (applied-text (op Op) (operands (List String)) (from-etype Etype) (to-etype Etype))
      (→ String)
      (let* ((a (list-ref operands 0))
             (b (if (> (length operands) 1) (list-ref operands 1) ""))
             (from (etype-wgsl from-etype))
             (to (etype-wgsl to-etype))
             (infix (lambda (symbol) (string-append "(" a " " symbol " " b ")")))
             (call (lambda (name) (string-append name "(" a ")")))
             (truth (lambda (symbol)
                      (string-append "select(" to "(0), " to "(1), " a " " symbol " " b ")"))))
        (match op
          ((Neg) (string-append "(" from "(0) - " a ")"))
          ((Exp) (call "exp"))
          ((Log) (call "log"))
          ((Sqrt) (call "sqrt"))
          ((Sin) (call "sin"))
          ((Cos) (call "cos"))
          ((Abs) (call "abs"))
          ((Floor) (call "floor"))
          ((Sign) (call "sign"))
          ((Add) (infix "+"))
          ((Sub) (infix "-"))
          ((Mul) (infix "*"))
          ((Div) (infix "/"))
          ((Pow) (string-append "pow(" a ", " b ")"))
          ((Max) (string-append "max(" a ", " b ")"))
          ((Min) (string-append "min(" a ", " b ")"))
          ((Less) (truth "<"))
          ((LessEqual) (truth "<="))
          ((Greater) (truth ">"))
          ((GreaterEqual) (truth ">="))
          ((Equal) (truth "=="))
          ((NotEqual) (truth "!="))
          ((BitAnd) (infix "&"))
          ((BitOr) (infix "|"))
          ((BitXor) (infix "^"))
          ((ShiftLeft) (string-append "(" a " << u32(" b "))"))
          ((ShiftRight) (string-append "(" a " >> u32(" b "))"))
          ((Select)
           (string-append "select(" (list-ref operands 2) ", " b ", " a " != " from "(0))"))
          ((Convert _) (string-append to "(" a ")"))
          ((Bitcast _) (string-append "bitcast<" to ">(" a ")"))
          (_ (panic "tensor lower: a tile's own operation applied to each element")))))

    ;; ---- Row text ----

    ;; Output row r is source row indices[r].
    (define (gather-text (n Node)) (→ String)
      (let* ((source (list-ref (● n args) 0))
             (index (indices "i" (● (port-of n default-port) shape)))
             (row (string-append "u32("
                                 (load n
                                       1
                                       (address (● (list-ref (● n args) 1) accessor)
                                                (list (list-ref index 0))))
                                 ")")))
        (string-append "  out[i] = "
                       (load n 0 (address (● source accessor) (Cons row (list-tail index 1))))
                       ";\n")))

    ;; The output's index on the joined axis picks the argument whose span
    ;; holds it.
    (define (concat-text (n Node) (axis I64)) (→ String)
      (let ((index (indices "i" (● (port-of n default-port) shape))))
        (string-append "  let c = " (list-ref index axis) ";\n"
                       (string-join (map-indexed (lambda (k span)
                                                   (string-append (if (= k 0) "  if" " else if")
                                                                  " (c < "
                                                                  (u (+ (● span first)
                                                                        (● span second)))
                                                                  ") { out[i] = "
                                                                  (load n
                                                                        k
                                                                        (address
                                                                         (● (list-ref (● n args) k)
                                                                            accessor)
                                                                         (map-indexed
                                                                          (lambda (j text)
                                                                            (if (= j axis)
                                                                                (string-append
                                                                                 "(c - "
                                                                                 (u (● span first))
                                                                                 ")")
                                                                                text))
                                                                          index)))
                                                                  "; }"))
                                                 (spans-of (● n args) axis))
                                    "")
                       "\n")))

    ;; Where each view starts on `axis` when they are joined, and its size.
    (define (spans-of (views (List View)) (axis I64)) (→ (List (Pair I64 I64)))
      (reverse (● (fold-left (lambda (state v)
                               (let ((size (list-ref (shape-of v) axis)))
                                 (new Pair
                                   (first (Cons (new Pair (first (● state second)) (second size))
                                                (● state first)))
                                   (second (+ (● state second) size)))))
                             (new Pair (first (Nil)) (second 0))
                             views)
                  first)))

    ;; Source row r added to output row indices[r], word by word, by a
    ;; compare-and-swap loop for floats.
    (define (scatter-code (n Node)) (→ String)
      (let* ((source (list-ref (● n args) 0))
             (out (port-of n default-port))
             (etype (● out etype))
             (index (indices "i" (shape-of source)))
             (row (string-append "u32("
                                 (load n
                                       1
                                       (address (● (list-ref (● n args) 1) accessor)
                                                (list (list-ref index 0))))
                                 ")"))
             (target (address (dense-accessor (● out shape)) (Cons row (list-tail index 1))))
             (value (load n 0 (flat-address (● source accessor) "i"))))
        (thread-kernel
         (string-append (if (fill? source) "" (storage 0 "a0" "read" (etype-wgsl etype)))
                        (if (fill? (list-ref (● n args) 1)) "" (storage 1 "a1" "read" "u32"))
                        (storage 2 "out" "read_write" (match etype
                                                        ((Signed) "atomic<i32>")
                                                        (_ "atomic<u32>"))))
         (element-count source)
         (match etype
           ((Float) (string-append "  let at = " target ";\n"
                                   "  let v = " value ";\n"
                                   "  var old = atomicLoad(&out[at]);\n"
                                   "  loop {\n"
                                   "    let r = atomicCompareExchangeWeak(&out[at], old, bitcast<u32>(bitcast<f32>(old) + v));\n"
                                   "    if (r.exchanged) { break; }\n"
                                   "    old = r.old_value;\n"
                                   "  }\n"))
           (_ (string-append "  atomicAdd(&out[" target "], " value ");\n"))))))

    ;; g's element at index written to `accessor`'s address of it.
    (define (place-code (n Node) (accessor Accessor)) (→ String)
      (let ((g (list-ref (● n args) 0)))
        (thread-kernel (declared n)
                       (element-count g)
                       (string-append "  out[" (address accessor (indices "i" (shape-of g))) "] = "
                                      (load n 0 (flat-address (● g accessor) "i")) ";\n"))))

    ;; ---- Reduction text ----

    (define (combine (op Reduction) (a String) (b String)) (→ String)
      (match op
        ((Sum) (string-append "(" a " + " b ")"))
        ((Largest) (string-append "max(" a ", " b ")"))
        ((Smallest) (string-append "min(" a ", " b ")"))))

    (define (identity-of (op Reduction) (etype Etype)) (→ String)
      (match op
        ((Sum) (string-append (etype-wgsl etype) "(0)"))
        ((Largest) (match etype
                     ((Float) "-0x1.fffffep+127f")
                     ((Unsigned) "0u")
                     ((Signed) "i32(-2147483648)")))
        ((Smallest) (match etype
                      ((Float) "0x1.fffffep+127f")
                      ((Unsigned) "4294967295u")
                      ((Signed) "i32(2147483647)")))))

    ;; Argument k's element j of output o's span, at index t of the load's
    ;; tile: o's index over the port's axes, then j's over the span's,
    ;; through its accessor.
    (define (span-address (n Node) (span (List I64)) (k I64) (o String) (j String) (t (List I64)))
      (→ String)
      (address (tile-element (● (list-ref (● n args) k) accessor) t)
               (append (indices o (● (port-of n default-port) shape)) (indices j span))))

    ;; A reduction's body at element j of output o's span: its statements,
    ;; indented by `indent`, and the name of its value.
    (define (span-body (n Node) (o String) (j String) (indent String)) (→ (Pair String String))
      (match (● n kind)
        ((Reduce _ span body)
         (let ((done (body-text (lambda (k t) (load n k (span-address n span k o j t))) body)))
           (new Pair
             (first (string-join (map (lambda (s) (string-append indent s)) (● done first)) ""))
             (second (list-ref (● done second) 0)))))
        (_ (panic "tensor lower: a span body of a node not a reduction"))))

    (define (small-reduce-text (n Node) (op Reduction) (span (List I64))) (→ String)
      (let ((element (span-body n "i" "j" "  ")))
        (string-append "  var acc = " (identity-of op (● (port-of n default-port) etype)) ";\n"
                       "  for (var j = 0u; j < " (u (product span)) "; j++) {\n"
                       (● element first)
                       "    acc = " (combine op "acc" (● element second)) ";\n"
                       "  }\n"
                       "  out[i] = acc;\n")))

    ;; A workgroup a part of an output's span: each thread combines up to
    ;; 16 elements, then the workgroup's 256 combine pairwise. The first
    ;; level computes the body over the node's arguments; later ones read
    ;; the parts below, densely, from binding 0.
    (define (level-code (n Node) (op Reduction) (outputs I64) (span I64) (parts I64) (partial Bool))
      (→ String)
      (let* ((etype (● (port-of n default-port) etype))
             (type (etype-wgsl etype))
             (element (if partial
                          (new Pair (first "") (second (string-append "a0[o * " (u span) " + j]")))
                          (span-body n "o" "j" "        "))))
        (string-append
         (if partial
             (string-append (storage 0 "a0" "read" type) (storage 1 "out" "read_write" type))
             (declared n))
         "var<workgroup> lane: array<" type ", 256>;\n"
         "@compute @workgroup_size(256)\n"
         "fn main(@builtin(workgroup_id) wid: vec3u, @builtin(num_workgroups) nwg: vec3u, @builtin(local_invocation_index) t: u32) {\n"
         "  let g = wid.y * nwg.x + wid.x;\n"
         "  let o = g / " (u parts) ";\n"
         "  let part = g % " (u parts) ";\n"
         "  var acc = " (identity-of op etype) ";\n"
         "  if (g < " (u (* outputs parts)) ") {\n"
         "    for (var r = 0u; r < 16u; r++) {\n"
         "      let j = part * 4096u + r * 256u + t;\n"
         "      if (j < " (u span) ") {\n"
         (● element first)
         "        acc = " (combine op "acc" (● element second)) ";\n"
         "      }\n"
         "    }\n"
         "  }\n"
         "  lane[t] = acc;\n"
         "  workgroupBarrier();\n"
         "  for (var s = 128u; s > 0u; s = s >> 1u) {\n"
         "    if (t < s) { lane[t] = " (combine op "lane[t]" "lane[t + s]") "; }\n"
         "    workgroupBarrier();\n"
         "  }\n"
         "  if (t == 0u && g < " (u (* outputs parts)) ") { out[g] = lane[0]; }\n"
         "}\n")))

    ))
