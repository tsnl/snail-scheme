;; 3D Gaussian Splatting (Kerbl et al. 2023) as middleware: gaussians in a
;; storage buffer, each placed by its row of a transforms table, projected
;; to screen-space ellipses by a compute pass, sorted far to near by
;; (snail shell graphics radix-sort), and blended in one instanced draw.
;; A program makes its `Splats` once with room for its gaussians and its
;; transforms, writes clouds of gaussians where it likes, and writes the
;; transforms whenever they move, so clouds are posed and composed without
;; touching their gaussians. A frame:
;;
;;   (write-transforms splats (list pose-a pose-b))
;;   (sort-splats encoder splats camera)             ; a compute pass
;;   (let ((pass (begin-render-pass encoder ...)))   ; onto the target
;;     (draw-splats pass splats)
;;     (end-pass pass))
;;
;; Gaussians a program has not written are zero, so transparent, and
;; culled. Each gaussian carries the 16 spherical-harmonic coefficients of
;; degree 3, those of lower degrees' clouds 0 above their degree.
(define-library (snail shell graphics splat)
  (export
   Gaussian
   SplatCamera
   Projected
   gaussian-shape
   harmonic-floats
   Cloud
   pack-cloud
   cloud-center
   splat-camera
   Splats
   make-splats
   write-cloud
   write-transforms
   sort-splats
   draw-splats
   release-splats)
  (import
   (snail core base)
   (only (snail shell math) tan)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics radix-sort)
   (snail shell graphics shaders))
  (begin

    ;; ---- Interfaces ----

    ;; A gaussian where its transform puts the origin: its center, its row
    ;; of the transforms table, its orientation as a unit quaternion x, y,
    ;; z, w, its standard deviations along its axes, and its opacity, from
    ;; 0 to 1. Values are activated already: a 3DGS file's log scales and
    ;; opacity logits are taken through exp and the sigmoid when read.
    (record Gaussian
      ((position Vec3f)
       (transform I32)
       (rotation Vec4f)
       (scale Vec3f)
       (opacity F32))
      (deriving Pod))

    ;; The camera: the view matrix, looking down -z; the eye; the focal
    ;; lengths in pixels across and up; and the target's size in pixels.
    (record SplatCamera
      ((view Mat4x4f)
       (eye Vec4f)
       (focal Vec2f)
       (viewport Vec2f))
      (deriving Pod))

    ;; A gaussian on the screen, as the projection writes it for the draw:
    ;; its conic (the inverse 2D covariance's xx, xy and yy), its color and
    ;; opacity, its center in pixels from the target's center, and the
    ;; radius in pixels its square covers, 0 when it is culled.
    (record Projected
      ((conic Vec4f)
       (color Vec4f)
       (center Vec2f)
       (radius F32))
      (deriving Pod))

    (define gaussian-shape (→ (Shape Gaussian)) (shape))

    (define camera-shape (→ (Shape SplatCamera)) (shape))

    (define projected-shape (→ (Shape Projected)) (shape))

    (define transform-shape (→ (Shape Mat4x4f)) (shape))

    ;; Each gaussian's coefficients, 16 colors, are 48 floats: coefficient
    ;; k's red, green and blue at 3k, 3k + 1 and 3k + 2.
    (define harmonic-floats (→ I64) 48)

    (define project-code
      (→ String)
      (string-append (declarations gaussian-shape)
                     (declarations camera-shape)
                     (declarations projected-shape)
                     splat-project-shader))

    (define draw-code
      (→ String)
      (string-append (declarations camera-shape) (declarations projected-shape) splat-draw-shader))

    ;; ---- Clouds ----

    ;; Gaussians packed for the GPU: `count` of them, their records at the
    ;; stride of `gaussian-shape`, and their coefficients, 48 floats each.
    (record Cloud
      ((count I64)
       (gaussians Bytes)
       (harmonics Bytes)))

    ;; Gaussians with their coefficients, each a list of up to 16 colors
    ;; from degree 0; those missing are 0.

    (define (pack-cloud (gaussians (List Gaussian)) (harmonics (List (List Vec3f)))) (→ Cloud)
      (new Cloud
        (count (length gaussians))
        (gaussians (pack gaussian-shape gaussians))
        (harmonics (pack (shape)
                         (concatenate (map (lambda (colors)
                                             (take (append (concatenate (map color-floats colors))
                                                           (map (lambda (_) 0.0)
                                                                (iota harmonic-floats)))
                                                   harmonic-floats))
                                           harmonics))))))

    ;; Gaussian `i`'s center, read back from its packed record, whose
    ;; first field it is.
    (define (cloud-center (cloud Cloud) (i I64)) (→ (List F64))
      (let ((byte (lambda (at shift)
                    (i32-shift-left (u8->i32 (array-ref (● cloud gaussians) at)) shift))))
        (map (lambda (axis)
               (let ((at (+ (* i (stride gaussian-shape)) (* 4 axis))))
                 (f32->f64 (bits->f32 (i32-or (i32-or (byte at 0) (byte (+ at 1) 8))
                                              (i32-or (byte (+ at 2) 16) (byte (+ at 3) 24)))))))
             (iota 3))))

    (define (color-floats (color Vec3f)) (→ (List F32))
      (list (● color x) (● color y) (● color z)))

    ;; ---- Cameras ----

    ;; A pinhole at `eye` looking at `target` with `up` up the screen, its
    ;; vertical field of view `fov` in radians, onto a target of `width`
    ;; by `height` pixels.

    (define (splat-camera (eye Vec3f) (target Vec3f) (up Vec3f) (fov F64) (width I32) (height I32))
      (→ SplatCamera)
      (let ((focal (/ (* 0.5 (i32->f64 height)) (tan (/ fov 2.0)))))
        (new SplatCamera
          (view (look-at (vec eye) (vec target) (vec up)))
          (eye (new Vec4f (x (● eye x)) (y (● eye y)) (z (● eye z)) (w 1.0)))
          (focal (new Vec2f (x (f64->f32 focal)) (y (f64->f32 focal))))
          (viewport (new Vec2f (x (i32->f32 width)) (y (i32->f32 height)))))))

    ;; The view matrix: right, up and backward as its rows, then the eye
    ;; moved to the origin.

    (define (look-at (eye (List F64)) (target (List F64)) (up (List F64))) (→ Mat4x4f)
      (let* ((f (normalized (minus target eye)))
             (r (normalized (cross f up)))
             (u (cross r f))
             (row (lambda (axis sign) (map (lambda (x) (* sign x)) axis))))
        (columns (list (row r 1.0) (row u 1.0) (row f -1.0))
                 (list (negate (dot r eye)) (negate (dot u eye)) (dot f eye)))))

    ;; A matrix from the rows of its linear part and its translation.

    (define (columns (rows (List (List F64))) (translation (List F64))) (→ Mat4x4f)
      (let ((column (lambda (c)
                      (new Vec4f
                        (x (f64->f32 (list-ref (list-ref rows 0) c)))
                        (y (f64->f32 (list-ref (list-ref rows 1) c)))
                        (z (f64->f32 (list-ref (list-ref rows 2) c)))
                        (w 0.0)))))
        (new Mat4x4f
          (x (column 0))
          (y (column 1))
          (z (column 2))
          (w (new Vec4f
               (x (f64->f32 (list-ref translation 0)))
               (y (f64->f32 (list-ref translation 1)))
               (z (f64->f32 (list-ref translation 2)))
               (w 1.0))))))

    (define (vec (v Vec3f)) (→ (List F64))
      (list (f32->f64 (● v x)) (f32->f64 (● v y)) (f32->f64 (● v z))))

    (define (minus (a (List F64)) (b (List F64))) (→ (List F64))
      (map (lambda (i) (- (list-ref a i) (list-ref b i))) (iota 3)))

    (define (dot (a (List F64)) (b (List F64))) (→ F64)
      (fold-left (lambda (sum i) (+ sum (* (list-ref a i) (list-ref b i)))) 0.0 (iota 3)))

    (define (normalized (v (List F64))) (→ (List F64))
      (let ((l (sqrt (dot v v)))) (map (lambda (x) (/ x l)) v)))

    (define (cross (a (List F64)) (b (List F64))) (→ (List F64))
      (list (- (* (list-ref a 1) (list-ref b 2)) (* (list-ref a 2) (list-ref b 1)))
            (- (* (list-ref a 2) (list-ref b 0)) (* (list-ref a 0) (list-ref b 2)))
            (- (* (list-ref a 0) (list-ref b 1)) (* (list-ref a 1) (list-ref b 0)))))

    ;; ---- Splats ----

    ;; What a program keeps: its capacities; the gaussians, their
    ;; coefficients and the transforms; the camera's uniform; what the
    ;; projection writes for the draw, and the keys and values it sorts;
    ;; the sorter; and the projection's and the draw's shaders, pipelines
    ;; and bind groups.
    (record Splats
      ((capacity I64)
       (transform-capacity I64)
       (gaussians GpuBuffer)
       (harmonics GpuBuffer)
       (transforms GpuBuffer)
       (camera GpuBuffer)
       (projected GpuBuffer)
       (keys GpuBuffer)
       (values GpuBuffer)
       (sorter Sorter)
       (project-module GpuShaderModule)
       (project-pipeline GpuComputePipeline)
       (project-group GpuBindGroup)
       (draw-module GpuShaderModule)
       (draw-pipeline GpuRenderPipeline)
       (draw-group GpuBindGroup)))

    ;; Room for `capacity` gaussians and `transform-capacity` transforms,
    ;; drawn onto a target of `format`. Every transform starts as the
    ;; identity. The projection reads the camera, gaussians, coefficients
    ;; and transforms, and writes the projected gaussians, keys and values;
    ;; the draw reads the camera, the projected gaussians, and the values
    ;; in sorted order.

    (define (make-splats (gpu Gpu) (label String)
                         (format TextureFormat)
                         (capacity I64)
                         (transform-capacity I64))
      (→ Splats)
      (! mut)
      (let* ((buffer (lambda (name size) (storage-buffer gpu (string-append label "/" name) size)))
             (camera (camera-buffer gpu label))
             (gaussians (buffer "gaussians" (* capacity (stride gaussian-shape))))
             (harmonics (buffer "harmonics" (* capacity (* 4 harmonic-floats))))
             (transforms (buffer "transforms" (* transform-capacity 64)))
             (projected (buffer "projected" (* capacity (stride projected-shape))))
             (keys (buffer "keys" (* capacity 4)))
             (values (buffer "values" (* capacity 4)))
             (project-module (module-of gpu "splat/project" project-code))
             (project-pipeline (project-pipeline-of gpu project-module))
             (draw-module (module-of gpu "splat/draw" draw-code))
             (draw-pipeline (draw-pipeline-of gpu draw-module format)))
        (write-buffer gpu transforms
                      0
                      (pack transform-shape (map (lambda (_) identity) (iota transform-capacity))))
        (new Splats
          (capacity capacity)
          (transform-capacity transform-capacity)
          (gaussians gaussians)
          (harmonics harmonics)
          (transforms transforms)
          (camera camera)
          (projected projected)
          (keys keys)
          (values values)
          (sorter (make-sorter gpu (string-append label "/order") keys values capacity 32))
          (project-module project-module)
          (project-pipeline project-pipeline)
          (project-group
           (splat-group gpu label
                        (ComputePipeline project-pipeline)
                        (list camera gaussians harmonics transforms projected keys values)))
          (draw-module draw-module)
          (draw-pipeline draw-pipeline)
          (draw-group
           (splat-group gpu label (RenderPipeline draw-pipeline) (list camera projected values))))))

    (define (storage-buffer (gpu Gpu) (label String) (size I64)) (→ GpuBuffer) (! mut)
      (create-buffer gpu (new BufferDescriptor
                           (label label)
                           (size (i64->i32 size))
                           (usage (list (Storage) (CopySrc) (CopyDst))))))

    (define (camera-buffer (gpu Gpu) (label String)) (→ GpuBuffer) (! mut)
      (create-buffer gpu (new BufferDescriptor
                           (label (string-append label "/camera"))
                           (size (i64->i32 (stride camera-shape)))
                           (usage (list (Uniform) (CopyDst))))))

    (define identity
      (→ Mat4x4f)
      (columns (list (list 1.0 0.0 0.0) (list 0.0 1.0 0.0) (list 0.0 0.0 1.0)) (list 0.0 0.0 0.0)))

    ;; A group binding each buffer whole, at bindings 0, 1, and so on.

    (define (splat-group (gpu Gpu) (label String) (pipeline GpuPipeline) (buffers (List GpuBuffer)))
      (→ GpuBindGroup)
      (! mut)
      (create-bind-group gpu (new BindGroupDescriptor
                               (label (string-append "splat/" label))
                               (pipeline pipeline)
                               (group 0)
                               (entries (map-indexed (lambda (binding buffer)
                                                       (BufferEntry (i64->i32 binding) buffer 0 0))
                                                     buffers)))))

    (define (module-of (gpu Gpu) (label String) (code String)) (→ GpuShaderModule) (! mut)
      (create-shader-module gpu (new ShaderModuleDescriptor (label label) (code code))))

    (define (project-pipeline-of (gpu Gpu) (module GpuShaderModule)) (→ GpuComputePipeline) (! mut)
      (create-compute-pipeline gpu
                               (new ComputePipelineDescriptor
                                 (label "splat/project")
                                 (module module)
                                 (entry "project"))))

    ;; Squares blended over what is drawn, untested by depth.

    (define (draw-pipeline-of (gpu Gpu) (module GpuShaderModule) (format TextureFormat))
      (→ GpuRenderPipeline)
      (! mut)
      (create-render-pipeline gpu
                              (new RenderPipelineDescriptor
                                (label "splat/draw")
                                (module module)
                                (vertex-entry "splat_vertex")
                                (buffers (Nil))
                                (fragment (Some (new FragmentState
                                                  (entry "splat_fragment")
                                                  (targets
                                                   (list (Some (new ColorTarget
                                                                 (format format)
                                                                 (blend (Some over)))))))))
                                (topology (TriangleStrip))
                                (cull (CullNone))
                                (depth (None)))))

    ;; ---- Writing ----

    ;; A cloud's gaussians from gaussian `first` on, 65,536 at a time: a
    ;; write's bytes are copied whole into the runtime's memory on their
    ;; way to the device, and a trained scene's coefficients run to
    ;; hundreds of megabytes.

    (define (write-cloud (gpu Gpu) (splats Splats) (first I64) (cloud Cloud)) (→ Unit) (! mut)
      (unless (<= (+ first (● cloud count)) (● splats capacity))
        (panic "splat: the cloud does not fit in its splats"))
      (for-each (lambda (from)
                  (let ((to (min (● cloud count) (+ from 65536))))
                    (write-rows gpu (● splats gaussians)
                                (stride gaussian-shape)
                                (+ first from)
                                (● cloud gaussians)
                                from
                                to)
                    (write-rows gpu (● splats harmonics)
                                (* 4 harmonic-floats)
                                (+ first from)
                                (● cloud harmonics)
                                from
                                to)))
                (map (lambda (k) (* k 65536)) (iota (quotient (+ (● cloud count) 65535) 65536)))))

    ;; Rows `from` to `to` of `bytes`, each `width` bytes, written at row
    ;; `at` of a buffer.
    (define (write-rows (gpu Gpu) (buffer GpuBuffer)
                        (width I64)
                        (at I64)
                        (bytes Bytes)
                        (from I64)
                        (to I64))
      (→ Unit)
      (! mut)
      (write-buffer gpu
                    buffer
                    (i64->i32 (* at width))
                    (subarray bytes (* from width) (* to width))))

    ;; The transforms table from its first row; rows not given keep theirs.

    (define (write-transforms (gpu Gpu) (splats Splats) (transforms (List Mat4x4f)))
      (→ Unit)
      (! mut)
      (unless (<= (length transforms) (● splats transform-capacity))
        (panic "splat: more transforms than the splats have room for"))
      (write-buffer gpu (● splats transforms) 0 (pack transform-shape transforms)))

    ;; ---- Drawing ----

    ;; A compute pass that projects every gaussian under the camera and
    ;; sorts them far to near.

    (define (sort-splats (gpu Gpu) (encoder GpuCommandEncoder) (splats Splats) (camera SplatCamera))
      (→ Unit)
      (! mut)
      (write-buffer gpu (● splats camera) 0 (pod-bytes camera-shape camera))
      (let ((pass (begin-compute-pass gpu encoder)))
        (set-compute-pipeline gpu pass (● splats project-pipeline))
        (set-compute-bind-group gpu pass 0 (● splats project-group))
        (dispatch-workgroups gpu pass (i64->i32 (quotient (+ (● splats capacity) 255) 256)) 1 1)
        (dispatch-sort gpu pass (● splats sorter))
        (end-compute-pass gpu pass)))

    ;; Every gaussian, in the order the last `sort-splats` found, onto a
    ;; target whose size the camera gave.

    (define (draw-splats (gpu Gpu) (pass GpuRenderPass) (splats Splats)) (→ Unit) (! mut)
      (set-pipeline gpu pass (● splats draw-pipeline))
      (set-bind-group gpu pass 0 (● splats draw-group))
      (draw gpu pass 4 (i64->i32 (● splats capacity)) 0 0))

    ;; Everything the splats made goes at the next submit.
    (define (release-splats (gpu Gpu) (s Splats)) (→ Unit) (! mut)
      (release-sorter gpu (● s sorter))
      (for-each (lambda (object) (destroy gpu object))
                (append (map BufferObject
                             (list (● s gaussians)
                                   (● s harmonics)
                                   (● s transforms)
                                   (● s camera)
                                   (● s projected)
                                   (● s keys)
                                   (● s values)))
                        (list (BindGroupObject (● s project-group))
                              (ComputePipelineObject (● s project-pipeline))
                              (ModuleObject (● s project-module))
                              (BindGroupObject (● s draw-group))
                              (PipelineObject (● s draw-pipeline))
                              (ModuleObject (● s draw-module))))))

    ))
