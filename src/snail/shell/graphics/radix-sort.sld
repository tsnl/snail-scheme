;; Sorting `u32` keys and their `u32` values in storage buffers on the
;; GPU: a least-significant-digit radix sort, eight bits a pass
;; (radix-sort.wgsl.scm). A pass counts the keys of each workgroup's run
;; of blocks by digit, scans the counts with (snail shell graphics scan)
;; into where each run's keys of each digit go, and scatters the keys and
;; values there, stably, into another pair of buffers, which the next
;; pass reads. The sort is stable: equal keys keep their values' order.
;;
;;   (let* ((lane (new SortLane (keys keys) (values values)))
;;          (sorter (make-sorter gpu "depths" lane lane count 32 (None))))
;;     (dispatch-sort gpu pass sorter) ; in a pass from begin-compute-pass
;;     ...)
;;
;; A sorter sorts the low `key-bits` bits of each key, 8, 16, 24 or 32. It
;; reads the lane `from` and leaves the pairs sorted in the lane `to`, its
;; passes alternating between `to` and a spare lane of its own so that the
;; last writes `to`. So `from` may be `to`, a sort in place, only for an
;; even number of passes: 16 or 32 bits. It sorts all `count` pairs, or as
;; many as the first `u32` of a buffer it is given says, which the device
;; may compute in the same pass, and writes nothing of `to` past them.
;; Each pass dispatches a workgroup a block of the capacity, at most
;; `most-groups`, and the workgroups share the blocks counted in runs.
;; Dispatching only the workgroups the count needs would take an indirect
;; dispatch, which Dawn validates on the host at about half a millisecond
;; each.
(define-library (snail shell graphics radix-sort)
  (export
   SortPass
   SortLane
   Sorter
   make-sorter
   dispatch-sort
   release-sorter)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics scan)
   (snail shell graphics shaders))
  (begin

    ;; ---- Passes ----

    ;; Which digit a pass sorts by, and the most keys the sorter sorts, as
    ;; its uniform tells the shader.
    (record SortPass
      ((shift I32)
       (capacity I32))
      (deriving Pod))

    (define pass-shape (→ (Shape SortPass)) (shape))

    ;; The keys a sorter given no count of its own sorts, all it holds, as
    ;; its count buffer tells the shader.
    (record SortCount
      ((count I32))
      (deriving Pod))

    (define count-shape (→ (Shape SortCount)) (shape))

    (define sort-code (→ String) (string-append (declarations pass-shape) radix-sort-shader))

    ;; Keys and their values, side by side.
    (record SortLane
      ((keys GpuBuffer)
       (values GpuBuffer)))

    ;; A pass's uniform and its bind groups: counting its input's digits,
    ;; and scattering its input to its output.
    (record Step
      ((uniform GpuBuffer)
       (count-group GpuBindGroup)
       (scatter-group GpuBindGroup)))

    ;; The shader and its pipelines, a step a pass, the counts by digit and
    ;; run and their scan, and the spare lane the passes alternate with the
    ;; sorted one; the buffer counting the keys sorted, whether the sorter
    ;; made it, and the workgroups a pass takes.
    (record Sorter
      ((module GpuShaderModule)
       (count-pipeline GpuComputePipeline)
       (scatter-pipeline GpuComputePipeline)
       (steps (List Step))
       (counts GpuBuffer)
       (scan Scan)
       (spare SortLane)
       (counting GpuBuffer)
       (own-count Bool)
       (groups I64)))

    ;; Workgroups enough to keep a device busy, each taking a run of the
    ;; blocks counted. On an RTX 5090, eight dispatches of a kernel storing
    ;; each key of a block took 0.026 ms over 1.65 million keys with 4096
    ;; workgroups taking blocks in turn, and 0.75 ms with a workgroup a
    ;; block of a capacity of 33.5 million, most finding none; over 33.5
    ;; million keys they took 0.64 and 0.82 ms.
    (define most-groups (→ I64) 4096)

    ;; ---- Making ----

    ;; A sorter of `count` keys and values from the lane `from` into the
    ;; lane `to`, whose buffers need the `Storage` usage, or of as many as
    ;; `counted` holds, a buffer of the `Storage` usage too. The counts
    ;; take 256 words a workgroup, a million for 4096 workgroups.

    (define (make-sorter (gpu Gpu) (label String)
                         (from SortLane)
                         (to SortLane)
                         (count I64)
                         (key-bits I64)
                         (counted (Option GpuBuffer)))
      (→ Sorter)
      (let ((passes (quotient key-bits 8)))
        (unless (and (any? (lambda (bits) (= bits key-bits)) (list 8 16 24 32)) (> count 0))
          (panic "radix-sort: a sorter sorts 8, 16, 24 or 32 bits of at least one key"))
        (when (and (= (remainder passes 2) 1) (shares-a-buffer? from to))
          (panic "radix-sort: a sorter sorts in place only 16 or 32 bits"))
        (let* ((module ((● gpu create-shader-module)
                        (new ShaderModuleDescriptor
                          (label "radix-sort")
                          (code sort-code))))
               (groups (min (tiles count 256) most-groups))
               (counts (u32-buffer gpu (string-append label "/counts") (* 256 groups)))
               (spare (new SortLane
                        (keys (u32-buffer gpu (string-append label "/keys") count))
                        (values (u32-buffer gpu (string-append label "/values") count))))
               (sorter (new Sorter
                         (module module)
                         (count-pipeline (sort-pipeline gpu module "count_digits"))
                         (scatter-pipeline (sort-pipeline gpu module "scatter"))
                         (steps (Nil))
                         (counts counts)
                         (scan (make-scan gpu label counts (* 256 groups)))
                         (spare spare)
                         (counting (match counted
                                     ((Some buffer) buffer)
                                     ((None) (count-buffer gpu label count))))
                         (own-count (match counted
                                      ((Some _) #f)
                                      ((None) #t)))
                         (groups groups)))
               (written (lambda (pass) (if (= (remainder (- passes pass) 2) 1) to spare))))
          (Sorter-steps-set sorter
                            (map (lambda (pass)
                                   (step gpu label
                                         sorter
                                         (pass-uniform gpu label (* 8 pass) count)
                                         (if (= pass 0) from (written (- pass 1)))
                                         (written pass)))
                                 (iota passes))))))

    ;; Whether two lanes share a buffer, so that a pass from one to the
    ;; other would write what it reads.
    (define (shares-a-buffer? (a SortLane) (b SortLane)) (→ Bool)
      (let ((ids (lambda (lane) (list (● lane keys id) (● lane values id)))))
        (any? (lambda (id) (member? id (ids b))) (ids a))))

    (define (count-buffer (gpu Gpu) (label String) (count I64)) (→ GpuBuffer)
      (let ((buffer (u32-buffer gpu (string-append label "/count") 1)))
        ((● gpu write-buffer)
         buffer
         0
         (pod-bytes count-shape (new SortCount (count (i64->i32 count)))))
        buffer))

    (define (sort-pipeline (gpu Gpu) (module GpuShaderModule) (entry String))
      (→ GpuComputePipeline)
      ((● gpu create-compute-pipeline) (new ComputePipelineDescriptor
                                         (label (string-append "radix-sort/" entry))
                                         (module module)
                                         (entry entry))))

    (define (u32-buffer (gpu Gpu) (label String) (count I64)) (→ GpuBuffer)
      ((● gpu create-buffer) (new BufferDescriptor
                               (label label)
                               (size (i64->i32 (* 4 count)))
                               (usage (list (Storage) (CopySrc) (CopyDst))))))

    (define (pass-uniform (gpu Gpu) (label String) (shift I64) (count I64)) (→ GpuBuffer)
      (let ((uniform ((● gpu create-buffer) (new BufferDescriptor
                                              (label (string-append label "/pass"))
                                              (size 16)
                                              (usage (list (Uniform) (CopyDst)))))))
        ((● gpu write-buffer) uniform
         0
         (pod-bytes pass-shape (new SortPass (shift (i64->i32 shift)) (capacity (i64->i32 count)))))
        uniform))

    ;; A pass from the lane `from` to the lane `to`.

    (define (step (gpu Gpu)
                  (label String)
                  (sorter Sorter)
                  (uniform GpuBuffer)
                  (from SortLane)
                  (to SortLane))
      (→ Step)
      (new Step
        (uniform uniform)
        (count-group (sort-group gpu label
                                 (● sorter count-pipeline)
                                 (list (BufferEntry 0 uniform 0 0)
                                       (BufferEntry 1 (● from keys) 0 0)
                                       (BufferEntry 3 (● sorter counts) 0 0)
                                       (BufferEntry 6 (● sorter counting) 0 0))))
        (scatter-group (sort-group gpu label
                                   (● sorter scatter-pipeline)
                                   (list (BufferEntry 0 uniform 0 0)
                                         (BufferEntry 1 (● from keys) 0 0)
                                         (BufferEntry 2 (● from values) 0 0)
                                         (BufferEntry 3 (● sorter counts) 0 0)
                                         (BufferEntry 4 (● to keys) 0 0)
                                         (BufferEntry 5 (● to values) 0 0)
                                         (BufferEntry 6 (● sorter counting) 0 0))))))

    (define (sort-group (gpu Gpu) (label String)
                        (pipeline GpuComputePipeline)
                        (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      ((● gpu create-bind-group) (new BindGroupDescriptor
                                   (label (string-append "radix-sort/" label))
                                   (pipeline (ComputePipeline pipeline))
                                   (group 0)
                                   (entries entries))))

    ;; ---- Sorting ----

    ;; Each pass: count, scan the counts, scatter.

    (define (dispatch-sort (gpu Gpu) (pass GpuComputePass) (sorter Sorter)) (→ Unit)
      (for-each (lambda (step)
                  (dispatch-blocks gpu pass (● sorter count-pipeline) (● step count-group) sorter)
                  (dispatch-scan gpu pass (● sorter scan))
                  (dispatch-blocks gpu
                                   pass
                                   (● sorter scatter-pipeline)
                                   (● step scatter-group)
                                   sorter))
                (● sorter steps)))

    (define (dispatch-blocks (gpu Gpu) (pass GpuComputePass)
                             (pipeline GpuComputePipeline)
                             (group GpuBindGroup)
                             (sorter Sorter))
      (→ Unit)
      ((● gpu set-compute-pipeline) pass pipeline)
      ((● gpu set-compute-bind-group) pass 0 group)
      ((● gpu dispatch-workgroups) pass (i64->i32 (● sorter groups)) 1 1))

    ;; Everything the sorter made, and its scan, goes at the next submit;
    ;; the lane it was given stays.
    (define (release-sorter (gpu Gpu) (sorter Sorter)) (→ Unit)
      (release-scan gpu (● sorter scan))
      (for-each (lambda (step)
                  ((● gpu destroy) (BufferObject (● step uniform)))
                  ((● gpu destroy) (BindGroupObject (● step count-group)))
                  ((● gpu destroy) (BindGroupObject (● step scatter-group))))
                (● sorter steps))
      (when (● sorter own-count) ((● gpu destroy) (BufferObject (● sorter counting))))
      (for-each (lambda (object) ((● gpu destroy) object))
                (list (BufferObject (● sorter counts))
                      (BufferObject (● sorter spare keys))
                      (BufferObject (● sorter spare values))
                      (ComputePipelineObject (● sorter count-pipeline))
                      (ComputePipelineObject (● sorter scatter-pipeline))
                      (ModuleObject (● sorter module)))))

    ))
