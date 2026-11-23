;; Device-resident Voronoi sites, camera rays, and minibatch training.
;; The CPU and GPU share the model, checkpoint format and sampled ray ids.
(define-library (snail shell graphics radiant-foam-gpu)
  (export DeviceFoam make-device-foam read-foam release-device-foam
          FoamView
          make-foam-view
          write-foam-camera!
          dispatch-foam-view
          read-foam-view
          release-foam-view
          FoamTrainer make-foam-trainer train-foam! release-foam-trainer)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics kernel)
   (snail shell graphics pod)
   (snail shell graphics radiant-foam)
   (only (snail shell graphics shaders) radiant-foam-shader))
  (begin

    ;; ---- Buffer layout ----

    ;; Node and the browser request buffers up to one GiB, within the
    ;; adapter's limits. Check byte sizes before narrowing them to I32.
    (define buffer-limit 1073741824)

    (define (four (v Vec3d) (w F64)) (→ Vec4f)
      (new Vec4f (x (f64->f32 (● v x))) (y (f64->f32 (● v y)))
           (z (f64->f32 (● v z))) (w (f64->f32 w))))

    (record CameraUniform
      ((eye Vec4f)
       (corner Vec4f)
       (dx Vec4f)
       (dy Vec4f)
       (image Vec4i))
      (deriving Pod))

    (define camera-shape (→ (Shape CameraUniform)) (shape))

    (define (camera-bytes (camera RayCamera) (w I64) (h I64)) (→ Bytes)
      ;; The shader's integer pixel-center resampling fits in a u32.
      (unless (and (> w 0) (> h 0) (> (● camera width) 0) (> (● camera height) 0)
                   (<= w (quotient 2147483647 (● camera width)))
                   (<= h (quotient 2147483647 (● camera height))))
        (panic "foam camera dimensions exceed the pixel grid"))
      (pod-bytes camera-shape
                 (new CameraUniform (eye (four (● camera eye) 0.0))
                      (corner (four (● camera corner) 0.0)) (dx (four (● camera dx) 0.0))
                      (dy (four (● camera dy) 0.0))
                      (image
                       (new Vec4i (x (i64->i32 (● camera width))) (y (i64->i32 (● camera height)))
                            (z (i64->i32 w)) (w (i64->i32 h)))))))

    (define (packed-sites (sites Foam)) (→ Bytes)
      (when (> (array-length sites) (quotient buffer-limit 32))
        (panic "foam exceeds its site buffer"))
      (let ((data (make-array (* 32 (array-length sites)) (i32->u8 0))))
        (do ((i 0 (+ i 1))) ((= i (array-length sites)) data)
          (let ((s (array-ref sites i)))
            (when (> (● s density) 3.4028234663852886e38) (panic "foam density exceeds f32"))
            (pod-write (four (● s position) (● s density)) data (* i 32))
            (pod-write (four (● s rgb) 0.0) data (+ (* i 32) 16))))))

    (define (packed-rays (samples (Array Sample))) (→ Bytes)
      (when (> (array-length samples) (quotient buffer-limit 48))
        (panic "foam exceeds its ray buffer"))
      (let ((data (make-array (* 48 (array-length samples)) (i32->u8 0))))
        (do ((i 0 (+ i 1))) ((= i (array-length samples)) data)
          (let ((s (array-ref samples i)) (at (* i 48)))
            (pod-write (four (● s ray origin) 0.0) data at)
            (pod-write (four (● s ray direction) 0.0) data (+ at 16))
            (pod-write (four (● s rgb) 0.0) data (+ at 32))))))

    (define (float-at (data Bytes) (at I64)) (→ F64)
      (let ((byte (lambda (k shift) (i32-shift-left (u8->i32 (array-ref data (+ at k))) shift))))
        (f32->f64 (bits->f32 (i32-or (i32-or (byte 0 0) (byte 1 8))
                                     (i32-or (byte 2 16) (byte 3 24)))))))

    (define (three-at (data Bytes) (at I64)) (→ Vec3d)
      (vec3d (float-at data at) (float-at data (+ at 4)) (float-at data (+ at 8))))

    ;; Even an empty array needs room for one WGSL element to bind.
    (define (upload (gpu Gpu) (name String) (bytes Bytes) (minimum I64) (more (List BufferUsage)))
      (→ GpuBuffer)
      (let ((buf
             (storage-buffer gpu name (max minimum (array-length bytes)) (Cons (CopyDst) more))))
        (when (> (array-length bytes) 0) ((● gpu write-buffer) buf 0 bytes))
        buf))

    (define (read-storage (gpu Gpu) (buf GpuBuffer) (size I64)) (→ Bytes)
      (if (= size 0) (make-array 0 (i32->u8 0))
          (let* ((n (i64->i32 size))
                 (stage ((● gpu create-buffer) (new BufferDescriptor (label "foam/readback")
                                                    (size n) (usage (list (CopyDst) (MapRead))))))
                 (encoder ((● gpu create-command-encoder))))
            ((● gpu copy-buffer-to-buffer) encoder buf 0 stage 0 n)
            ((● gpu submit) (list ((● gpu finish) encoder)))
            (let ((data ((● gpu read-buffer) stage 0 n)))
              ((● gpu destroy) (BufferObject stage))
              data))))

    ;; ---- Spatial groups ----

    ;; Interleave eight bits per axis into a Morton key. Sorting only the
    ;; ids keeps checkpoint order and the CPU's tie breaker. Groups stay
    ;; valid as sites move because every update refits their bounding boxes.
    (define (morton (p Vec3d)) (→ I64)
      (let* ((quantize (lambda (x) (min 255 (f64->i64 (* 128.0 (+ x 1.0))))))
             (x (quantize (● p x))) (y (quantize (● p y))) (z (quantize (● p z)))
             (bit (lambda (v k) (i64-and 1 (i64-shift-right/logical v k)))))
        (do ((k 7 (- k 1))
             (code 0 (+ (+ (* code 8) (bit x k)) (+ (* 2 (bit y k)) (* 4 (bit z k))))))
            ((< k 0) code))))

    (define (spatial-order (sites Foam)) (→ Bytes)
      (let* ((keys (array-map (lambda (s) (morton (● s position))) sites))
             (ids (list-sort (lambda (a b) (< (array-ref keys a) (array-ref keys b)))
                             (iota (array-length sites)))))
        (pack (ann (shape) (Shape I32)) (map i64->i32 ids))))

    ;; ---- Sites ----

    (record DeviceFoam
      ((count I64)
       (sites GpuBuffer)
       (order GpuBuffer)
       (bounds GpuBuffer)
       (gradients GpuBuffer)
       (rate GpuBuffer)
       (module GpuShaderModule)
       (render GpuComputePipeline)
       (learn GpuComputePipeline)
       (update GpuComputePipeline)
       (update-group GpuBindGroup)))

    (define (entry (binding I32) (buffer GpuBuffer)) (→ BindGroupEntry)
      (BufferEntry binding buffer 0 0))

    (define (dispatch (gpu Gpu) (pass GpuComputePass) (pipeline GpuComputePipeline)
                      (group GpuBindGroup) (count I64) (width I64))
      (→ Unit)
      ((● gpu set-compute-pipeline) pass pipeline)
      ((● gpu set-compute-bind-group) pass 0 group)
      (dispatch-items gpu pass count width))

    (define (update-cells! (gpu Gpu) (pass GpuComputePass) (foam DeviceFoam)) (→ Unit)
      (dispatch gpu pass (● foam update) (● foam update-group) (● foam count) 16))

    (define (rate-bytes (rate F64)) (→ Bytes)
      (pod-bytes (ann (shape) (Shape F32)) (f64->f32 rate)))

    (define (make-device-foam (gpu Gpu) (initial Foam)) (→ DeviceFoam)
      (let* ((n (array-length initial))
             (sites (upload gpu "foam/sites" (packed-sites initial) 32 (list (CopySrc))))
             (order (upload gpu "foam/order" (spatial-order initial) 4 (Nil)))
             (bounds (storage-buffer gpu "foam/bounds" (* 32 (max 1 (quotient (+ n 15) 16))) (Nil)))
             (gradients (storage-buffer gpu "foam/gradients" (* 32 n) (Nil)))
             (rate (uniform-buffer gpu "foam/rate" (rate-bytes 0.0)))
             (module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor (label "radiant foam")
                           (code (string-append "const SITES: u32 = "
                                                (show n)
                                                "u;\n"
                                                (declarations camera-shape)
                                                radiant-foam-shader)))))
             (kernel (lambda (name) (compute-kernel gpu module "foam" name)))
             (update (kernel "update_cells"))
             (group (kernel-group gpu update 0 "foam/update"
                                  (list (entry 0 sites) (entry 1 order) (entry 2 bounds)
                                        (entry 5 gradients) (entry 7 rate))))
             (foam (new DeviceFoam (count n) (sites sites) (order order) (bounds bounds)
                        (gradients gradients) (rate rate) (module module) (render (kernel "render"))
                        (learn (kernel "learn")) (update update) (update-group group)))
             (encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
        ;; WebGPU zeroes new storage. The first update builds bounds with zero gradients.
        (update-cells! gpu pass foam)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        foam))

    (define (read-foam (gpu Gpu) (foam DeviceFoam)) (→ Foam)
      (let ((data (read-storage gpu (● foam sites) (* 32 (● foam count)))))
        (make-foam (map (lambda (i)
                          (let ((at (* i 32)))
                            (site (three-at data at)
                                  (float-at data (+ at 12))
                                  (three-at data (+ at 16)))))
                        (iota (● foam count))))))

    (define (release-device-foam (gpu Gpu) (foam DeviceFoam)) (→ Unit)
      (for-each (● gpu destroy)
                (list (BindGroupObject (● foam update-group))
                      (ComputePipelineObject (● foam render))
                      (ComputePipelineObject (● foam learn)) (ComputePipelineObject (● foam update))
                      (ModuleObject (● foam module)) (BufferObject (● foam rate))
                      (BufferObject (● foam gradients)) (BufferObject (● foam bounds))
                      (BufferObject (● foam order)) (BufferObject (● foam sites)))))

    ;; ---- Rendering ----

    (record FoamView
      ((foam DeviceFoam)
       (width I64)
       (height I64)
       (camera GpuBuffer)
       (pixels GpuBuffer)
       (group GpuBindGroup)))

    (define (walk-entries (foam DeviceFoam)) (→ (List BindGroupEntry))
      (list (entry 0 (● foam sites)) (entry 1 (● foam order)) (entry 2 (● foam bounds))))

    (define (make-foam-view (gpu Gpu) (foam DeviceFoam) (cam RayCamera) (width I64) (height I64))
      (→ FoamView)
      (unless (and (> height 0) (> width 0) (<= width (quotient (quotient buffer-limit 16) height)))
        (panic "foam frame exceeds the pixel buffer"))
      (let* ((camera (uniform-buffer gpu "foam/camera" (camera-bytes cam width height)))
             (pixels (storage-buffer gpu "foam/pixels" (* 16 (* width height)) (list (CopySrc))))
             (group (kernel-group gpu (● foam render) 0 "foam/render"
                                  (append (walk-entries foam)
                                          (list (entry 4 pixels) (entry 8 camera))))))
        (new FoamView
          (foam foam)
          (width width)
          (height height)
          (camera camera)
          (pixels pixels)
          (group group))))

    (define (write-foam-camera! (gpu Gpu) (view FoamView) (camera RayCamera)) (→ Unit)
      ((● gpu write-buffer) (● view camera) 0 (camera-bytes camera (● view width) (● view height))))

    (define (dispatch-foam-view (gpu Gpu) (pass GpuComputePass) (view FoamView)) (→ Unit)
      (dispatch gpu pass (● view foam render) (● view group) (* (● view width) (● view height)) 64))

    (define (read-foam-view (gpu Gpu) (view FoamView)) (→ (Array Vec3d))
      (let* ((n (* (● view width) (● view height)))
             (data (read-storage gpu (● view pixels) (* 16 n))))
        (array-generate n (lambda (i) (three-at data (* 16 i))))))

    (define (release-foam-view (gpu Gpu) (view FoamView)) (→ Unit)
      (for-each (● gpu destroy)
                (list (BindGroupObject (● view group))
                      (BufferObject (● view camera))
                      (BufferObject (● view pixels)))))

    ;; ---- Training ----

    ;; Bind each batch as a separate slice of one reusable index buffer.
    ;; Its binding size is the true ray count. Only the offset is padded
    ;; to WebGPU's 256-byte alignment. Queue order protects each refill.
    (record FoamTrainer
      ((foam DeviceFoam)
       (samples I64)
       (batch I64)
       (pitch I64)
       (rays GpuBuffer)
       (indices GpuBuffer)
       (groups (Array GpuBindGroup))))

    (define (make-foam-trainer (gpu Gpu) (foam DeviceFoam) (samples (Array Sample)) (batch I64))
      (→ FoamTrainer)
      (unless (and (> (array-length samples) 0) (> batch 0) (<= batch (quotient buffer-limit 4)))
        (panic "foam training needs rays and a positive batch fitting the index buffer"))
      (let* ((rays (upload gpu "foam/training" (packed-rays samples) 48 (Nil)))
             (pitch (* 256 (quotient (+ (* 4 batch) 255) 256)))
             (window (min 32 (quotient buffer-limit pitch)))
             (indices (storage-buffer gpu "foam/indices" (* pitch window) (list (CopyDst))))
             (entries
              (append (walk-entries foam) (list (entry 3 rays) (entry 5 (● foam gradients)))))
             (group (lambda (i)
                      (let ((slice
                             (BufferEntry 6 indices (i64->i32 (* i pitch)) (i64->i32 (* 4 batch)))))
                        (kernel-group gpu (● foam learn) 0 "foam/learn" (Cons slice entries)))))
             (groups (array-generate window group)))
        (new FoamTrainer (foam foam) (samples (array-length samples)) (batch batch)
             (pitch pitch) (rays rays) (indices indices) (groups groups))))

    (define (batch-indices (trainer FoamTrainer) (start I64) (count I64)) (→ Bytes)
      (let ((bytes (make-array (* count (● trainer pitch)) (i32->u8 0))))
        (do ((i 0 (+ i 1))) ((= i count) bytes)
          (fold-left (lambda (at id) (pod-write (i64->i32 id) bytes at))
                     (* i (● trainer pitch))
                     (sample-batch (● trainer samples) (● trainer batch) (+ start i))))))

    (define (train-foam! (gpu Gpu) (trainer FoamTrainer) (start I64) (steps I64) (rate F64))
      (→ Unit)
      (unless (and (>= steps 0) (>= rate 0.0) (<= rate 3.4028234663852886e38))
        (panic "foam training needs nonnegative steps and a finite f32 rate"))
      (let* ((foam (● trainer foam))
             (batch (● trainer batch))
             (window (array-length (● trainer groups))))
        ((● gpu write-buffer) (● foam rate) 0 (rate-bytes (/ rate (i64->f64 batch))))
        (do ((k 0 (+ k window))) ((>= k steps) (unit))
          (let* ((count (min window (- steps k)))
                 (encoder ((● gpu create-command-encoder)))
                 (pass ((● gpu begin-compute-pass) encoder)))
            ((● gpu write-buffer) (● trainer indices) 0 (batch-indices trainer (+ start k) count))
            (do ((i 0 (+ i 1))) ((= i count) (unit))
              (dispatch gpu pass (● foam learn) (array-ref (● trainer groups) i) batch 64)
              (update-cells! gpu pass foam))
            ((● gpu end-compute-pass) pass)
            ((● gpu submit) (list ((● gpu finish) encoder)))))))

    (define (release-foam-trainer (gpu Gpu) (trainer FoamTrainer)) (→ Unit)
      (array-for-each (lambda (g) ((● gpu destroy) (BindGroupObject g))) (● trainer groups))
      ((● gpu destroy) (BufferObject (● trainer indices)))
      ((● gpu destroy) (BufferObject (● trainer rays))))

    ))
