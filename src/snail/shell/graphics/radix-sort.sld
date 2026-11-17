;; Sorting `u32` keys and their `u32` values in storage buffers, in place,
;; on the GPU: a least-significant-digit radix sort, four bits a pass
;; (radix-sort.wgsl.scm). A pass counts each block of 256 keys by digit,
;; scans the counts with (snail shell graphics scan) into where each
;; block's keys of each digit go, and scatters the keys and values there,
;; stably, into a second pair of buffers; the next pass reads them back.
;; The sort is stable: equal keys keep their values' order.
;;
;;   (let ((sorter (make-sorter "depths" keys values count 32)))
;;     (dispatch-sort pass sorter)     ; in a pass from begin-compute-pass
;;     ...)
;;
;; A sorter sorts the low `key-bits` bits of each key, 8, 16, 24 or 32: an
;; even number of passes, so the sorted keys end where they began. Each
;; pass is one dispatch of a workgroup per block, so a sorter holds at most
;; 16,776,960 keys.
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

    ;; Which digit a pass sorts by, the blocks of keys, and the key count,
    ;; as its uniform tells the shader.
    (record SortPass
      ((shift I32)
       (blocks I32)
       (count I32))
      (deriving Pod))

    (define pass-shape (→ (Shape SortPass)) (shape))

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

    ;; The shader and its two pipelines, a step a pass, the blocks of keys,
    ;; the counts by digit and block and their scan, and the spare lane the
    ;; passes alternate with the sorted one.
    (record Sorter
      ((module GpuShaderModule)
       (count-pipeline GpuComputePipeline)
       (scatter-pipeline GpuComputePipeline)
       (steps (List Step))
       (blocks I64)
       (counts GpuBuffer)
       (scan Scan)
       (spare Lane)))

    ;; ---- Making ----

    ;; A sorter of `count` keys and values in `keys` and `values`, which
    ;; need the `Storage` usage. Even passes read the given lane and write
    ;; the spare one; odd passes read it back.

    (define (make-sorter (label String)
                         (keys GpuBuffer)
                         (values GpuBuffer)
                         (count I64)
                         (key-bits I64))
      (→ Sorter)
      (! gpu)
      (unless (and (any? (lambda (bits) (= bits key-bits)) (list 8 16 24 32)) (> count 0))
        (panic "radix-sort: a sorter sorts 8, 16, 24 or 32 bits of at least one key"))
      (let* ((module (create-shader-module
                      (new ShaderModuleDescriptor (label "radix-sort") (code sort-code))))
             (blocks (tiles count 256))
             (counts (u32-buffer (string-append label "/counts") (* 16 blocks)))
             (given (new Lane (keys keys) (values values)))
             (spare (new Lane
                      (keys (u32-buffer (string-append label "/keys") count))
                      (values (u32-buffer (string-append label "/values") count))))
             (sorter (new Sorter
                       (module module)
                       (count-pipeline (sort-pipeline module "count_digits"))
                       (scatter-pipeline (sort-pipeline module "scatter"))
                       (steps (Nil))
                       (blocks blocks)
                       (counts counts)
                       (scan (make-scan label counts (* 16 blocks)))
                       (spare spare))))
        (Sorter-steps-set sorter
                          (map (lambda (pass)
                                 (let ((even (= (remainder pass 2) 0)))
                                   (step label
                                         sorter
                                         (pass-uniform label (* 4 pass) count)
                                         (if even given spare)
                                         (if even spare given))))
                               (iota (quotient key-bits 4))))))

    (define (sort-pipeline (module GpuShaderModule) (entry String)) (→ GpuComputePipeline) (! gpu)
      (create-compute-pipeline (new ComputePipelineDescriptor
                                 (label (string-append "radix-sort/" entry))
                                 (module module)
                                 (entry entry))))

    (define (u32-buffer (label String) (count I64)) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor
                       (label label)
                       (size (i64->i32 (* 4 count)))
                       (usage (list (Storage) (CopySrc) (CopyDst))))))

    (define (pass-uniform (label String) (shift I64) (count I64)) (→ GpuBuffer) (! gpu)
      (let ((uniform (create-buffer (new BufferDescriptor
                                      (label (string-append label "/pass"))
                                      (size 16)
                                      (usage (list (Uniform) (CopyDst)))))))
        (write-buffer uniform
                      0
                      (pod-bytes pass-shape
                                 (new SortPass
                                   (shift (i64->i32 shift))
                                   (blocks (i64->i32 (tiles count 256)))
                                   (count (i64->i32 count)))))
        uniform))

    ;; A pass from the lane `from` to the lane `to`.

    (define (step (label String) (sorter Sorter) (uniform GpuBuffer) (from Lane) (to Lane)) (→ Step)
      (! gpu)
      (new Step
        (uniform uniform)
        (count-group (sort-group label
                                 (● sorter count-pipeline)
                                 (list (BufferEntry 0 uniform 0 0)
                                       (BufferEntry 1 (● from keys) 0 0)
                                       (BufferEntry 3 (● sorter counts) 0 0))))
        (scatter-group (sort-group label
                                   (● sorter scatter-pipeline)
                                   (list (BufferEntry 0 uniform 0 0)
                                         (BufferEntry 1 (● from keys) 0 0)
                                         (BufferEntry 2 (● from values) 0 0)
                                         (BufferEntry 3 (● sorter counts) 0 0)
                                         (BufferEntry 4 (● to keys) 0 0)
                                         (BufferEntry 5 (● to values) 0 0))))))

    (define (sort-group (label String)
                        (pipeline GpuComputePipeline)
                        (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (! gpu)
      (create-bind-group (new BindGroupDescriptor
                           (label (string-append "radix-sort/" label))
                           (pipeline (ComputePipeline pipeline))
                           (group 0)
                           (entries entries))))

    ;; ---- Sorting ----

    ;; Each pass: count, scan the counts, scatter.

    (define (dispatch-sort (pass GpuComputePass) (sorter Sorter)) (→ Unit) (! gpu)
      (for-each (lambda (step)
                  (dispatch-blocks pass (● sorter count-pipeline) (● step count-group) sorter)
                  (dispatch-scan pass (● sorter scan))
                  (dispatch-blocks pass (● sorter scatter-pipeline) (● step scatter-group) sorter))
                (● sorter steps)))

    (define (dispatch-blocks (pass GpuComputePass)
                             (pipeline GpuComputePipeline)
                             (group GpuBindGroup)
                             (sorter Sorter))
      (→ Unit)
      (! gpu)
      (set-compute-pipeline pass pipeline)
      (set-compute-bind-group pass 0 group)
      (dispatch-workgroups pass (i64->i32 (● sorter blocks)) 1 1))

    ;; Everything the sorter made, and its scan, goes at the next submit;
    ;; the lane it was given stays.
    (define (release-sorter (sorter Sorter)) (→ Unit) (! gpu)
      (release-scan (● sorter scan))
      (for-each (lambda (step)
                  (destroy (BufferObject (● step uniform)))
                  (destroy (BindGroupObject (● step count-group)))
                  (destroy (BindGroupObject (● step scatter-group))))
                (● sorter steps))
      (for-each destroy
                (list (BufferObject (● sorter counts))
                      (BufferObject (● sorter spare keys))
                      (BufferObject (● sorter spare values))
                      (ComputePipelineObject (● sorter count-pipeline))
                      (ComputePipelineObject (● sorter scatter-pipeline))
                      (ModuleObject (● sorter module)))))

    ))
