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
;; Each level is one dispatch of at most 65535 tiles, so a scan holds at
;; most 33,553,920 numbers. Sums wrap modulo 2^32.
(define-library (snail shell graphics scan)
  (export
   ScanLevel
   Scan
   make-scan
   dispatch-scan
   release-scan
   tiles)
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

    (define (make-scan (label String) (data GpuBuffer) (count I64)) (→ Scan) (! gpu)
      (let* ((module (create-shader-module
                      (new ShaderModuleDescriptor (label "scan") (code scan-code))))
             (scan (new Scan
                     (module module)
                     (scan-pipeline (step-pipeline module "scan_tiles"))
                     (add-pipeline (step-pipeline module "add_sums"))
                     (levels (Nil)))))
        (Scan-levels-set scan (levels label scan data count))))

    (define (step-pipeline (module GpuShaderModule) (entry String)) (→ GpuComputePipeline) (! gpu)
      (create-compute-pipeline
       (new ComputePipelineDescriptor
         (label (string-append "scan/" entry))
         (module module)
         (entry entry))))

    ;; The levels from `data` up, each holding the sums of the one below,
    ;; until one fits in a tile; its total goes to a sum nothing reads.

    (define (levels (label String) (scan Scan) (data GpuBuffer) (count I64))
      (→ (List Level))
      (! gpu)
      (let ((level (level-of label scan data count)))
        (if (<= count 512)
            (list level)
            (Cons level (levels label scan (● level sums) (tiles count 512))))))

    (define (level-of (label String) (scan Scan) (data GpuBuffer) (count I64)) (→ Level) (! gpu)
      (let ((uniform (level-uniform label count))
            (sums (u32-buffer (string-append label "/sums") (tiles count 512))))
        (new Level
          (count count)
          (uniform uniform)
          (sums sums)
          (scan-group (level-group label (● scan scan-pipeline) uniform data sums))
          (add-group (level-group label (● scan add-pipeline) uniform data sums)))))

    (define (u32-buffer (label String) (count I64)) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor
                       (label label)
                       (size (i64->i32 (* 4 count)))
                       (usage (list (Storage) (CopySrc) (CopyDst))))))

    (define (level-uniform (label String) (count I64)) (→ GpuBuffer) (! gpu)
      (let ((uniform (create-buffer (new BufferDescriptor
                                      (label (string-append label "/level"))
                                      (size 16)
                                      (usage (list (Uniform) (CopyDst)))))))
        (write-buffer uniform 0 (pod-bytes level-shape (new ScanLevel (count (i64->i32 count)))))
        uniform))

    (define (level-group (label String)
                         (pipeline GpuComputePipeline)
                         (uniform GpuBuffer)
                         (data GpuBuffer)
                         (sums GpuBuffer))
      (→ GpuBindGroup)
      (! gpu)
      (create-bind-group (new BindGroupDescriptor
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

    (define (dispatch-scan (pass GpuComputePass) (scan Scan)) (→ Unit) (! gpu)
      (set-compute-pipeline pass (● scan scan-pipeline))
      (for-each (lambda (level) (dispatch-level pass (● level scan-group) (● level count)))
                (● scan levels))
      (set-compute-pipeline pass (● scan add-pipeline))
      (for-each (lambda (level) (dispatch-level pass (● level add-group) (● level count)))
                (reverse (but-last (● scan levels)))))

    (define (dispatch-level (pass GpuComputePass) (group GpuBindGroup) (count I64)) (→ Unit) (! gpu)
      (set-compute-bind-group pass 0 group)
      (dispatch-workgroups pass (i64->i32 (tiles count 512)) 1 1))

    (define (but-last (items (List T))) (→ (List T)) (∀ (T))
      (match items
        ((Cons item (Cons next rest)) (Cons item (but-last (Cons next rest))))
        (_ (Nil))))

    ;; Everything the scan made goes at the next submit; the buffer it
    ;; scans stays.
    (define (release-scan (scan Scan)) (→ Unit) (! gpu)
      (for-each (lambda (level)
                  (for-each destroy
                            (list (BufferObject (● level uniform))
                                  (BufferObject (● level sums))
                                  (BindGroupObject (● level scan-group))
                                  (BindGroupObject (● level add-group)))))
                (● scan levels))
      (for-each destroy
                (list (ComputePipelineObject (● scan scan-pipeline))
                      (ComputePipelineObject (● scan add-pipeline))
                      (ModuleObject (● scan module)))))

    ))
