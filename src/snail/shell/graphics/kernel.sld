;; What every library of compute kernels would otherwise write for
;; itself, each with the guarantee that makes it worth sharing:
;;
;;   compute-kernel   a pipeline for one entry point of a module
;;   kernel-group     a bind group laid out as the kernel it is for expects
;;   dispatch-items,  workgroups enough for every item, or for every texel
;;   dispatch-texels
;;   uniform-slots,   small uniform records side by side in one buffer,
;;   slot-entry       each where a uniform may be bound
;;   uniform-buffer   a uniform buffer holding the bytes it is made with
;;   storage-buffer   a storage buffer that binds even when it holds nothing
(define-library (snail shell graphics kernel)
  (export
   compute-kernel
   kernel-group
   dispatch-items
   dispatch-texels
   slot
   uniform-slots
   slot-entry
   uniform-buffer
   storage-buffer)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod))
  (begin

    ;; The kernel `entry` of `module`, labeled `label`/`entry`.
    (define (compute-kernel (gpu Gpu) (module GpuShaderModule) (label String) (entry String))
      (→ GpuComputePipeline)
      (create-compute-pipeline gpu (new ComputePipelineDescriptor
                                     (label (string-append label "/" entry))
                                     (module module)
                                     (entry entry))))

    ;; Group `index` of `kernel`, whose layout it takes.
    (define (kernel-group (gpu Gpu) (kernel GpuComputePipeline)
                          (index I32)
                          (label String)
                          (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (create-bind-group gpu (new BindGroupDescriptor
                               (label label)
                               (pipeline (ComputePipeline kernel))
                               (group index)
                               (entries entries))))

    ;; Workgroups of `size` for `count` items, at least one, in rows of
    ;; 65535, the most a dispatch has along an axis. Invocations past the
    ;; count run too, so a kernel returns for an index it has no item for.
    (define (dispatch-items (gpu Gpu) (pass GpuComputePass) (count I64) (size I64)) (→ Unit)
      (let ((groups (max 1 (quotient (+ count (- size 1)) size))))
        (dispatch-workgroups gpu pass
                             (i64->i32 (min groups 65535))
                             (i64->i32 (quotient (+ groups 65534) 65535))
                             1)))

    ;; Workgroups of 8 by 8 for every texel of a width and a height.
    (define (dispatch-texels (gpu Gpu) (pass GpuComputePass) (width I32) (height I32))
      (→ Unit)
      (dispatch-workgroups gpu pass (quotient (+ width 7) 8) (quotient (+ height 7) 8) 1))

    ;; A uniform binds at a multiple of 256 bytes.
    (define slot (→ I64) 256)

    ;; Each value at the start of a slot of its own, in order.
    (define (uniform-slots (shape (Shape T)) (values (List T))) (→ Bytes) (∀ (T)) (⊨ (Pod T))
      (array-concatenate
       (map (lambda (value)
              (let ((bytes (pod-bytes shape value)))
                (array-append bytes (make-array (- slot (array-length bytes)) (i32->u8 0)))))
            values)))

    ;; Slot `index` of `buffer` at `binding`.
    (define (slot-entry (binding I32) (buffer GpuBuffer) (index I64)) (→ BindGroupEntry)
      (BufferEntry binding buffer (i64->i32 (* slot index)) (i64->i32 slot)))

    (define (uniform-buffer (gpu Gpu) (label String) (bytes Bytes)) (→ GpuBuffer)
      (let ((buffer (create-buffer gpu (new BufferDescriptor
                                         (label label)
                                         (size (i64->i32 (array-length bytes)))
                                         (usage (list (Uniform) (CopyDst)))))))
        (write-buffer gpu buffer 0 bytes)
        buffer))

    ;; At least 16 bytes, since no buffer binds empty.
    (define (storage-buffer (gpu Gpu) (label String) (size I64) (more (List BufferUsage)))
      (→ GpuBuffer)
      (create-buffer gpu (new BufferDescriptor
                           (label label)
                           (size (i64->i32 (max 16 size)))
                           (usage (Cons (Storage) more)))))

    ))
