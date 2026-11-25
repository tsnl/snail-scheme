;; Ray queries on the device, which WebGPU lacks: a bounding volume
;; hierarchy over any triangles, and kernels that trace queues of rays
;; through it.
;;
;; `build-bvh` builds it once, in one compute pass (bvh.wgsl.scm): Morton
;; codes of the triangles' centroids, a bitonic sort of them, the tree
;; from the sorted codes, and its boxes refit from the leaves up, then
;; packed so each node holds both its children's boxes. What the build
;; needs only while it runs, the keys, the sort's steps and the binary
;; tree, goes when it is submitted.
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
   Bvh
   build-bvh
   build-moving-bvh
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

    ;; Triangles as the program holds them: `positions`, read as 32-bit
    ;; floats, with a vertex's x at word `offset` plus `stride` words a
    ;; vertex; three indices a triangle; their count; and their box.
    (record Triangles
      ((positions GpuBuffer)
       (stride I32)
       (offset I32)
       (indices GpuBuffer)
       (count I64)
       (low (List F64))
       (high (List F64))))

    ;; Where positions are, for the queries' uniform.
    (record BvhLayout
      ((shape Vec4i))
      (deriving Pod))

    (define layout-shape (→ (Shape BvhLayout)) (shape))

    ;; Its nodes, 64 bytes each, n - 1 of them for n triangles (one for a
    ;; lone triangle), the root at 0; the triangles; and the queries'
    ;; uniform.
    (record Bvh
      ((nodes GpuBuffer)
       (triangles Triangles)
       (layout GpuBuffer)
       (refitter (Option Refitter))))

    ;; A moving mesh keeps its sorted leaf order and binary tree. The query
    ;; bindings keep pointing to the same packed nodes after every refit.
    (record RefitStep
      ((pipeline GpuComputePipeline)
       (group GpuBindGroup)
       (count I64)))

    (record Refitter
      ((leaves RefitStep)
       (to-spare RefitStep)
       (to-nodes RefitStep)
       (pack RefitStep)
       (rounds I64)
       (buffers (List GpuBuffer))))

    ;; ---- Building ----

    ;; The triangles' box; then n, the padded count and a sort step's j
    ;; and k; then the positions' stride and offset.
    (record BvhBuild
      ((low Vec4f)
       (high Vec4f)
       (counts Vec4i)
       (words Vec4i))
      (deriving Pod))

    (define build-shape (→ (Shape BvhBuild)) (shape))

    ;; Its nodes and uniform; the triangles are their owner's.
    (define (release-bvh (gpu Gpu) (bvh Bvh)) (→ Unit)
      ((● gpu destroy) (BufferObject (● bvh nodes)))
      ((● gpu destroy) (BufferObject (● bvh layout)))
      (match (● bvh refitter)
        ((Some r)
         (for-each (lambda (s) ((● gpu destroy) (BindGroupObject (● s group))))
                   (list (● r leaves) (● r to-spare) (● r to-nodes) (● r pack)))
         (for-each (lambda (p) ((● gpu destroy) (ComputePipelineObject p)))
                   (list (● r leaves pipeline)
                         (● r to-spare pipeline)
                         (● r pack pipeline)))
         (for-each (lambda (b) ((● gpu destroy) (BufferObject b))) (● r buffers)))
        (_ (unit))))



    (define (build-bvh (gpu Gpu) (triangles Triangles)) (→ Bvh)
      (build-tree gpu triangles #f))

    (define (build-moving-bvh (gpu Gpu) (triangles Triangles)) (→ Bvh)
      (build-tree gpu triangles #t))

    (define (build-tree (gpu Gpu) (triangles Triangles) (moving Bool)) (→ Bvh)
      (let* ((n (max 1 (● triangles count)))
             (padded (power-of-two-at-least (max 2 n)))
             (steps (sort-steps padded))
             (build (uniforms gpu triangles n padded steps))
             (keys (storage-buffer gpu "bvh/keys" (* 4 padded) (Nil)))
             (order (storage-buffer gpu "bvh/order" (* 4 padded) (Nil)))
             (positions (● triangles positions))
             (indices (● triangles indices))
             (nodes (storage-buffer gpu "bvh/nodes" (* 32 (- (* 2 n) 1)) (Nil)))
             (spare (storage-buffer gpu "bvh/spare" (* 32 (- (* 2 n) 1)) (Nil)))
             (wide (storage-buffer gpu "bvh/wide" (* 64 (max 1 (- n 1))) (Nil)))
             (module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor
                        (label "bvh")
                        (code (string-append (declarations build-shape) bvh-shader)))))
             (kernels (new Kernels
                        (pipelines (pipelines-of gpu module))
                        (build build)
                        (encoder ((● gpu create-command-encoder))))))
        ((● gpu destroy) (ModuleObject module))
        (let ((pass ((● gpu begin-compute-pass) (● kernels encoder))))
          (run gpu kernels
               pass
               "morton"
               0
               padded
               (list (buffer 1 keys) (buffer 2 order) (buffer 3 positions) (buffer 4 indices)))
          (for-each (lambda (step)
                      (run gpu kernels
                           pass
                           "sort_step"
                           (+ 1 step)
                           (quotient padded 2)
                           (list (buffer 1 keys) (buffer 2 order))))
                    (iota (length steps)))
          (run gpu kernels
               pass
               "build_leaves"
               0
               n
               (list (buffer 2 order) (buffer 3 positions) (buffer 4 indices) (buffer 5 nodes)))
          (run gpu kernels pass "build_internal" 0 (- n 1) (list (buffer 1 keys) (buffer 5 nodes)))
          (for-each (lambda (refit)
                      (let ((from (if (= (remainder refit 2) 0) nodes spare))
                            (to (if (= (remainder refit 2) 0) spare nodes)))
                        (run gpu kernels
                             pass
                             "refit"
                             0
                             (- (* 2 n) 1)
                             (list (buffer 5 to) (buffer 6 from)))))
                    (iota (refits n)))
          (run gpu kernels pass "pack" 0 (max 1 (- n 1)) (list (buffer 6 nodes) (buffer 7 wide)))
          ((● gpu end-compute-pass) pass))
        ((● gpu submit) (list ((● gpu finish) (● kernels encoder))))
        (let ((retained (list build order nodes spare)))
          ((● gpu destroy) (BufferObject keys))
          (unless moving
            (for-each (lambda (b) ((● gpu destroy) (BufferObject b))) retained))
          (for-each (lambda (named)
                      (unless (and moving
                                   (member? (● named first) (list "build_leaves" "refit" "pack")))
                        ((● gpu destroy) (ComputePipelineObject (● named second)))))
                    (● kernels pipelines))
          (new Bvh (nodes wide) (triangles triangles) (layout (layout-of gpu triangles))
               (refitter
                (if moving
                    (Some (new Refitter
                            (buffers retained)
                            (rounds (quotient (refits n) 2))
                            (leaves (refit-step gpu kernels "build_leaves" n
                                                (list (buffer 2 order) (buffer 3 positions)
                                                      (buffer 4 indices) (buffer 5 nodes))))
                            (to-spare (refit-step gpu kernels "refit" (- (* 2 n) 1)
                                                  (list (buffer 5 spare) (buffer 6 nodes))))
                            (to-nodes (refit-step gpu kernels "refit" (- (* 2 n) 1)
                                                  (list (buffer 5 nodes) (buffer 6 spare))))
                            (pack (refit-step gpu kernels "pack" (max 1 (- n 1))
                                              (list (buffer 6 nodes) (buffer 7 wide))))))
                    (None)))))))

    (define (refit-step (gpu Gpu)
                        (k Kernels)
                        (entry String)
                        (count I64)
                        (entries (List BindGroupEntry)))
      (→ RefitStep)
      (let ((pipeline (match (assoc-ref (● k pipelines) entry) ((Some p) p) (_ (panic entry)))))
        (new RefitStep (pipeline pipeline) (count count)
             (group
              (kernel-group gpu pipeline 0 entry (Cons (slot-entry 0 (● k build) 0) entries))))))

    (define (dispatch-refit (gpu Gpu) (pass GpuComputePass) (step RefitStep)) (→ Unit)
      ((● gpu set-compute-pipeline) pass (● step pipeline))
      ((● gpu set-compute-bind-group) pass 0 (● step group))
      (dispatch-items gpu pass (● step count) 256))

    ;; Refit after the vertex writes and before any draw or ray query.
    (define (refit-bvh! (gpu Gpu) (bvh Bvh)) (→ Unit)
      (let* ((r (match (● bvh refitter) ((Some r) r) (_ (panic "refit requires a moving BVH"))))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-compute-pass) encoder)))
        (dispatch-refit gpu pass (● r leaves))
        (for-each (lambda (_) (dispatch-refit gpu pass (● r to-spare))
                          (dispatch-refit gpu pass (● r to-nodes))) (iota (● r rounds)))
        (dispatch-refit gpu pass (● r pack))
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))))

    (define (layout-of (gpu Gpu) (triangles Triangles)) (→ GpuBuffer)
      (uniform-buffer gpu "bvh/layout"
                      (pod-bytes layout-shape (new BvhLayout (shape (positions-of triangles))))))

    (define (positions-of (triangles Triangles)) (→ Vec4i)
      (new Vec4i (x (● triangles stride)) (y (● triangles offset)) (z 0) (w 0)))

    ;; What each dispatch shares: a pipeline for each entry, the uniforms,
    ;; and the encoder of the one pass.
    (record Kernels
      ((pipelines (List (Pair String GpuComputePipeline)))
       (build GpuBuffer)
       (encoder GpuCommandEncoder)))

    (define (pipelines-of (gpu Gpu) (module GpuShaderModule))
      (→ (List (Pair String GpuComputePipeline)))
      (map
       (lambda (entry) (new Pair (first entry) (second (compute-kernel gpu module "bvh" entry))))
       (list "morton" "sort_step" "build_leaves" "build_internal" "refit" "pack")))

    ;; One dispatch of `entry` over `count` items with the uniforms of slot
    ;; `uniform` and `entries`; its group goes at the submit.
    (define (run (gpu Gpu) (kernels Kernels)
                 (pass GpuComputePass)
                 (entry String)
                 (uniform I64)
                 (count I64)
                 (entries (List BindGroupEntry)))
      (→ Unit)
      (let* ((pipeline (match (assoc-ref (● kernels pipelines) entry)
                         ((Some pipeline) pipeline)
                         ((None) (panic (string-append "bvh: no kernel " entry)))))
             (group (kernel-group gpu pipeline
                                  0
                                  (string-append "bvh/" entry)
                                  (Cons (slot-entry 0 (● kernels build) uniform) entries))))
        (when (> count 0)
          ((● gpu set-compute-pipeline) pass pipeline)
          ((● gpu set-compute-bind-group) pass 0 group)
          (dispatch-items gpu pass count 256))
        ((● gpu destroy) (BindGroupObject group))))

    (define (buffer (binding I32) (b GpuBuffer)) (→ BindGroupEntry) (BufferEntry binding b 0 0))

    ;; Slot 0 for every kernel but the sort, then a slot for each of its
    ;; steps.
    (define (uniforms (gpu Gpu)
                      (triangles Triangles)
                      (n I64)
                      (padded I64)
                      (steps (List (Pair I64 I64))))
      (→ GpuBuffer)
      (uniform-buffer gpu "bvh/build"
                      (uniform-slots build-shape
                                     (map (lambda (step) (build-of triangles n padded step))
                                          (Cons (new Pair (first 0) (second 0)) steps)))))

    (define (build-of (triangles Triangles) (n I64) (padded I64) (step (Pair I64 I64))) (→ BvhBuild)
      (new BvhBuild
        (low (corner (● triangles low)))
        (high (corner (● triangles high)))
        (counts (new Vec4i
                  (x (i64->i32 n))
                  (y (i64->i32 padded))
                  (z (i64->i32 (● step first)))
                  (w (i64->i32 (● step second)))))
        (words (positions-of triangles))))

    (define (corner (point (List F64))) (→ Vec4f)
      (new Vec4f
        (x (f64->f32 (list-ref point 0)))
        (y (f64->f32 (list-ref point 1)))
        (z (f64->f32 (list-ref point 2)))
        (w 0.0)))



    ;; The bitonic sort's steps, j then k: for each block size k from 2,
    ;; distances j from k/2 down to 1.
    (define (sort-steps (padded I64)) (→ (List (Pair I64 I64)))
      (concatenate (map (lambda (k)
                          (map (lambda (j) (new Pair (first j) (second k)))
                               (halvings (quotient k 2))))
                        (doublings 2 padded))))

    (define (halvings (j I64)) (→ (List I64)) (if (< j 1) (Nil) (Cons j (halvings (quotient j 2)))))

    (define (doublings (k I64) (limit I64)) (→ (List I64))
      (if (> k limit) (Nil) (Cons k (doublings (* k 2) limit))))

    (define (power-of-two-at-least (n I64)) (→ I64)
      (if (<= n 1) 1 (* 2 (power-of-two-at-least (quotient (+ n 1) 2)))))

    ;; Enough refits for the deepest tree n keys of 30 bits make, rounded
    ;; up to even so the boxes end in `nodes`.
    (define (refits (n I64)) (→ I64)
      (let ((deepest (+ 32 (bits n))))
        (* 2 (quotient (+ deepest 1) 2))))

    (define (bits (n I64)) (→ I64) (if (<= n 1) 0 (+ 1 (bits (quotient n 2)))))



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
                                                    (code (string-append (declarations layout-shape)
                                                                         cutout
                                                                         rays-shader))))))
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
                    (list (buffer 0 (● bvh nodes))
                          (buffer 1 (● bvh triangles positions))
                          (buffer 2 (● bvh triangles indices))
                          (buffer 3 (● bvh layout))
                          (buffer 4 rays)
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
