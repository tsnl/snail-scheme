;; Lowering a tensor graph to plain WebGPU objects, explicitly and once:
;; a buffer for each port the program needs, a compute pipeline and bind
;; group for each dispatch, and the order to run them in. Everything it
;; makes is the caller's: a `Program` lists its steps, each with its WGSL
;; text, pipeline, bind group and workgroups, and every buffer it made, by
;; use and size. The caller encodes the steps into a compute pass of its
;; own, or lets `run-program` do that in a pass by itself, as often as it
;; likes, with nothing built again; and releases the program when done.
;;
;;   (let ((program (lower "fit" (list loss) (list (new Pair (first w) (second w')))))) ...)
;;   (write-param program "x" bytes)   ; a param's elements, 32-bit words
;;   (run-program program)             ; every sink computed, then w := w'
;;   (read-sink program 0)             ; the loss's bytes
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
   (only (snail shell task) tasks)
   (only (snail shell gpu)
         gpu
         create-buffer
         write-buffer
         read-buffer
         create-shader-module
         create-compute-pipeline
         create-bind-group
         create-command-encoder
         copy-buffer-to-buffer
         begin-compute-pass
         begin-timed-compute-pass
         create-query-set
         submit-timed
         elapsed-seconds
         set-compute-pipeline
         set-compute-bind-group
         dispatch-workgroups
         end-compute-pass
         finish
         submit
         destroy
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
    ;; everything to release; and whether the pool began with given scratch.
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
       (borrowing Bool)))

    ;; ---- Lowering ----

    (define (lower (label String) (sinks (List View)) (updates (List (Pair View View))))
      (→ Program)
      (! gpu)
      (lower-with label sinks updates nothing-given))

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
    ;; and each update written to its param. An update's param is a root
    ;; too, so one only written, never read, still has its buffer. A param
    ;; `given` has is read and written in the caller's buffer, which must be
    ;; its size, and the pool starts with the scratch it has.
    (define (lower-with (label String)
                        (sinks (List View))
                        (updates (List (Pair View View)))
                        (given Given))
      (→ Program)
      (! gpu)
      (let* ((targets (map (lambda (u) (● u first)) updates))
             (written (pinned-keys targets))
             (assignments (map (lambda (u) (prepare-update u written)) updates))
             (roots (append targets (append sinks (map (lambda (u) (● u second)) assignments))))
             (order (toposort roots))
             (last (last-uses order))
             (pinned (pinned-keys roots))
             (built
              (fold-left (lambda (b pair) (node-built b (● pair second) (● pair first) last pinned))
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
                           (borrowing (not (null? (table-keys (● given scratch))))))
                         (zip (iota (length order)) order)))
             (sunk (fold-left sink-built (new Pair (first built) (second (Nil))) sinks))
             (done
              (fold-left (lambda (b u) (copied-into b (● u second) (view-buffer b (● u first))))
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
    (define (node-built (b Build) (n Node) (t I64) (last (Table I64)) (pinned (Table Bool)))
      (→ Build)
      (! gpu)
      ;; Only a custom kernel reads a Fill through a buffer. Sinks and
      ;; assignments, like generated kernels, can copy its literal directly.
      (if (match (● n kind)
            ((Fill _) (not (table-contains? last (● n key))))
            (_ #f))
          b
          (let ((ready (fold-left (lambda (b port) (port-given b n port)) b (● n ports))))
            (fold-left (lambda (b a)
                         (if (and (= (table-ref-or last (● a node key) -1) t)
                                  (not (table-contains? pinned (● a node key)))
                                  (pooled? (● a node kind)))
                             (released-node b (● a node))
                             b))
                       (node-steps ready n)
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

    (define (new-buffer (label String) (size I64)) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor
                       (label label)
                       (size (i64->i32 size))
                       (usage (list (Storage) (CopySrc) (CopyDst))))))

    ;; A buffer of `size` bytes: a free one from the pool, or a new one.
    (define (taken (b Build) (label String) (size I64)) (→ (Pair Build GpuBuffer)) (! gpu)
      (match (table-ref (● b pool) (show size))
        ((Some (Cons buffer rest))
         (new Pair
           (first (Build-pool-set b (table-set (● b pool) (show size) rest)))
           (second buffer)))
        (_
         (let ((buffer (new-buffer (string-append (● b label) "/" label) size)))
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
    ;; with its data; any other from the pool.
    (define (port-given (b Build) (n Node) (port Port)) (→ Build) (! gpu)
      (let ((key (port-key n (● port name))))
        (match (● n kind)
          ((Param name)
           (let ((made (param-buffer-for b name port)))
             (Build-params-set (buffer-set (● made first) key (● made second))
                               (table-set (● b params)
                                          name
                                          (new Binding (buffer (● made second)) (port port))))))
          ((Constant name data)
           (let ((buffer (new-buffer (string-append (● b label) "/" name) (bytes-of port))))
             (write-buffer buffer 0 data)
             (buffer-set (made-buffer b "constant" buffer (bytes-of port)) key buffer)))
          (_
           (let ((pair (taken b key (bytes-of port))))
             (buffer-set (● pair first) key (● pair second)))))))

    ;; A param's buffer: the given one of its name and size, or its own.
    (define (param-buffer-for (b Build) (name String) (port Port))
      (→ (Pair Build GpuBuffer))
      (! gpu)
      (match (table-ref (● b given) name)
        ((Some binding)
         (if (= (bytes-of (● binding port)) (bytes-of port))
             (new Pair (first b) (second (● binding buffer)))
             (panic (string-append "tensor lower: given param " name " has another size"))))
        ((None)
         (let ((buffer (new-buffer (string-append (● b label) "/" name) (bytes-of port))))
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

    (define (dispatched (b Build)
                        (code String)
                        (entry String)
                        (entries (List (Pair I64 GpuBuffer)))
                        (workgroups I64))
      (→ Build)
      (! gpu)
      (if (= workgroups 0)
          b
          (let* ((with (pipeline-for b code entry))
                 (pipeline (● with second))
                 (group (create-bind-group
                         (new BindGroupDescriptor
                           (label (string-append (● b label) "/" entry))
                           (pipeline (ComputePipeline pipeline))
                           (group 0)
                           (entries
                            (map (lambda (e) (BufferEntry (i64->i32 (● e first)) (● e second) 0 0))
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

    (define (pipeline-for (b Build) (code String) (entry String))
      (→ (Pair Build GpuComputePipeline))
      (! gpu)
      (let ((key (string-append entry "#" code)))
        (match (table-ref (● b pipelines) key)
          ((Some pipeline) (new Pair (first b) (second pipeline)))
          ((None)
           (let* ((module (create-shader-module
                           (new ShaderModuleDescriptor (label (● b label)) (code code))))
                  (pipeline (create-compute-pipeline
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
    (define (generated (b Build) (n Node) (code String) (workgroups I64)) (→ Build) (! gpu)
      (dispatched b code "main" (kernel-entries b n) workgroups))

    (define (kernel-entries (b Build) (n Node)) (→ (List (Pair I64 GpuBuffer)))
      (let ((count (length (● n args))))
        (append (filter-map (lambda (pair)
                              (if (fill? (● pair second))
                                  (None)
                                  (Some (new Pair
                                          (first (● pair first))
                                          (second (view-buffer b (● pair second)))))))
                            (zip (iota count) (● n args)))
                (map (lambda (pair)
                       (new Pair
                         (first (+ count (● pair first)))
                         (second (buffer-of b n (● (● pair second) name)))))
                     (zip (iota (length (● n ports))) (● n ports))))))

    ;; Every word of a buffer set to zero.
    (define (zeroed (b Build) (buffer GpuBuffer) (size I64)) (→ Build) (! gpu)
      (dispatched b
                  zero-code
                  "main"
                  (list (new Pair (first 0) (second buffer)))
                  (tiles (quotient size 4) 256)))

    ;; ---- Nodes ----

    ;; Each kind's dispatches, its ports already given buffers.

    (define (node-steps (b Build) (n Node)) (→ Build) (! gpu)
      (let ((out (lambda () (port-of n default-port))) (arg (lambda (k) (list-ref (● n args) k))))
        (match (● n kind)
          ((Param _) b)
          ((Constant _ _) b)
          ((Reduce op axes) (reduce-steps b n op axes))
          ((Place accessor)
           (generated (zeroed b (buffer-of b n default-port) (bytes-of (out)))
                      n
                      (place-code n accessor)
                      (tiles (element-count (arg 0)) 256)))
          ((ScatterAdd _)
           (generated (zeroed b (buffer-of b n default-port) (bytes-of (out)))
                      n
                      (scatter-code n)
                      (tiles (element-count (arg 0)) 256)))
          ((Sort bits) (sort-steps b n bits))
          ((PrefixSum) (scan-steps b n))
          ((CustomKind c) (custom-steps b n c))
          (_ (generated b n (thread-code n) (tiles (product (● (out) shape)) 256))))))

    ;; The keys and values copied into the ports, then sorted there.
    (define (sort-steps (b Build) (n Node) (bits I64)) (→ Build) (! gpu)
      (let* ((keys (buffer-of b n "keys"))
             (values (buffer-of b n "values"))
             (count (element-count (list-ref (● n args) 0)))
             (copied (copied-into (copied-into b (list-ref (● n args) 0) keys)
                                  (list-ref (● n args) 1)
                                  values))
             (sorter (make-sorter (string-append (● b label) "/sort") keys values count bits)))
        (step-added copied (Sorting sorter))))

    (define (scan-steps (b Build) (n Node)) (→ Build) (! gpu)
      (let* ((out (buffer-of b n default-port))
             (scan (make-scan (string-append (● b label) "/scan")
                              out
                              (element-count (list-ref (● n args) 0)))))
        (step-added (copied-into b (list-ref (● n args) 0) out) (Scanning scan))))

    ;; A view's elements written densely into `buffer`.
    (define (copied-into (b Build) (view View) (buffer GpuBuffer)) (→ Build) (! gpu)
      (if (fill? view)
          (dispatched b
                      (copy-code view)
                      "main"
                      (list (new Pair (first 1) (second buffer)))
                      (tiles (element-count view) 256))
          (dispatched b
                      (copy-code view)
                      "main"
                      (list (new Pair (first 0) (second (view-buffer b view)))
                            (new Pair (first 1) (second buffer)))
                      (tiles (element-count view) 256))))

    ;; Every port zeroed, then each kernel over the bindings it uses: the
    ;; arguments first, then the ports.
    (define (custom-steps (b Build) (n Node) (c Custom)) (→ Build) (! gpu)
      (let ((buffers (append (map (lambda (a) (view-buffer b a)) (● n args))
                             (map (lambda (port) (buffer-of b n (● port name))) (● n ports)))))
        (fold-left (lambda (b kernel)
                     (dispatched b
                                 (● kernel code)
                                 (● kernel entry)
                                 (map
                                  (lambda (k) (new Pair (first k) (second (list-ref buffers k))))
                                  (● kernel bindings))
                                 (● kernel workgroups)))
                   (fold-left
                    (lambda (b port) (zeroed b (buffer-of b n (● port name)) (bytes-of port)))
                    b
                    (● n ports))
                   (● c kernels))))

    ;; A reduction over a span of up to 256 elements: a thread an output.
    ;; Over more: a workgroup reduces each part of 4096, and the parts are
    ;; reduced the same way, level by level, until one part is left.
    (define (reduce-steps (b Build) (n Node) (op Reduction) (axes (List I64))) (→ Build) (! gpu)
      (let* ((a (list-ref (● n args) 0))
             (span (product (map (lambda (k) (list-ref (shape-of a) k)) axes)))
             (outputs (product (● (port-of n default-port) shape))))
        (if (<= span 256)
            (generated b n (thread-code n) (tiles outputs 256))
            (reduce-levels b n op outputs span (None)))))

    (define (reduce-levels (b Build)
                           (n Node)
                           (op Reduction)
                           (outputs I64)
                           (span I64)
                           (from (Option GpuBuffer)))
      (→ Build)
      (! gpu)
      (let* ((parts (tiles span 4096))
             (a (list-ref (● n args) 0))
             (code (level-code n op outputs span parts (some? from)))
             (source (match from
                       ((Some buffer) (list (new Pair (first 0) (second buffer))))
                       ((None)
                        (if (fill? a)
                            (Nil)
                            (list (new Pair (first 0) (second (view-buffer b a)))))))))
        (if (= parts 1)
            (dispatched b
                        code
                        "main"
                        (append source
                                (list (new Pair (first 1) (second (buffer-of b n default-port)))))
                        outputs)
            (let* ((pair (taken b "partial" (* 4 (* outputs parts))))
                   (partial (● pair second))
                   (next (dispatched (● pair first)
                                     code
                                     "main"
                                     (append source (list (new Pair (first 1) (second partial))))
                                     (* outputs parts)))
                   (reduced (reduce-levels next n op outputs parts (Some partial))))
              (given-back reduced (* 4 (* outputs parts)) partial)))))

    (define (some? (value (Option GpuBuffer))) (→ Bool)
      (match value
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Sinks and updates ----

    ;; A sink's buffer: its port's when it sees a computed port whole, a
    ;; copy otherwise; and a buffer to read it back through.
    (define (sink-built (state (Pair Build (List Sink))) (view View))
      (→ (Pair Build (List Sink)))
      (! gpu)
      (let* ((b (● state first))
             (size (max 4 (* 4 (element-count view))))
             (direct (and (identity? view)
                          (not (fill? view))
                          (pooled? (● view node kind))
                          (not (● b borrowing))))
             (made (if direct
                       (new Pair (first b) (second (view-buffer b view)))
                       (let ((buffer (new-buffer (string-append (● b label) "/sink") size)))
                         (new Pair
                           (first (copied-into (made-buffer b "sink" buffer size) view buffer))
                           (second buffer)))))
             (readback (create-buffer (new BufferDescriptor
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

    ;; ---- Running ----

    (define (write-param (program Program) (name String) (data Bytes)) (→ Unit) (! gpu)
      (match (table-ref (● program params) name)
        ((Some binding)
         (unless (= (array-length data) (* 4 (product (● binding port shape))))
           (panic (string-append "tensor: param " name " written with the wrong number of bytes")))
         (write-buffer (● binding buffer) 0 data))
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
    (define (encode-steps (pass GpuComputePass) (program Program)) (→ Unit) (! gpu)
      (for-each (lambda (step) (encode-step pass step)) (● program steps)))

    ;; The program's steps in a compute pass of their own, submitted.
    (define (run-program (program Program)) (→ Unit) (! gpu)
      (run-steps (● program steps)))

    (define (run-steps (steps (List Step))) (→ Unit) (! gpu)
      (let* ((encoder (create-command-encoder)) (pass (begin-compute-pass encoder)))
        (for-each (lambda (step) (encode-step pass step)) steps)
        (end-compute-pass pass)
        (submit (list (finish encoder)))))

    (define (encode-step (pass GpuComputePass) (step Step)) (→ Unit) (! gpu)
      (match step
        ((Dispatch pipeline group x y _ _)
         (set-compute-pipeline pass pipeline)
         (set-compute-bind-group pass 0 group)
         (dispatch-workgroups pass (i64->i32 x) (i64->i32 y) 1))
        ((Sorting sorter) (dispatch-sort pass sorter))
        ((Scanning scan) (dispatch-scan pass scan))))

    ;; Sink `k`'s bytes as the last run left them.
    (define (read-sink (program Program) (k I64)) (→ Bytes) (! gpu tasks)
      (let ((sink (list-ref (● program sinks) k)) (encoder (create-command-encoder)))
        (copy-buffer-to-buffer encoder
                               (● sink buffer)
                               0
                               (● sink readback)
                               0
                               (i64->i32 (● sink size)))
        (submit (list (finish encoder)))
        (read-buffer (● sink readback) 0 (i64->i32 (● sink size)))))

    ;; A param's bytes, through a buffer made for the reading.
    (define (read-param (program Program) (name String)) (→ Bytes) (! gpu tasks)
      (match (table-ref (● program params) name)
        ((Some binding)
         (let* ((size (bytes-of (● binding port)))
                (readback (create-buffer (new BufferDescriptor
                                           (label (string-append "read " name))
                                           (size (i64->i32 size))
                                           (usage (list (MapRead) (CopyDst))))))
                (encoder (create-command-encoder)))
           (copy-buffer-to-buffer encoder (● binding buffer) 0 readback 0 (i64->i32 size))
           (submit (list (finish encoder)))
           (let ((data (read-buffer readback 0 (i64->i32 (* 4 (product (● binding port shape)))))))
             (destroy (BufferObject readback))
             data)))
        ((None) (panic (string-append "tensor: the program has no param " name)))))

    (define (release-program (program Program)) (→ Unit) (! gpu)
      (for-each (lambda (step)
                  (match step
                    ((Sorting sorter) (release-sorter sorter))
                    ((Scanning scan) (release-scan scan))
                    (_ (unit))))
                (● program steps))
      (for-each destroy (● program objects)))

    ;; ---- Growing ----

    ;; A copy of every param of a program, made on the device, so a host
    ;; can release the program and lower a larger one before giving the
    ;; params back: two programs' scratch need not fit at once.
    (record Stash
      ((params (Table Binding))))

    (define (stash-params (program Program)) (→ Stash) (! gpu)
      (let* ((encoder (create-command-encoder))
             (copies (map (lambda (name)
                            (match (table-ref (● program params) name)
                              ((Some binding)
                               (let ((copy (new-buffer (string-append "stash/" name)
                                                       (bytes-of (● binding port)))))
                                 (copy-buffer-to-buffer encoder
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
        (submit (list (finish encoder)))
        (new Stash
          (params (fold-left (lambda (t pair) (table-set t (● pair first) (● pair second)))
                             (empty-table)
                             copies)))))

    ;; Each stashed param copied into the program's of the same name, as
    ;; much of it as both hold, and the stash destroyed.
    (define (unstash-params (stash Stash) (program Program)) (→ Unit) (! gpu)
      (let ((encoder (create-command-encoder)))
        (for-each (lambda (name)
                    (match (new Pair
                             (first (table-ref (● stash params) name))
                             (second (table-ref (● program params) name)))
                      ((Pair (Some source) (Some target))
                       (copy-buffer-to-buffer encoder
                                              (● source buffer)
                                              0
                                              (● target buffer)
                                              0
                                              (i64->i32 (min (bytes-of (● source port))
                                                             (bytes-of (● target port))))))
                      (_ (unit))))
                  (table-keys (● stash params)))
        (submit (list (finish encoder)))
        (for-each (lambda (name)
                    (match (table-ref (● stash params) name)
                      ((Some binding) (destroy (BufferObject (● binding buffer))))
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
    (define (profile-program (program Program)) (→ (List (Pair String F64))) (! gpu tasks)
      (concatenate (map timed-steps (groups (● program steps) 2048))))

    (define (groups (items (List T)) (size I64)) (→ (List (List T))) (∀ (T))
      (if (null? items)
          (Nil)
          (Cons (take items (min size (length items)))
                (groups (list-drop items (min size (length items))) size))))

    ;; The steps, each in a timed pass of its own, then their times read.
    (define (timed-steps (steps (List Step))) (→ (List (Pair String F64))) (! gpu tasks)
      (let* ((count (length steps))
             (queries (create-query-set (new QuerySetDescriptor
                                          (label "profile")
                                          (count (i64->i32 (* 2 count))))))
             (writes (map (lambda (k) (step-writes queries k)) (iota count)))
             (encoder (create-command-encoder)))
        (for-each (lambda (pair) (timed-step encoder (● pair first) (● pair second)))
                  (zip writes steps))
        (let ((times (submit-timed encoder queries (i64->i32 (* 2 count)))))
          (destroy (QuerySetObject queries))
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

    (define (timed-step (encoder GpuCommandEncoder) (writes TimestampWrites) (step Step)) (→ Unit)
      (! gpu)
      (let ((pass (begin-timed-compute-pass encoder writes)))
        (encode-step pass step)
        (end-compute-pass pass)))

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
      (let ((count (length (● n args))))
        (string-append
         (string-join (filter-map (lambda (pair)
                                    (if (fill? (● pair second))
                                        (None)
                                        (Some (storage (● pair first)
                                                       (string-append "a" (show (● pair first)))
                                                       "read"
                                                       (etype-wgsl (etype-of (● pair second)))))))
                                  (zip (iota count) (● n args)))
                      "")
         (string-join (map (lambda (pair)
                             (storage (+ count (● pair first))
                                      (● (● pair second) name)
                                      "read_write"
                                      (etype-wgsl (● (● pair second) etype))))
                           (zip (iota (length (● n ports))) (● n ports)))
                      ""))))

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

    ;; Argument `k` of a node at `at`: a literal for a `Fill`.
    (define (load (n Node) (k I64) (at String)) (→ String)
      (let ((a (list-ref (● n args) k)))
        (match (● a node kind)
          ((Fill value) (literal (etype-of a) value))
          (_ (string-append "a" (show k) "[" at "]")))))

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

    ;; A thread an output element: maps, fills, matrix products, gathers
    ;; and small reductions.
    (define (thread-code (n Node)) (→ String)
      (let* ((out (port-of n default-port)) (count (product (● out shape))))
        (thread-kernel (declared n)
                       count
                       (match (● n kind)
                         ((Fill value)
                          (string-append "  out[i] = " (literal (● out etype) value) ";\n"))
                         ((Map body) (string-append "  out[i] = " (body-text n body) ";\n"))
                         ((Matmul) (matmul-text n))
                         ((Gather) (gather-text n))
                         ((Concat axis) (concat-text n axis))
                         ((Reduce op axes) (small-reduce-text n op axes))
                         (_ (panic "tensor lower: no thread kernel for this node"))))))

    (define (operand (n Node) (k I64)) (→ String)
      (load n k (flat-address (● (list-ref (● n args) k) accessor) "i")))

    ;; ---- Map text ----

    ;; A map's body as one WGSL expression of element i: each load its
    ;; argument's element there, through the argument's accessor.
    (define (body-text (n Node) (e Expr)) (→ String)
      (match e
        ((Load k _) (operand n k))
        ((Literal value etype) (literal etype value))
        ((Apply op operands etype)
         (applied-text op
                       (map (lambda (o) (body-text n o)) operands)
                       (expr-etype (list-ref operands 0))
                       etype))))

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
          ((Bitcast _) (string-append "bitcast<" to ">(" a ")")))))

    ;; ---- Matrix and row text ----

    ;; Output (..., r, c) sums a's row r against b's column c.
    (define (matmul-text (n Node)) (→ String)
      (let* ((a (list-ref (● n args) 0))
             (b (list-ref (● n args) 1))
             (shape (● (port-of n default-port) shape))
             (lead (take (indices "i" shape) (- (length shape) 2)))
             (r (list-ref (indices "i" shape) (- (length shape) 2)))
             (c (list-ref (indices "i" shape) (- (length shape) 1)))
             (k (list-ref (shape-of a) (- (length shape) 1))))
        (string-append "  var total = " (etype-wgsl (etype-of a)) "(0);\n"
                       "  for (var m = 0u; m < " (u k) "; m++) {\n"
                       "    total += "
                       (load n 0 (address (● a accessor) (append lead (list r "m"))))
                       " * " (load n 1 (address (● b accessor) (append lead (list "m" c)))) ";\n"
                       "  }\n"
                       "  out[i] = total;\n")))

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

    ;; Element j of output o's span: o's address over the kept axes plus
    ;; j's over the reduced ones.
    (define (span-address (n Node) (axes (List I64)) (o String) (j String)) (→ String)
      (let* ((a (● (list-ref (● n args) 0) accessor))
             (spans (map-indexed (lambda (k size) (if (member? k axes) size 1)) (● a shape)))
             (kept (new Accessor
                     (offset (● a offset))
                     (shape (● (port-of n default-port) shape))
                     (pitch (● a pitch))))
             (reduced (new Accessor (offset 0) (shape spans) (pitch (● a pitch)))))
        (string-append "("
                       (address kept (indices o (● kept shape)))
                       " + "
                       (address reduced (indices j spans))
                       ")")))

    (define (small-reduce-text (n Node) (op Reduction) (axes (List I64))) (→ String)
      (let* ((a (list-ref (● n args) 0))
             (span (product (map (lambda (k) (list-ref (shape-of a) k)) axes))))
        (string-append "  var acc = " (identity-of op (etype-of a)) ";\n"
                       "  for (var j = 0u; j < " (u span) "; j++) {\n"
                       "    acc = "
                       (combine op "acc" (load n 0 (span-address n axes "i" "j")))
                       ";\n"
                       "  }\n"
                       "  out[i] = acc;\n")))

    ;; A workgroup a part of an output's span: each thread combines up to
    ;; 16 elements, then the workgroup's 256 combine pairwise. The first
    ;; level reads the argument; later ones the parts below, densely.
    (define (level-code (n Node) (op Reduction) (outputs I64) (span I64) (parts I64) (partial Bool))
      (→ String)
      (let* ((a (list-ref (● n args) 0))
             (etype (etype-of a))
             (type (etype-wgsl etype))
             (axes (match (● n kind)
                     ((Reduce _ axes) axes)
                     (_ (Nil))))
             (element (if partial
                          (string-append "a0[o * " (u span) " + j]")
                          (load n 0 (span-address n axes "o" "j")))))
        (string-append
         (if (and (not partial) (fill? a)) "" (storage 0 "a0" "read" type))
         (storage 1 "out" "read_write" type)
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
         "      if (j < " (u span) ") { acc = " (combine op "acc" element) "; }\n"
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
