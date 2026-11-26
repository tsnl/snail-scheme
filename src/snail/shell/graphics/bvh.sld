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
    ;; leaf holds; how many levels it may take; the positions' layout; how
    ;; many tasks a level can hold; and how many levels split wide tasks
    ;; across the device.
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
       (capacity I32)
       (wide-levels I32))
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

    ;; The builder's kernels, made once and shared by every build: the
    ;; steps of a level's wide tasks in their order, after the others.
    (record BvhBuilder
      ((measure GpuComputePipeline)
       (split GpuComputePipeline)
       (fill GpuComputePipeline)
       (clear GpuComputePipeline)
       (climb GpuComputePipeline)
       (convert GpuComputePipeline)
       (wide-reset GpuComputePipeline)
       (wide-bound GpuComputePipeline)
       (wide-steps (List GpuComputePipeline))))

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
                        (convert (kernel "convert"))
                        (wide-reset (kernel "wide_reset"))
                        (wide-bound (kernel "wide_bound"))
                        (wide-steps (map kernel
                                         (list "wide_bin" "wide_choose" "wide_count" "wide_scan"
                                               "wide_scatter" "wide_branch"))))))
        ((● gpu destroy) (ModuleObject module))
        builder))

    (define (release-bvh-builder (gpu Gpu) (b BvhBuilder)) (→ Unit)
      (for-each (lambda (p) ((● gpu destroy) (ComputePipelineObject p)))
                (append (list (● b measure) (● b split) (● b fill) (● b clear) (● b climb)
                              (● b convert) (● b wide-reset) (● b wide-bound))
                        (● b wide-steps))))

    ;; Every tree's slots, every leaf triangle, and each node's parent slot.
    (record Trees
      ((slots GpuBuffer)
       (leaves GpuBuffer)
       (parents GpuBuffer)))

    ;; A dispatch of a build: a kernel over `items` invocations, `size` a
    ;; workgroup, with its group.
    (record Step
      ((kernel GpuComputePipeline)
       (group GpuBindGroup)
       (items I64)
       (size I64)))

    (define (dispatch-step (gpu Gpu) (pass GpuComputePass) (step Step)) (→ Unit)
      ((● gpu set-compute-pipeline) pass (● step kernel))
      ((● gpu set-compute-bind-group) pass 0 (● step group))
      (dispatch-items gpu pass (● step items) (● step size)))

    ;; What a build needs while it runs, and its steps: the boxes; for each
    ;; level its wide tasks' steps, the first levels', then its split; and
    ;; the leaves' triangles, which a top level has none of and a refit runs
    ;; again. `restart!` writes the counts (the nodes made, each level's
    ;; tasks, then each level's wide tasks), the roots and the wide roots.
    (record Run
      ((plan Plan)
       (buffers (List GpuBuffer))
       (counts GpuBuffer)
       (tasks GpuBuffer)
       (widened GpuBuffer)
       (steps (List Step))
       (fill (Option Step))))

    ;; A wide task has more primitives than this (bvh.wgsl.scm's WIDE). The
    ;; first levels split wide tasks across the device, enough of them for
    ;; the halvings from the build's span to WIDE's, and three more for
    ;; uneven splits; a wide task below them is split as any other.
    (define wide (→ I64) 4096)

    (define (wide-levels (p Plan)) (→ I64)
      (if (<= (● p primitives) wide) 0
          (min (● p levels) (+ 3 (bits (quotient (● p primitives) wide))))))

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
        (capacity (i64->i32 (max 1 (● p primitives))))
        (wide-levels (i64->i32 (wide-levels p)))))

    (define (run-for (gpu Gpu) (b BvhBuilder) (trees Trees) (t Triangles) (p Plan)) (→ Run)
      (let* ((n (max 1 (● p primitives)))
             (most-wide (+ 1 (quotient n wide)))
             (uniform (uniform-buffer gpu "bvh/build"
                                      (uniform-slots build-shape
                                                     (map (lambda (level) (build-of p t level))
                                                          (iota (● p levels))))))
             (storage (lambda ((label String) (size I64)) (→ GpuBuffer)
                        (storage-buffer gpu label size (list (CopyDst)))))
             (boxes (storage "bvh/boxes" (* 32 n)))
             (refs (storage "bvh/refs" (* 8 n)))
             (tasks (storage "bvh/tasks" (* 2 (* (stride task-shape) n))))
             (counts (storage "bvh/counts" (* 4 (+ 2 (* 2 (● p levels))))))
             (widened (storage "bvh/widened" (* 8 most-wide)))
             (merged (storage "bvh/wide" (* 4 (* 354 most-wide))))
             (decided (storage "bvh/decided" (* 48 most-wide)))
             (lefts (storage "bvh/lefts" (* 4 (* most-wide (+ 1 (quotient n 1024))))))
             (entry (lambda ((binding I32) (buffer GpuBuffer)) (→ BindGroupEntry)
                      (BufferEntry binding buffer 0 0)))
             (step (lambda ((kernel GpuComputePipeline) (level I64) (bindings (List BindGroupEntry))
                            (items I64) (size I64))
                     (→ Step)
                     (new Step
                       (kernel kernel)
                       (group (kernel-group gpu kernel 0 "bvh"
                                            (Cons (slot-entry 0 uniform level) bindings)))
                       (items items)
                       (size size))))
             (vertices (list (entry 8 (● t positions)) (entry 9 (● t indices))))
             (span (list (entry 1 boxes) (entry 2 refs) (entry 3 tasks) (entry 4 counts)
                         (entry 12 widened)))
             (wide-of (lambda ((index I64)) (→ (List BindGroupEntry))
                        (list-ref (list (Cons (entry 13 merged) span)
                                        (list (entry 3 tasks)
                                              (entry 4 counts)
                                              (entry 5 (● trees slots))
                                              (entry 7 (● trees parents)) (entry 12 widened)
                                              (entry 13 merged) (entry 14 decided))
                                        (append span (list (entry 13 merged) (entry 14 decided)
                                                           (entry 15 lefts)))
                                        (list (entry 3 tasks) (entry 4 counts) (entry 12 widened)
                                              (entry 15 lefts))
                                        (append span (list (entry 13 merged) (entry 14 decided)
                                                           (entry 15 lefts)))
                                        (list (entry 3 tasks) (entry 4 counts) (entry 12 widened)
                                              (entry 13 merged) (entry 14 decided)))
                                  index)))
             (workgroups (lambda ((groups I64)) (→ I64) (* 256 (max 1 (min 1024 groups)))))
             (wide-items (list (workgroups (quotient n 1024)) (workgroups most-wide)
                               (workgroups (quotient n 1024)) most-wide
                               (workgroups (quotient n 1024)) (workgroups most-wide)))
             (split-entries (append span
                                    (list (entry 5 (● trees slots)) (entry 6 (● trees leaves))
                                          (entry 7 (● trees parents)))))
             (level-steps
              (lambda ((level I64)) (→ (List Step))
                (append (if (< level (wide-levels p))
                            (append (if (= level 0)
                                        (list (step (● b wide-bound) 0 (Cons (entry 13 merged) span)
                                                    (workgroups (quotient n 1024)) 256))
                                        (Nil))
                                    (map (lambda (k)
                                           (step (list-ref (● b wide-steps) k) level (wide-of k)
                                                 (list-ref wide-items k) 256))
                                         (iota 6)))
                            (Nil))
                        (list
                         (step (● b split) level split-entries (workgroups (quotient n 2)) 256))))))
        (new Run
          (plan p)
          (buffers (list uniform boxes refs tasks counts widened merged decided lefts))
          (counts counts)
          (tasks tasks)
          (widened widened)
          (steps (append (Cons (step (● b measure) 0
                                     (append (list (entry 1 boxes) (entry 2 refs)
                                                   (entry 5 (● trees slots)))
                                             vertices)
                                     n 256)
                               (if (> (wide-levels p) 0)
                                   (list (step (● b wide-reset) 0 (list (entry 13 merged))
                                               (* 354 most-wide) 256))
                                   (Nil)))
                         (concatenate (map level-steps (iota (● p levels))))))
          (fill (if (● p instances) (None)
                    (Some (step (● b fill) 0 (Cons (entry 6 (● trees leaves)) vertices) n 256)))))))

    ;; The run's first level: no nodes made yet, the plan's roots as its
    ;; tasks, and those of them that are wide on its wide list. Written
    ;; before the run is encoded, and again for each rebuild of the top
    ;; level.
    (define (restart! (gpu Gpu) (r Run)) (→ Unit)
      (let* ((roots (● r plan roots)) (levels (● r plan levels))
             (wide-roots (if (> (wide-levels (● r plan)) 0)
                             (filter (lambda (k) (> (i32->i64 (● (list-ref roots k) count)) wide))
                                     (iota (length roots)))
                             (Nil)))
             (zeros (lambda ((n I64)) (→ (List I32)) (map (lambda (_) (ann 0 I32)) (iota n)))))
        ((● gpu write-buffer) (● r counts) 0
         (pack (shape)
               (concatenate (list (list (ann 0 I32) (i64->i32 (length roots)))
                                  (zeros levels)
                                  (list (i64->i32 (length wide-roots)))
                                  (zeros (- levels 1))))))
        ((● gpu write-buffer) (● r tasks) 0 (pack task-shape roots))
        (unless (null? wide-roots)
          ((● gpu write-buffer) (● r widened) 0 (pack (shape) (map i64->i32 wide-roots))))))

    ;; The run's steps, then its leaves'.
    (define (encode-run (gpu Gpu) (pass GpuComputePass) (r Run)) (→ Unit)
      (for-each (lambda (step) (dispatch-step gpu pass step)) (● r steps))
      (match (● r fill)
        ((Some step) (dispatch-step gpu pass step))
        ((None) (unit))))

    (define (release-run (gpu Gpu) (r Run)) (→ Unit)
      (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer))) (● r buffers))
      (for-each (lambda (step) ((● gpu destroy) (BindGroupObject (● step group))))
                (append (● r steps) (match (● r fill) ((Some f) (list f)) ((None) (Nil))))))

    ;; A plan built and submitted; its run, which the caller lets go or
    ;; keeps to build again.
    (define (built (gpu Gpu) (b BvhBuilder) (trees Trees) (t Triangles) (p Plan)) (→ Run)
      (let* ((r (run-for gpu b trees t p))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-compute-pass) encoder)))
        (restart! gpu r)
        (encode-run gpu pass r)
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
             ((Some step) (dispatch-step gpu pass step))
             ((None) (unit)))
           (over (● b clear) (● m clear) (● m slots))
           (over (● b climb) (● m climb) (● m records))
           (over (● b convert) (● m convert) (● m slots))
           (encode-run gpu pass (● m top))
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
