;; Cast the same shadow rays before and after moving a box across the street.
;; Keep the query's original bindings to catch stale vertices and stale boxes.
(define-library (gpu-test moving-scene)
  (export moving-shadows bent-shadows)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (only (snail shell graphics animation) Influence SkinBinding rigid-influence v4 unit-matrix)
   (only (snail shell graphics mesh) geometry MeshVertex)
   (snail shell graphics kernel)
   (snail shell graphics bvh)
   (snail shell graphics gltf)
   (snail shell graphics trace scene)
   (only (snail shell app) Item Box Vec3 item)
   (snail shell game scenery))
  (begin
    (define (box-at (x F32)) (→ Item)
      (item (Box) (new Vec3 (x x) (y 0.0) (z 0.0)) (new Vec3 (x 1.0) (y 1.0) (z 1.0)) 0.0 0))

    (define (two-boxes) (→ Gltf)
      (let* ((empty
              (new Gltf (buffers (Nil)) (size 0) (images (Nil)) (materials (Nil)) (placed (Nil))))
             (g (with-shapes empty (list (box-at 5.0) (box-at 0.0))))) g))

    (define (ray (x F32) (limit F32)) (→ (List Vec4f))
      (let ((zero (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 0.0))))
        (list (new Vec4f (x x) (y 3.0) (z 0.15) (w limit))
              (new Vec4f (x 0.0) (y -1.0) (z 0.0) (w 0.0)) zero zero zero)))

    (define (hits (gpu Gpu) (query GpuComputePipeline) (group GpuBindGroup)
                  (rays GpuBuffer) (back GpuBuffer)) (→ String)
                  (let* ((encoder ((● gpu create-command-encoder)))
                         (pass ((● gpu begin-compute-pass) encoder)))
                    (trace-rays gpu pass query group (None) 4)
                    ((● gpu end-compute-pass) pass)
                    ((● gpu copy-buffer-to-buffer) encoder rays 0 back 0 320)
                    ((● gpu submit) (list ((● gpu finish) encoder)))
                    (let ((bytes ((● gpu read-buffer) back 0 320)))
                      (string-join (map (lambda (i)
                                          (if (every? (lambda (b)
                                                        (= (u8->i32
                                                            (array-ref bytes (+ (* 80 i) (+ 36 b))))
                                                           255))
                                                      (iota 4))
                                              "open" "hit")) (iota 4)) " "))))

    (define (moving-shadows (gpu Gpu)) (→ String)
      (let* ((g (two-boxes)) (n (● (list-ref (● g placed) 1) primitive positions count))
             (stage (moving-scene gpu (upload-scene gpu (lambda (_) (Nil)) g 1) (list n))))
        (across gpu stage (lambda (x) (pose-scene! gpu stage (list (item-pose (box-at x))))))))

    ;; The base stays planted. The upper edge is weighted equally to base
    ;; and tip, so a tip displaced by three moves the edge by one and a half.
    (define (bent-shadows (gpu Gpu)) (→ String)
      (let* ((vertices (● (geometry (Box)) vertices))
             (half (new Influence
                     (joints (new Vec4i (x 0) (y 1) (z 0) (w 0)))
                     (weights (v4 0.5 0.5 0.0 0.0))))
             (bindings
              (map (lambda (v) (if (> (● v position y) 0.5) half (rigid-influence 0))) vertices))
             (stage
              (skin-scene gpu
                          (upload-scene gpu (lambda (_) (Nil)) (two-boxes) 1)
                          (list (new SkinBinding (slots 2) (vertices bindings))))))
        (across gpu stage (lambda (x)
                            (let ((palette
                                   (list unit-matrix (pose-matrix (item-pose (box-at (* 2.0 x)))))))
                              (deform-scene! gpu stage palette)
                              (when (> x 0.0)
                                (check-vertices gpu stage vertices x -3.0)
                                (deform-scene! gpu stage palette)
                                (check-vertices gpu stage vertices x 0.0)))))))

    ;; Read exactly the world vertices used by primary rays and SVGF. A
    ;; second draw of the same pose must have zero displacement.
    (define (check-vertices (gpu Gpu)
                            (stage MovingScene)
                            (vertices (List MeshVertex))
                            (shift F32)
                            (motion F32))
      (→ Unit)
      (let* ((size (* vertex-stride (length vertices))) (encoder ((● gpu create-command-encoder)))
             (back ((● gpu create-buffer)
                    (new BufferDescriptor (label "test/skinning") (size (i64->i32 size))
                         (usage (list (CopyDst) (MapRead)))))))
        ((● gpu copy-buffer-to-buffer)
         encoder
         (● stage scene vertices)
         (i64->i32 size)
         back
         0
         (i64->i32 size))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let ((bytes ((● gpu read-buffer) back 0 (i64->i32 size))))
          (for-each (lambda (i)
                      (let* ((p (● (list-ref vertices i) position))
                             (top (> (● p y) 0.5))
                             (at (* vertex-stride i)))
                        (unless (and (< (abs (- (float-at bytes at) (+ (● p x) (if top shift 0.0))))
                                        0.0001)
                                     (< (abs (- (float-at bytes (+ at 52)) (if top motion 0.0)))
                                        0.0001))
                          (panic "incorrect skinned position or motion vector"))))
                    (iota (length vertices))))
        ((● gpu destroy) (BufferObject back))))
    (define (float-at (bytes Bytes) (at I64)) (→ F32)
      (let ((byte (lambda ((k I64) (shift I32))
                    (→ I32)
                    (i32-shift-left (u8->i32 (array-ref bytes (+ at k))) shift))))
        (bits->f32 (i32-or (i32-or (byte 0 0) (byte 1 8)) (i32-or (byte 2 16) (byte 3 24))))))

    (define (across (gpu Gpu) (stage MovingScene) (place! (Fn F32 → Unit))) (→ String)
      (place! -1.5)
      (let* ((tree (build-moving-bvh gpu (scene-triangles (● stage scene))))
             (kernels (make-ray-kernels gpu opaque-cutout))
             (rays (storage-buffer gpu "test/rays" 320 (list (CopySrc) (CopyDst))))
             (counts (storage-buffer gpu "test/count" 4 (list (CopyDst))))
             (group (ray-group gpu (● kernels occlude) tree rays counts 0))
             (back ((● gpu create-buffer)
                    (new BufferDescriptor
                      (label "test/shadows")
                      (size 320)
                      (usage (list (CopyDst) (MapRead)))))))
        ((● gpu write-buffer)
         rays
         0
         (pack (shape)
               (concatenate (list (ray -1.5 2.1) (ray 1.5 2.1) (ray 5.0 4.0) (ray 5.0 1.0)))))
        ((● gpu write-buffer) counts 0 (pod-bytes (shape) (ann 4 I32)))
        (let ((old (hits gpu (● kernels occlude) group rays back)))
          (place! 1.5)
          (refit-bvh! gpu tree)
          (let ((now (hits gpu (● kernels occlude) group rays back)))
            (for-each (lambda (r) ((● gpu destroy) r))
                      (list (BindGroupObject group) (ComputePipelineObject (● kernels occlude))
                            (ComputePipelineObject (● kernels intersect)) (BufferObject back)
                            (BufferObject rays) (BufferObject counts)))
            (release-bvh gpu tree) (release-moving-scene gpu stage)
            (string-append old " / " now)))))))
