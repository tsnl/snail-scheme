;; Ray queries on the device, which WebGPU lacks: bounding volume
;; hierarchies over a scene's triangles, and kernels that trace queues of
;; rays through them.
;;
;; A `Bvh` has two levels, as hardware ray tracing has them. A bottom
;; level is a tree over one span of triangles: the still triangles in
;; one, and each moving object's in one of its own. The top level is a
;; tree over the bottom levels' roots. `build-bvh` builds every tree on
;; the device, top down by the surface area heuristic (bvh.wgsl.scm), a
;; dispatch a level. `refit-bvh!` follows moving triangles after their
;; vertices change: each moving tree keeps its shape and takes the boxes
;; of its triangles where they are now, and the top level is built again
;; over the roots. The still triangles' tree is never touched again.
;;
;; `make-ray-kernels` makes the queries (rays.wgsl.scm), `intersect` for
;; the nearest hit and `occlude` for any, with the program's `cutout`
;; test in group 1. A queue is a buffer of `Ray`s, 80 bytes each, and its
;; count, a word at a multiple of 256 in a buffer of counts, so the
;; program can append to it with atomics. A query is dispatched over the
;; queue's capacity, and invocations past the count return: an indirect
;; dispatch would launch only what the count needs, but Chromium checks
;; each one's arguments first, which measured about half a millisecond of
;; wall time a dispatch on an RTX 5090, more than the idle workgroups cost.
(define-library (snail shell graphics bvh)
  (export
   Triangles
   TriangleSpan
   BvhBuilder
   make-bvh-builder
   release-bvh-builder
   Bvh
   build-bvh
   refit-bvh!
   release-bvh
   ray-size
   opaque-cutout
   RayKernels
   make-ray-kernels
   ray-group
   trace-rays)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics shaders))
  (begin

    ;; ---- Triangles ----

    ;; A span of a scene's triangles: the first, and how many.
    (record TriangleSpan
      ((first I64)
       (count I64)))

    ;; Triangles as the program holds them: `positions`, read as 32-bit
    ;; floats, with a vertex's x at word `offset` plus `stride` words a
    ;; vertex; three indices a triangle; their count; and the spans that
    ;; move, an object each, in order and together the last triangles.
    (record Triangles
      ((positions GpuBuffer)
       (stride I32)
       (offset I32)
       (indices GpuBuffer)
       (count I64)
       (moving (List TriangleSpan))))

    (define (moving-count (t Triangles)) (→ I64)
      (fold-left (lambda (n span) (+ n (● span count))) 0 (● t moving)))

    ;; The moving spans, parsed: they must tile the last triangles in order,
    ;; since each moving tree's leaves are laid out where its span is.
    (define (checked (t Triangles)) (→ Triangles)
      (let ((end (fold-left (lambda (at span)
                              (unless (and (= at (● span first)) (> (● span count) 0))
                                (panic
                                 "moving triangles must be the last, in nonempty spans in order"))
                              (+ at (● span count)))
                            (- (● t count) (moving-count t))
                            (● t moving))))
        (unless (= end (● t count)) (panic "moving spans run past the triangles"))
        t))

    ;; ---- Slots ----

    ;; Where each tree is. Slot 0 is the top level's root, then come the
    ;; bottom levels' roots, the still triangles' first; then, each from
    ;; an even slot, the top level's nodes, the still tree's and the
    ;; moving trees'. A tree over n primitives has at most n - 1 nodes, two
    ;; slots each. Leaves hold every triangle once, where its span is.
    (record Regions
      ((still I64)
       (roots I64)
       (top-nodes I64)
       (still-nodes I64)
       (moving-nodes I64)
       (slots I64)))

    (define (layout-of (t Triangles)) (→ Regions)
      (let* ((moving (moving-count t))
             (still (- (● t count) moving))
             (roots (+ (if (> still 0) 1 0) (length (● t moving))))
             (top (* 2 (quotient (+ roots 2) 2)))
             (still-nodes (+ top (* 2 roots)))
             (moving-nodes (+ still-nodes (* 2 still))))
        (new Regions
          (still still)
          (roots roots)
          (top-nodes top)
          (still-nodes still-nodes)
          (moving-nodes moving-nodes)
          (slots (+ moving-nodes (* 2 moving))))))

    ;; The first moving tree's root slot.
    (define (first-moving-root (l Regions)) (→ I64) (+ 1 (if (> (● l still) 0) 1 0)))

    ;; ---- Plans ----

    ;; A task as bvh.wgsl.scm stores it: its span of the build's
    ;; primitives, the slot its node fills, its depth, and its centroids'
    ;; bounds, empty for a root, which the device measures.
    (record BvhTask
      ((first I32)
       (count I32)
       (slot I32)
       (depth I32)
       (low Vec4f)
       (high Vec4f))
      (deriving Pod))

    ;; One build's uniform: the level a dispatch splits; its primitives, a
    ;; triangle span or (`instances`) the bottom levels' roots from slot
    ;; `root-base`; where its nodes and leaves go; the most triangles a
    ;; leaf holds; how many levels it may take; the positions' layout; and
    ;; how many tasks a level can hold.
    (record BvhBuild
      ((level I32)
       (primitives I32)
       (first-triangle I32)
       (instances I32)
       (node-base I32)
       (leaf-base I32)
       (root-base I32)
       (most-leaf I32)
       (levels I32)
       (stride I32)
       (offset I32)
       (capacity I32))
      (deriving Pod))

    ;; A refit's uniform: the moving trees' leaves, their roots and their
    ;; nodes, and the first slot that is no root, where a climb stops.
    (record BvhRefit
      ((first-record I32)
       (records I32)
       (first-root I32)
       (roots I32)
       (first-node I32)
       (nodes I32)
       (root-limit I32)
       (pad I32))
      (deriving Pod))

    (define task-shape (→ (Shape BvhTask)) (shape))
    (define build-shape (→ (Shape BvhBuild)) (shape))
    (define refit-shape (→ (Shape BvhRefit)) (shape))

    ;; What one build makes: trees over `primitives` from `first-triangle`,
    ;; or over the bottom levels' roots, one tree from each root task.
    (record Plan
      ((primitives I64)
       (first-triangle I64)
       (instances Bool)
       (node-base I64)
       (leaf-base I64)
       (most-leaf I64)
       (levels I64)
       (roots (List BvhTask))))

    ;; A span's task at depth 0, filling `slot`.
    (define (root-task (first I64) (count I64) (slot I64)) (→ BvhTask)
      (new BvhTask
        (first (i64->i32 first))
        (count (i64->i32 count))
        (slot (i64->i32 slot))
        (depth 0)
        (low (new Vec4f (x 1e30) (y 1e30) (z 1e30) (w 0.0)))
        (high (new Vec4f (x -1e30) (y -1e30) (z -1e30) (w 0.0)))))

    ;; A leaf holds at most four triangles; a bottom level takes at most 40
    ;; levels, which halving reaches leaves within for 2^41 triangles.
    (define (still-plan (l Regions)) (→ Plan)
      (new Plan
        (primitives (● l still))
        (first-triangle 0)
        (instances #f)
        (node-base (● l still-nodes))
        (leaf-base 0)
        (most-leaf 4)
        (levels 40)
        (roots (list (root-task 0 (● l still) 1)))))

    (define (moving-plan (l Regions) (t Triangles)) (→ Plan)
      (new Plan
        (primitives (moving-count t))
        (first-triangle (● l still))
        (instances #f)
        (node-base (● l moving-nodes))
        (leaf-base (● l still))
        (most-leaf 4)
        (levels 40)
        (roots (map-indexed (lambda (i span)
                              (root-task (- (● span first) (● l still))
                                         (● span count)
                                         (+ (first-moving-root l) i)))
                            (● t moving)))))

    ;; The top level's leaves are single roots, and its levels leave the
    ;; heuristic six levels past halving's.
    (define (top-plan (l Regions)) (→ Plan)
      (new Plan
        (primitives (● l roots))
        (first-triangle 0)
        (instances #t)
        (node-base (● l top-nodes))
        (leaf-base 0)
        (most-leaf 1)
        (levels (+ 7 (bits (● l roots))))
        (roots (list (root-task 0 (● l roots) 0)))))

    (define (bits (n I64)) (→ I64) (if (<= n 1) 0 (+ 1 (bits (quotient (+ n 1) 2)))))

    ;; ---- Building ----

    ;; The builder's kernels, made once and shared by every build.
    (record BvhBuilder
      ((measure GpuComputePipeline)
       (split GpuComputePipeline)
       (fill GpuComputePipeline)
       (clear GpuComputePipeline)
       (climb GpuComputePipeline)
       (convert GpuComputePipeline)))

    (define (make-bvh-builder (gpu Gpu)) (→ BvhBuilder)
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor
                        (label "bvh")
                        (code (string-append (declarations build-shape)
                                             (declarations refit-shape)
                                             (declarations task-shape)
                                             bvh-shader)))))
             (kernel (lambda ((entry String)) (→ GpuComputePipeline)
                       (compute-kernel gpu module "bvh" entry)))
             (builder (new BvhBuilder
                        (measure (kernel "measure"))
                        (split (kernel "split"))
                        (fill (kernel "fill"))
                        (clear (kernel "clear"))
                        (climb (kernel "climb"))
                        (convert (kernel "convert")))))
        ((● gpu destroy) (ModuleObject module))
        builder))

    (define (release-bvh-builder (gpu Gpu) (b BvhBuilder)) (→ Unit)
      (for-each (lambda (p) ((● gpu destroy) (ComputePipelineObject p)))
                (list (● b measure) (● b split) (● b fill) (● b clear) (● b climb) (● b convert))))

    ;; Every tree's slots, every leaf triangle, and each node's parent slot.
    (record Trees
      ((slots GpuBuffer)
       (leaves GpuBuffer)
       (parents GpuBuffer)))

    ;; What a build needs while it runs: a uniform a level, the
    ;; primitives' boxes, the spans and tasks of a level and of the next,
    ;; the counts (the nodes made, then each level's tasks), and the groups
    ;; of its kernels. `fill` is the leaves', which a top level has none of.
    (record Run
      ((plan Plan)
       (uniform GpuBuffer)
       (boxes GpuBuffer)
       (refs GpuBuffer)
       (tasks GpuBuffer)
       (counts GpuBuffer)
       (prepare GpuBindGroup)
       (levels (List GpuBindGroup))
       (fill (Option GpuBindGroup))))

    (define (build-of (p Plan) (t Triangles) (level I64)) (→ BvhBuild)
      (new BvhBuild
        (level (i64->i32 level))
        (primitives (i64->i32 (● p primitives)))
        (first-triangle (i64->i32 (● p first-triangle)))
        (instances (if (● p instances) 1 0))
        (node-base (i64->i32 (● p node-base)))
        (leaf-base (i64->i32 (● p leaf-base)))
        (root-base 1)
        (most-leaf (i64->i32 (● p most-leaf)))
        (levels (i64->i32 (● p levels)))
        (stride (● t stride))
        (offset (● t offset))
        (capacity (i64->i32 (max 1 (● p primitives))))))

    (define (run-for (gpu Gpu) (b BvhBuilder) (trees Trees) (t Triangles) (p Plan)) (→ Run)
      (let* ((n (max 1 (● p primitives)))
             (uniform (uniform-buffer gpu "bvh/build"
                                      (uniform-slots build-shape
                                                     (map (lambda (level) (build-of p t level))
                                                          (iota (● p levels))))))
             (boxes (storage-buffer gpu "bvh/boxes" (* 32 n) (Nil)))
             (refs (storage-buffer gpu "bvh/refs" (* 8 n) (Nil)))
             (tasks
              (storage-buffer gpu "bvh/tasks" (* 2 (* (stride task-shape) n)) (list (CopyDst))))
             (counts (storage-buffer gpu "bvh/counts" (* 4 (+ 2 (● p levels))) (list (CopyDst))))
             (group
              (lambda ((kernel GpuComputePipeline) (level I64) (entries (List BindGroupEntry)))
                (→ GpuBindGroup)
                (kernel-group gpu kernel 0 "bvh" (Cons (slot-entry 0 uniform level) entries))))
             (vertices (list (BufferEntry 8 (● t positions) 0 0) (BufferEntry 9 (● t indices) 0 0)))
             (split-entries (list (BufferEntry 1 boxes 0 0) (BufferEntry 2 refs 0 0)
                                  (BufferEntry 3 tasks 0 0) (BufferEntry 4 counts 0 0)
                                  (BufferEntry 5 (● trees slots) 0 0)
                                  (BufferEntry 6 (● trees leaves) 0 0)
                                  (BufferEntry 7 (● trees parents) 0 0))))
        (new Run
          (plan p)
          (uniform uniform)
          (boxes boxes)
          (refs refs)
          (tasks tasks)
          (counts counts)
          (prepare (group (● b measure) 0
                          (append (list (BufferEntry 1 boxes 0 0) (BufferEntry 2 refs 0 0)
                                        (BufferEntry 5 (● trees slots) 0 0))
                                  vertices)))
          (levels (map (lambda (level) (group (● b split) level split-entries))
                       (iota (● p levels))))
          (fill (if (● p instances) (None)
                    (Some
                     (group (● b fill) 0 (Cons (BufferEntry 6 (● trees leaves) 0 0) vertices))))))))

    ;; The run's first level: no nodes made yet, and the plan's roots as
    ;; its tasks. Written before the run is encoded, and again for each
    ;; rebuild of the top level.
    (define (restart! (gpu Gpu) (r Run)) (→ Unit)
      (let ((roots (● r plan roots)) (levels (● r plan levels)))
        ((● gpu write-buffer) (● r counts) 0
         (pack (shape)
               (append (list (ann 0 I32) (i64->i32 (length roots)))
                       (map (lambda (_) (ann 0 I32)) (iota levels)))))
        ((● gpu write-buffer) (● r tasks) 0 (pack task-shape roots))))

    ;; The boxes, a split a level, then the leaves' triangles.
    (define (encode-run (gpu Gpu) (b BvhBuilder) (pass GpuComputePass) (r Run)) (→ Unit)
      (let ((n (● r plan primitives)))
        ((● gpu set-compute-pipeline) pass (● b measure))
        ((● gpu set-compute-bind-group) pass 0 (● r prepare))
        (dispatch-items gpu pass n 256)
        ((● gpu set-compute-pipeline) pass (● b split))
        (for-each (lambda (group)
                    ((● gpu set-compute-bind-group) pass 0 group)
                    ((● gpu dispatch-workgroups)
                     pass
                     (i64->i32 (max 1 (min 1024 (quotient n 2))))
                     1
                     1))
                  (● r levels))
        (match (● r fill)
          ((Some group) ((● gpu set-compute-pipeline) pass (● b fill))
           ((● gpu set-compute-bind-group) pass 0 group)
           (dispatch-items gpu pass n 256))
          ((None) (unit)))))

    (define (release-run (gpu Gpu) (r Run)) (→ Unit)
      (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer)))
                (list (● r uniform) (● r boxes) (● r refs) (● r tasks) (● r counts)))
      (for-each (lambda (group) ((● gpu destroy) (BindGroupObject group)))
                (append (Cons (● r prepare) (● r levels))
                        (match (● r fill) ((Some g) (list g)) ((None) (Nil))))))

    ;; A plan built and submitted; its run, which the caller lets go or
    ;; keeps to build again.
    (define (built (gpu Gpu) (b BvhBuilder) (trees Trees) (t Triangles) (p Plan)) (→ Run)
      (let* ((r (run-for gpu b trees t p))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-compute-pass) encoder)))
        (restart! gpu r)
        (encode-run gpu b pass r)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        r))

    ;; ---- The hierarchy ----

    ;; Its trees and the triangles they are over; and, where some move, what
    ;; a refit needs.
    (record Bvh
      ((trees Trees)
       (triangles Triangles)
       (motion (Option Motion))))

    ;; A refit's uniform and groups; the moving trees' boxes as they merge;
    ;; the moving build's leaf fill, kept; and the top level's run, which
    ;; every refit builds again.
    (record Motion
      ((builder BvhBuilder)
       (refit GpuBuffer)
       (merged GpuBuffer)
       (leaves Run)
       (top Run)
       (clear GpuBindGroup)
       (climb GpuBindGroup)
       (convert GpuBindGroup)
       (records I64)
       (slots I64)))

    ;; The still triangles' tree, each moving object's, and the top level
    ;; over them, on the device.
    (define (build-bvh (gpu Gpu) (b BvhBuilder) (given Triangles)) (→ Bvh)
      (let* ((t (checked given))
             (l (layout-of t))
             (trees (new Trees
                      (slots (storage-buffer gpu "bvh/slots" (* 32 (● l slots)) (Nil)))
                      (leaves (storage-buffer gpu "bvh/triangles" (* 48 (max 1 (● t count))) (Nil)))
                      (parents (storage-buffer gpu
                                               "bvh/parents"
                                               (* 4 (+ 1 (quotient (● l slots) 2)))
                                               (Nil))))))
        (when (> (● l still) 0) (release-run gpu (built gpu b trees t (still-plan l))))
        (if (null? (● t moving))
            (begin (release-run gpu (built gpu b trees t (top-plan l)))
                   (new Bvh (trees trees) (triangles t) (motion (None))))
            (let* ((leaves (built gpu b trees t (moving-plan l t)))
                   (top (built gpu b trees t (top-plan l))))
              (new Bvh
                (trees trees)
                (triangles t)
                (motion (Some (motion-of gpu b trees t l leaves top))))))))

    (define (motion-of (gpu Gpu) (b BvhBuilder) (trees Trees) (t Triangles) (l Regions)
                       (leaves Run) (top Run))
      (→ Motion)
      (let* ((roots (length (● t moving)))
             (records (moving-count t))
             (refit (uniform-buffer gpu "bvh/refit"
                                    (pod-bytes refit-shape
                                               (new BvhRefit
                                                 (first-record (i64->i32 (● l still)))
                                                 (records (i64->i32 records))
                                                 (first-root (i64->i32 (first-moving-root l)))
                                                 (roots (i64->i32 roots))
                                                 (first-node (i64->i32 (● l moving-nodes)))
                                                 (nodes (i64->i32 (* 2 records)))
                                                 (root-limit (i64->i32 (+ 1 (● l roots))))
                                                 (pad 0)))))
             (merged (storage-buffer gpu "bvh/merged" (* 24 (● l slots)) (Nil)))
             (group (lambda ((kernel GpuComputePipeline) (entries (List BindGroupEntry)))
                      (→ GpuBindGroup)
                      (kernel-group gpu kernel 0 "bvh/refit"
                                    (append
                                     (list (BufferEntry 11 refit 0 0) (BufferEntry 10 merged 0 0))
                                     entries)))))
        (new Motion
          (builder b)
          (refit refit)
          (merged merged)
          (leaves leaves)
          (top top)
          (clear (group (● b clear) (Nil)))
          (climb (group (● b climb) (list (BufferEntry 6 (● trees leaves) 0 0)
                                          (BufferEntry 7 (● trees parents) 0 0))))
          (convert (group (● b convert) (list (BufferEntry 5 (● trees slots) 0 0))))
          (records records)
          (slots (+ roots (* 2 records))))))

    ;; After the moving vertices change and before any draw or ray query:
    ;; the moving leaves' corners read again, their trees' boxes merged
    ;; anew, and the top level built again over the roots. A hierarchy
    ;; with nothing moving has nothing to refit.
    (define (refit-bvh! (gpu Gpu) (bvh Bvh)) (→ Unit)
      (match (● bvh motion)
        ((Some m)
         (let* ((b (● m builder))
                (encoder ((● gpu create-command-encoder)))
                (pass ((● gpu begin-compute-pass) encoder))
                (over
                 (lambda ((kernel GpuComputePipeline) (group GpuBindGroup) (count I64)) (→ Unit)
                   ((● gpu set-compute-pipeline) pass kernel)
                   ((● gpu set-compute-bind-group) pass 0 group)
                   (dispatch-items gpu pass count 256))))
           (restart! gpu (● m top))
           (match (● m leaves fill)
             ((Some group) (over (● b fill) group (● m records)))
             ((None) (unit)))
           (over (● b clear) (● m clear) (● m slots))
           (over (● b climb) (● m climb) (● m records))
           (over (● b convert) (● m convert) (● m slots))
           (encode-run gpu b pass (● m top))
           ((● gpu end-compute-pass) pass)
           ((● gpu submit) (list ((● gpu finish) encoder)))))
        ((None) (unit))))

    ;; Its trees and what a refit keeps; the triangles are their owner's.
    (define (release-bvh (gpu Gpu) (bvh Bvh)) (→ Unit)
      (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer)))
                (list (● bvh trees slots) (● bvh trees leaves) (● bvh trees parents)))
      (match (● bvh motion)
        ((Some m)
         (release-run gpu (● m leaves))
         (release-run gpu (● m top))
         (for-each (lambda (group) ((● gpu destroy) (BindGroupObject group)))
                   (list (● m clear) (● m climb) (● m convert)))
         (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer)))
                   (list (● m refit) (● m merged))))
        ((None) (unit))))

    ;; ---- Queries ----

    (define ray-size (→ I64) 80)

    ;; A `cutout` for triangles that are all opaque.
    (define opaque-cutout
      (→ String)
      "fn cutout(triangle: u32, barycentric: vec2f, seed: ptr<function, u32>) -> bool { return false; }\n")

    (record RayKernels
      ((intersect GpuComputePipeline)
       (occlude GpuComputePipeline)))

    ;; The queries with `cutout`, WGSL that defines the function and
    ;; declares what it reads in group 1.
    (define (make-ray-kernels (gpu Gpu) (cutout String)) (→ RayKernels)
      (let ((module ((● gpu create-shader-module) (new ShaderModuleDescriptor
                                                    (label "rays")
                                                    (code (string-append cutout rays-shader))))))
        (new RayKernels
          (intersect (compute-kernel gpu module "rays" "intersect"))
          (occlude (compute-kernel gpu module "rays" "occlude")))))

    ;; Group 0 of `query`, one of the kernels' pipelines, over the BVH and
    ;; a queue: its rays, and its count at byte `count-at` of `counts`.
    (define (ray-group (gpu Gpu) (query GpuComputePipeline)
                       (bvh Bvh)
                       (rays GpuBuffer)
                       (counts GpuBuffer)
                       (count-at I32))
      (→ GpuBindGroup)
      (kernel-group gpu query
                    0
                    "rays"
                    (list (BufferEntry 0 (● bvh trees slots) 0 0)
                          (BufferEntry 1 (● bvh trees leaves) 0 0)
                          (BufferEntry 4 rays 0 0)
                          (BufferEntry 5 counts count-at 4))))

    ;; A query over a queue that holds at most `capacity` rays; `cutout`
    ;; is its group 1, if it has one.
    (define (trace-rays (gpu Gpu) (pass GpuComputePass)
                        (query GpuComputePipeline)
                        (rays GpuBindGroup)
                        (cutout (Option GpuBindGroup))
                        (capacity I64))
      (→ Unit)
      ((● gpu set-compute-pipeline) pass query)
      ((● gpu set-compute-bind-group) pass 0 rays)
      (match cutout
        ((Some group) ((● gpu set-compute-bind-group) pass 1 group))
        ((None) (unit)))
      (dispatch-items gpu pass capacity 64))

    ))
