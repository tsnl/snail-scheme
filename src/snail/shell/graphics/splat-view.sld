;; Splats drawn by the renderer training descends through, instead of as
;; quads: (snail shell graphics splat-train)'s graph rendered for viewing,
;; lowered to a program that reads a `Splats`'s own buffers, so writing a
;; cloud or transforms to the splats changes what both draw. A frame, in
;; the caller's passes:
;;
;;   (write-view-camera gpu view camera)          ; the quad path's camera
;;   (let ((pass (begin-compute-pass gpu encoder)))
;;     (encode-splat-view gpu pass view)          ; project, bin, blend
;;     (end-compute-pass gpu pass))
;;   (let ((pass (begin-render-pass gpu encoder ...)))
;;     (present-splat-view gpu pass view)         ; the image onto the target
;;     (end-pass gpu pass))
;;
;; The blend is training's: front to back in 16x16 tiles, in floats,
;; stopping where a pixel's transmittance would fall under 1e-4, over
;; black. The quads blend back to front in the target's precision, over
;; what the pass cleared to. Both clamp alpha to 0.99 and skip what is
;; under 1/255, and both cull a gaussian under 1/255 opacity whole. The
;; target's size and the tile entries binning holds are fixed when the
;; view is made: entries past them are dropped.
(define-library (snail shell graphics splat-view)
  (export
   SplatView
   make-splat-view
   write-view-camera
   encode-splat-view
   view-entries
   present-splat-view
   release-splat-view)
  (import
   (snail core base)
   (only (snail shell gpu)
         Gpu
         GpuShaderModule
         GpuRenderPipeline
         GpuBindGroup
         GpuComputePass
         GpuRenderPass
         TextureFormat
         ShaderModuleDescriptor
         RenderPipelineDescriptor
         FragmentState
         ColorTarget
         TriangleList
         CullNone
         BindGroupDescriptor
         RenderPipeline
         BufferEntry
         BindGroupObject
         PipelineObject
         ModuleObject)
   (snail shell graphics pod)
   (snail shell graphics shaders)
   (only (snail shell graphics splat)
         Splats
         SplatCamera
         gaussian-shape
         gaussian-word
         harmonic-words
         harmonic-half)
   (snail shell graphics splat-train)
   (snail shell tensor)
   (snail shell tensor fuse)
   (snail shell tensor lower)
   (only (snail shell tensor eval) bytes->values))
  (begin

    ;; ---- The splats as params ----

    ;; A `Splats`'s buffers as params: each gaussian's record, `Gaussian`,
    ;; a row of 32-bit words; its coefficients' words, f16s two to a word
    ;; (`harmonic-words`); and the transforms table, a column-major 4x4
    ;; matrix a row.
    (record ViewedParams
      ((gaussians View)
       (harmonics View)
       (transforms View)))

    (define (viewed-params (splats Splats)) (→ ViewedParams)
      (new ViewedParams
        (gaussians (param "gaussians"
                          (list (● splats capacity) (quotient (stride gaussian-shape) 4))
                          (Unsigned)))
        (harmonics (param "harmonics" (list (● splats capacity) harmonic-words) (Unsigned)))
        (transforms (param "transforms" (list (● splats transform-capacity) 16) (Float)))))

    ;; The params given the splats' own buffers.
    (define (given-splats (splats Splats) (p ViewedParams)) (→ Given)
      (bound (bound (bound nothing-given (● p gaussians) (● splats gaussians))
                    (● p harmonics)
                    (● splats harmonics))
             (● p transforms)
             (● splats transforms)))

    ;; The params as the training renderer's cloud. Each record is narrowed
    ;; to its fields where its layout puts them: its center's floats from
    ;; their words, its f16s unpacked. Its activated scale and opacity are
    ;; taken back to the logarithm and the logit the renderer activates,
    ;; kept off 0 and 1, where those are infinite. A gaussian under 1/255
    ;; opacity is not live, as the quads cull it, and every degree shades:
    ;; a cloud of a lower degree has zeros above it.
    (define (viewed-cloud (p ViewedParams)) (→ Cloud)
      (let* ((g (● p gaussians))
             (h (● p harmonics))
             (field (lambda (name size) (narrow g 1 (gaussian-word name) size)))
             (size (halves (field "scale-opacity" 2)))
             (alpha (narrow size 1 3 1))
             (opacity (minimum (maximum alpha (scalar 1e-7)) (scalar 0.9999999))))
        (new Cloud
          (means (bitcast (field "position" 3) (Float)))
          (scales (log (maximum (narrow size 1 0 3) (scalar 1e-30))))
          (rotations (halves (field "rotation" 2)))
          (opacities (log (/ opacity (- (scalar 1.0) opacity))))
          (dc (degree-colors h 0))
          (degree1 (degree-colors h 1))
          (degree2 (degree-colors h 2))
          (degree3 (degree-colors h 3))
          (live (greater-equal alpha (scalar (/ 1.0 255.0))))
          (degrees (fill 1.0 (list 3) (Float)))
          (placement (Some (placement-of (● p transforms)
                                         (field "transform" 1)))))))

    ;; Degree d's 2d + 1 colors of each gaussian, unpacked from the words
    ;; they alone hold: those from half `harmonic-half` of its first color,
    ;; and the padding half with them.
    (define (degree-colors (h View) (d I64)) (→ View)
      (let ((colors (+ (* 2 d) 1)) (first (quotient (harmonic-half (* d d)) 2)))
        (reshape (narrow (halves (narrow h 1 first (quotient (+ (* 3 colors) 1) 2)))
                         1
                         0
                         (* 3 colors))
                 (list (list-ref (shape-of h) 0) colors 3))))

    ;; ---- Placement ----

    ;; Each gaussian placed by its row of the transforms table. A row's
    ;; matrix is column-major, so its linear part is the first three
    ;; columns' first three floats, transposed to rows, and its offset is
    ;; the fourth column's. The unmapping's rows are the cross products of
    ;; the linear part's columns, its cofactors, signed by its determinant,
    ;; as the quads' projection carries a direction back. The table's rows
    ;; are worked out first, then each gaussian gathers its own.
    (define (placement-of (transforms View) (rows View)) (→ Placement)
      (let* ((n (list-ref (shape-of transforms) 0))
             (m (reshape transforms (list n 4 4)))
             (column (lambda (c) (reshape (narrow (narrow m 1 c 1) 2 0 3) (list n 3))))
             (cofactors (concat (list (cross (column 1) (column 2))
                                      (cross (column 2) (column 0))
                                      (cross (column 0) (column 1)))
                                1))
             (determinant (sum (* (column 0) (narrow cofactors 1 0 3)) (list 1)))
             (sign (- (scalar 1.0) (* (scalar 2.0) (less determinant (scalar 0.0))))))
        (new Placement
          (linear (gather (transpose (narrow (narrow m 1 0 3) 2 0 3)) rows))
          (offset (gather (column 3) rows))
          (unmapping (gather (* (reshape sign (list n 1 1)) (reshape cofactors (list n 3 3)))
                             rows)))))

    ;; Each row's cross product, n x 3 by n x 3.
    (define (cross (a View) (b View)) (→ View)
      (let ((at (lambda (v k) (narrow v 1 k 1))))
        (concat (list (- (* (at a 1) (at b 2)) (* (at a 2) (at b 1)))
                      (- (* (at a 2) (at b 0)) (* (at a 0) (at b 2)))
                      (- (* (at a 0) (at b 1)) (* (at a 1) (at b 0))))
                1)))

    ;; ---- Cameras ----

    ;; The quad path's camera in COLMAP's convention, as the training
    ;; renderer takes it: the view's rows are right, up and backward, so
    ;; COLMAP's, right, down and forward, are the first and the other two
    ;; negated, and so are the translation's; the focal lengths are the
    ;; same, and the principal point is the target's center.
    (define (colmap-camera (camera SplatCamera)) (→ (List F32))
      (let* ((v (● camera view))
             (row (lambda (i)
                    (map (lambda (c) (signed i (component c i))) (list (● v x) (● v y) (● v z))))))
        (concatenate (list (row 0)
                           (row 1)
                           (row 2)
                           (map (lambda (i) (signed i (component (● v w) i))) (iota 3))
                           (list (● camera focal x)
                                 (● camera focal y)
                                 (/ (● camera viewport x) 2.0)
                                 (/ (● camera viewport y) 2.0))))))

    (define (component (v Vec4f) (i I64)) (→ F32)
      (cond ((= i 0) (● v x))
            ((= i 1) (● v y))
            (else (● v z))))

    (define (signed (i I64) (x F32)) (→ F32)
      (if (= i 0) x (- 0.0 x)))

    ;; ---- The view ----

    ;; The lowered render, whose sinks are the image and how many tile
    ;; entries binning asked for; the target's size; and the triangle that
    ;; presents the image: its shader, pipeline and bind group.
    (record SplatView
      ((program Program)
       (width I64)
       (height I64)
       (present-module GpuShaderModule)
       (present-pipeline GpuRenderPipeline)
       (present-group GpuBindGroup)))

    ;; The splats as the training renderer sees them, onto a target of
    ;; `format`, `width` by `height` pixels, binning at most `entries`
    ;; tile entries. The program is given the splats' gaussians,
    ;; coefficients and transforms, and makes the rest.
    (define (make-splat-view (gpu Gpu) (splats Splats)
                             (format TextureFormat)
                             (width I64)
                             (height I64)
                             (entries I64))
      (→ SplatView)
      (let* ((p (viewed-params splats))
             (sensor (new Sensor (width width) (height height) (capacity entries)))
             (drawn (render (viewed-cloud p) (camera-param) sensor (Viewing)))
             (program (lower-with gpu "splat view"
                                  (fuse (list (● drawn image) (● drawn entries)))
                                  (Nil)
                                  (given-splats splats p)))
             (module (present-module-of gpu width)))
        (presenting gpu program sensor module (present-pipeline-of gpu module format))))

    (define (presenting (gpu Gpu) (program Program)
                        (sensor Sensor)
                        (module GpuShaderModule)
                        (pipeline GpuRenderPipeline))
      (→ SplatView)
      (new SplatView
        (program program)
        (width (● sensor width))
        (height (● sensor height))
        (present-module module)
        (present-pipeline pipeline)
        (present-group ((● gpu create-bind-group)
                        (new BindGroupDescriptor
                          (label "splat/present")
                          (pipeline (RenderPipeline pipeline))
                          (group 0)
                          (entries (list (BufferEntry 0
                                                      (sink-buffer program 0)
                                                      0
                                                      0))))))))

    (define (present-module-of (gpu Gpu) (width I64)) (→ GpuShaderModule)
      ((● gpu create-shader-module)
       (new ShaderModuleDescriptor
         (label "splat/present")
         (code (string-append "const WIDTH = "
                              (show width)
                              "u;\n"
                              splat-present-shader)))))

    (define (present-pipeline-of (gpu Gpu) (module GpuShaderModule) (format TextureFormat))
      (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label "splat/present")
         (module module)
         (vertex-entry "present_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "present_fragment")
                           (targets
                            (list (Some (new ColorTarget
                                          (format format)
                                          (blend (None)))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    ;; ---- A frame ----

    ;; The camera the next frame is seen from.
    (define (write-view-camera (gpu Gpu) (view SplatView) (camera SplatCamera)) (→ Unit)
      (write-param gpu (● view program) "camera" (pack (shape) (colmap-camera camera))))

    ;; Projecting, binning and blending, into the caller's compute pass.
    (define (encode-splat-view (gpu Gpu) (pass GpuComputePass) (view SplatView)) (→ Unit)
      (encode-steps gpu pass (● view program)))

    ;; How many tile entries the last frame's binning asked for, which past
    ;; the view's room for them dropped the rest.
    (define (view-entries (gpu Gpu) (view SplatView)) (→ I64)
      (f64->i64 (array-ref (bytes->values (read-sink gpu (● view program) 1) (Float)) 0)))

    ;; The image blended, covering the caller's render pass's target.
    (define (present-splat-view (gpu Gpu) (pass GpuRenderPass) (view SplatView)) (→ Unit)
      ((● gpu set-pipeline) pass (● view present-pipeline))
      ((● gpu set-bind-group) pass 0 (● view present-group))
      ((● gpu draw) pass 3 1 0 0))

    ;; What the view made goes at the next submit; the splats' buffers stay.
    (define (release-splat-view (gpu Gpu) (view SplatView)) (→ Unit)
      (release-program gpu (● view program))
      (for-each (lambda (object) ((● gpu destroy) object))
                (list (BindGroupObject (● view present-group))
                      (PipelineObject (● view present-pipeline))
                      (ModuleObject (● view present-module)))))

    ))
