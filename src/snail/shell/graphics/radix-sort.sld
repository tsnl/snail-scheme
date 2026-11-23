;; Sorting `u32` keys and their `u32` values in storage buffers, in place,
;; on the GPU: a least-significant-digit radix sort, four bits a pass
;; (radix-sort.wgsl.scm). A pass counts each block of 256 keys by digit,
;; scans the counts with (snail shell graphics scan) into where each
;; block's keys of each digit go, and scatters the keys and values there,
;; stably, into a second pair of buffers; the next pass reads them back.
;; The sort is stable: equal keys keep their values' order.
;;
;;   (let ((sorter (make-sorter gpu "depths" keys values count 32 (None))))
;;     (dispatch-sort gpu pass sorter) ; in a pass from begin-compute-pass
;;     ...)
;;
;; A sorter sorts the low `key-bits` bits of each key, 8, 16, 24 or 32: an
;; even number of passes, so the sorted keys end where they began. It
;; sorts all `count` keys, or as many of them as the first `u32` of a
;; buffer it is given says, which the device may compute in the same pass,
;; and leaves the keys past that as they were. Each pass dispatches a
;; workgroup a block of the capacity, at most `most-groups`, and each
;; workgroup takes the blocks counted in turn. Dispatching only the
;; workgroups the count needs would take an indirect dispatch, which Dawn
;; validates on the host at about half a millisecond each.
(define-library (snail shell graphics radix-sort)
  (export
   SortPass
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
    (record Lane
      ((keys GpuBuffer)
       (values GpuBuffer)))

    ;; A pass's uniform and its bind groups: counting its input's digits,
    ;; and scattering its input to its output.
    (record Step
      ((uniform GpuBuffer)
       (count-group GpuBindGroup)
       (scatter-group GpuBindGroup)))

    ;; The shader and its pipelines, a step a pass, the counts by digit and
    ;; block and their scan, and the spare lane the passes alternate with
    ;; the sorted one; the buffer counting the keys sorted, whether the
    ;; sorter made it, and the workgroups a pass takes.
    (record Sorter
      ((module GpuShaderModule)
       (count-pipeline GpuComputePipeline)
       (scatter-pipeline GpuComputePipeline)
       (steps (List Step))
       (counts GpuBuffer)
       (scan Scan)
       (spare Lane)
       (counting GpuBuffer)
       (own-count Bool)
       (groups I64)))

    ;; Workgroups enough to keep a device busy, each taking blocks in turn.
    ;; On an RTX 5090, eight dispatches of a kernel storing each key of a
    ;; block took 0.026 ms over 1.65 million keys with 4096 workgroups, and
    ;; 0.75 ms with a workgroup a block of a capacity of 33.5 million, most
    ;; finding none; over 33.5 million keys they took 0.64 and 0.82 ms.
    (define most-groups (→ I64) 4096)

    ;; ---- Making ----

    ;; A sorter of `count` keys and values in `keys` and `values`, which
    ;; need the `Storage` usage, or of as many as `counted` holds, a buffer
    ;; of the `Storage` usage too. Even passes read the given lane and
    ;; write the spare one; odd passes read it back.

    (define (make-sorter (gpu Gpu) (label String)
                         (keys GpuBuffer)
                         (values GpuBuffer)
                         (count I64)
                         (key-bits I64)
                         (counted (Option GpuBuffer)))
      (→ Sorter)
      (unless (and (any? (lambda (bits) (= bits key-bits)) (list 8 16 24 32)) (> count 0))
        (panic "radix-sort: a sorter sorts 8, 16, 24 or 32 bits of at least one key"))
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor
                        (label "radix-sort")
                        (code sort-code))))
             (blocks (tiles count 256))
             (counts (u32-buffer gpu (string-append label "/counts") (* 16 blocks)))
             (given (new Lane (keys keys) (values values)))
             (spare (new Lane
                      (keys (u32-buffer gpu (string-append label "/keys") count))
                      (values (u32-buffer gpu (string-append label "/values") count))))
             (counting (match counted
                         ((Some buffer) buffer)
                         ((None) (count-buffer gpu label count))))
             (sorter (new Sorter
                       (module module)
                       (count-pipeline (sort-pipeline gpu module "count_digits"))
                       (scatter-pipeline (sort-pipeline gpu module "scatter"))
                       (steps (Nil))
                       (counts counts)
                       (scan (make-scan gpu label counts (* 16 blocks)))
                       (spare spare)
                       (counting counting)
                       (own-count (match counted
                                    ((Some _) #f)
                                    ((None) #t)))
                       (groups (min blocks most-groups)))))
        (Sorter-steps-set sorter
                          (map (lambda (pass)
                                 (let ((even (= (remainder pass 2) 0)))
                                   (step gpu label
                                         sorter
                                         (pass-uniform gpu label (* 4 pass) count)
                                         (if even given spare)
                                         (if even spare given))))
                               (iota (quotient key-bits 4))))))

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
                  (from Lane)
                  (to Lane))
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
