;; An exclusive prefix sum of `u32` numbers in a storage buffer, in place,
;; on the GPU: afterwards each number is the sum of those before it, by
;; Blelloch's work-efficient scan (scan.wgsl.scm). A workgroup scans a tile
;; of 512 numbers and writes the tile's total to a buffer of sums one level
;; up, which is scanned the same way, until a level fits in one tile; each
;; level's scanned sums are then added back to the tiles below, top down.
;; A `Scan` is made once for a buffer and a count, and encoded into a
;; compute pass as often as the buffer changes:
;;
;;   (let ((scan (make-scan "counts" counts 4096)))
;;     (dispatch-scan pass scan)       ; in a pass from begin-compute-pass
;;     ...)
;;
;; Each level is one dispatch, its tiles in rows of at most 65535
;; workgroups. Sums wrap modulo 2^32.
(define-library (snail shell graphics scan)
  (export
   ScanLevel
   Scan
   make-scan
   dispatch-scan
   release-scan
   tiles
   dispatch-rows)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics shaders))
  (begin

    ;; ---- Levels ----

    ;; How many numbers a level holds, as its uniform tells the shader.
    (record ScanLevel
      ((count I32))
      (deriving Pod))

    (define level-shape (→ (Shape ScanLevel)) (shape))

    (define scan-code (→ String) (string-append (declarations level-shape) scan-shader))

    ;; The workgroups that cover `count` numbers, `size` to a workgroup.
    (define (tiles (count I64) (size I64)) (→ I64)
      (quotient (+ count (- size 1)) size))

    ;; A level: how many numbers it holds, its uniform saying so, the sums
    ;; of its tiles one level up, and the bind groups of its two steps,
    ;; each over its numbers and those sums.
    (record Level
      ((count I64)
       (uniform GpuBuffer)
       (sums GpuBuffer)
       (scan-group GpuBindGroup)
       (add-group GpuBindGroup)))

    ;; The shader and its two pipelines, and the levels from the buffer up.
    (record Scan
      ((module GpuShaderModule)
       (scan-pipeline GpuComputePipeline)
       (add-pipeline GpuComputePipeline)
       (levels (List Level))))

    ;; ---- Making ----

    (define (make-scan (gpu Gpu) (label String) (data GpuBuffer) (count I64)) (→ Scan)
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor
                        (label "scan")
                        (code scan-code))))
             (scan (new Scan
                     (module module)
                     (scan-pipeline (step-pipeline gpu module "scan_tiles"))
                     (add-pipeline (step-pipeline gpu module "add_sums"))
                     (levels (Nil)))))
        (Scan-levels-set scan (levels gpu label scan data count))))

    (define (step-pipeline (gpu Gpu) (module GpuShaderModule) (entry String))
      (→ GpuComputePipeline)
      ((● gpu create-compute-pipeline)
       (new ComputePipelineDescriptor
         (label (string-append "scan/" entry))
         (module module)
         (entry entry))))

    ;; The levels from `data` up, each holding the sums of the one below,
    ;; until one fits in a tile; its total goes to a sum nothing reads.

    (define (levels (gpu Gpu) (label String) (scan Scan) (data GpuBuffer) (count I64))
      (→ (List Level))
      (let ((level (level-of gpu label scan data count)))
        (if (<= count 512)
            (list level)
            (Cons level (levels gpu label scan (● level sums) (tiles count 512))))))

    (define (level-of (gpu Gpu) (label String) (scan Scan) (data GpuBuffer) (count I64))
      (→ Level)
      (let ((uniform (level-uniform gpu label count))
            (sums (u32-buffer gpu (string-append label "/sums") (tiles count 512))))
        (new Level
          (count count)
          (uniform uniform)
          (sums sums)
          (scan-group (level-group gpu label (● scan scan-pipeline) uniform data sums))
          (add-group (level-group gpu label (● scan add-pipeline) uniform data sums)))))

    (define (u32-buffer (gpu Gpu) (label String) (count I64)) (→ GpuBuffer)
      ((● gpu create-buffer) (new BufferDescriptor
                               (label label)
                               (size (i64->i32 (* 4 count)))
                               (usage (list (Storage) (CopySrc) (CopyDst))))))

    (define (level-uniform (gpu Gpu) (label String) (count I64)) (→ GpuBuffer)
      (let ((uniform ((● gpu create-buffer) (new BufferDescriptor
                                              (label (string-append label "/level"))
                                              (size 16)
                                              (usage (list (Uniform) (CopyDst)))))))
        ((● gpu write-buffer)
         uniform
         0
         (pod-bytes level-shape (new ScanLevel (count (i64->i32 count)))))
        uniform))

    (define (level-group (gpu Gpu) (label String)
                         (pipeline GpuComputePipeline)
                         (uniform GpuBuffer)
                         (data GpuBuffer)
                         (sums GpuBuffer))
      (→ GpuBindGroup)
      ((● gpu create-bind-group) (new BindGroupDescriptor
                                   (label (string-append "scan/" label))
                                   (pipeline (ComputePipeline pipeline))
                                   (group 0)
                                   (entries (list (BufferEntry 0 uniform 0 0)
                                                  (BufferEntry 1 data 0 0)
                                                  (BufferEntry 2 sums 0 0))))))

    ;; ---- Scanning ----

    ;; Every level scanned from the buffer up, then each level's sums added
    ;; to the level below, from the top down. Dispatches in a pass see the
    ;; writes of those before them.

    (define (dispatch-scan (gpu Gpu) (pass GpuComputePass) (scan Scan)) (→ Unit)
      ((● gpu set-compute-pipeline) pass (● scan scan-pipeline))
      (for-each (lambda (level) (dispatch-level gpu pass (● level scan-group) (● level count)))
                (● scan levels))
      ((● gpu set-compute-pipeline) pass (● scan add-pipeline))
      (for-each (lambda (level) (dispatch-level gpu pass (● level add-group) (● level count)))
                (reverse (but-last (● scan levels)))))

    (define (dispatch-level (gpu Gpu) (pass GpuComputePass) (group GpuBindGroup) (count I64))
      (→ Unit)
      ((● gpu set-compute-bind-group) pass 0 group)
      (dispatch-rows gpu pass (tiles count 512)))

    ;; `count` workgroups in rows of at most 65535.
    (define (dispatch-rows (gpu Gpu) (pass GpuComputePass) (count I64)) (→ Unit)
      (let ((x (min count 65535)))
        ((● gpu dispatch-workgroups) pass (i64->i32 x) (i64->i32 (tiles count x)) 1)))

    (define (but-last (items (List T))) (→ (List T)) (∀ (T))
      (match items
        ((Cons item (Cons next rest)) (Cons item (but-last (Cons next rest))))
        (_ (Nil))))

    ;; Everything the scan made goes at the next submit; the buffer it
    ;; scans stays.
    (define (release-scan (gpu Gpu) (scan Scan)) (→ Unit)
      (for-each (lambda (level)
                  (for-each (lambda (object) ((● gpu destroy) object))
                            (list (BufferObject (● level uniform))
                                  (BufferObject (● level sums))
                                  (BindGroupObject (● level scan-group))
                                  (BindGroupObject (● level add-group)))))
                (● scan levels))
      (for-each (lambda (object) ((● gpu destroy) object))
                (list (ComputePipelineObject (● scan scan-pipeline))
                      (ComputePipelineObject (● scan add-pipeline))
                      (ModuleObject (● scan module)))))

    ))
