;; Forward-lit instances grouped by reusable batch versions.
(define-library (snail shell graphics renderer batches)
  (export
   Frame
   Vec3
   Camera
   Light
   Projection
   Perspective
   Orthographic
   Mesh
   Box
   Pyramid
   Prism
   Sphere
   Tile
   Tetrahedron
   Octahedron
   Upright
   Item
   Item-position-set
   Item-scale-set
   Item-yaw-set
   Item-color-set
   Item-glow-set
   Item-from-set
   item
   rgb
   Style Solid Translucent Revealed Batch
   BatchState batch-state render-batch-frame! restore-batch! replay-batch-frame! release-batches!)
  (import
   (except (snail core base) instance)
   (snail core table)
   (snail core io)
   (snail shell json)
   (snail shell wire)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics mesh)
   (rename (snail shell graphics raster) (Style Raster-style) (solid solid-style))
   (snail shell graphics passes)
   (snail shell graphics forward frame)
   (snail shell graphics compositor)
   (snail shell graphics api-trace))
  (begin
    ;; ---- Frames ----

    ;; A 3D scene: a camera, the light, a 0xRRGGBB background, how far from
    ;; 0 to 1 every item has moved from where it was toward where it is,
    ;; and the batches of items. Its meshes are those of
    ;; `(snail shell graphics mesh)`, each standing on y = 0 within the
    ;; unit cell around the origin.
    (record Frame
      ((camera Camera)
       (light Light)
       (background I32)
       (motion F32)
       (batches (List Batch))))

    (record Vec3
      ((x F32)
       (y F32)
       (z F32))
      (deriving Serialize Deserialize))

    ;; A perspective projection with a vertical field of view, or an
    ;; orthographic one showing `height` world units from the bottom of the
    ;; screen to the top.
    (enum Projection
      (Perspective ((fov F32)))
      (Orthographic ((height F32)))
      (deriving Serialize Deserialize))

    ;; Up is +y.
    (record Camera
      ((eye Vec3)
       (target Vec3)
       (projection Projection))
      (deriving Serialize Deserialize))

    ;; Sunlight shining from `direction` with strength `sun`, and the light
    ;; every surface receives whichever way it faces.
    (record Light
      ((direction Vec3)
       (sun F32)
       (ambient F32))
      (deriving Serialize Deserialize))

    ;; ---- Items ----

    ;; A mesh instance: position, scale, rotation about the vertical axis, a
    ;; 0xRRGGBB color, and a glow from 0, lit by the light, to 1, its own
    ;; color. It moves from `from` to `position` as the frame's motion goes
    ;; from 0 to 1, so a frame animates it without new items. Surfaces are
    ;; matte.
    (record Item
      ((mesh Mesh)
       (position Vec3)
       (scale Vec3)
       (yaw F32)
       (color I32)
       (glow F32)
       (from Vec3))
      (deriving Serialize Deserialize))

    ;; A 0xRRGGBB color.

    (define (rgb (red I32) (green I32) (blue I32)) (→ I32)
      (+ (* red 65536) (+ (* green 256) blue)))

    ;; An unlit, plain item standing still.

    (define (item (mesh Mesh) (position Vec3) (scale Vec3) (yaw F32) (color I32)) (→ Item)
      (new Item
        (mesh mesh)
        (position position)
        (scale scale)
        (yaw yaw)
        (color color)
        (glow 0.0)
        (from position)))

    ;; Solid batches hide what is behind them. Translucent ones are drawn
    ;; after, over them. A revealed batch shows only within `radius` of a
    ;; point on the ground. Styles cost nothing to change between frames.
    (enum Style
      (Solid)
      (Translucent ((opacity F32)))
      (Revealed ((center Vec3) (radius F32)))
      (deriving Serialize Deserialize))

    ;; A batch's instances are kept until its version changes, so `items`
    ;; runs only when its version is new.
    (record Batch
      ((key I32)
       (version I32)
       (style Style)
       (items (Fn → (List Item)))))

    ;; ---- Drawing ----

    ;; The batched forward renderer owns a color output, a single depth buffer
    ;; and its post targets. Static batch versions survive a resize.
    (record Drawn
      ((raster Raster)
       (depth Plane)
       (output Plane)
       (post Post)
       (surfaces (List Kept))))

    ;; A batch's surface, and the version it shows.
    (record Kept
      ((key I32)
       (version I32)
       (surface Surface)))

    (record BatchState
      ((drawn (Option Drawn))
       (instances (Table (List Item)))))
    (define (batch-state) (→ BatchState) (new BatchState (drawn (None)) (instances (empty-table))))
    (define (started (gpu Gpu) (w I32) (h I32)) (→ Drawn)
      (new Drawn (raster (make-forward-batches gpu light-format))
           (depth (batch-depth gpu w h)) (output (display-plane gpu w h))
           (post (make-post gpu (Rgba8Unorm) w h (Neutral)))
           (surfaces (Nil))))

    (define (batch-depth (gpu Gpu) (w I32) (h I32)) (→ Plane)
      (make-plane gpu "forward/batch-depth" w h (Depth24Plus) (list (RenderAttachment))))

    (define (drawn-frame (gpu Gpu)
                         (encoder GpuCommandEncoder)
                         (state BatchState)
                         (frame Frame)
                         (w I32)
                         (h I32))
      (→ Plane)
      (let* ((drawn (match (● state drawn) ((Some previous) previous) (_ (started gpu w h))))
             (drawn (surfaced gpu (resized gpu drawn w h) frame))
             (pass (begin-forward-pass gpu encoder (● drawn post targets light-view) (None)
                                       (rgb-color (● frame background))
                                       (Some (new DepthAttachment
                                               (view (● drawn depth view))
                                               (load (ClearDepth 1.0))
                                               (store #f))))))
        (write-raster gpu (● drawn raster) (frame-camera frame w h) (frame-sun (● frame light)))
        (draw-surfaces gpu pass drawn #f)
        (draw-surfaces gpu pass drawn #t)
        ((● gpu end-pass) pass)
        (draw-post gpu encoder (● drawn output view) (● drawn post))
        (set! (● state drawn) (Some drawn)) (● drawn output)))

    (define (resized (gpu Gpu) (drawn Drawn) (w I32) (h I32)) (→ Drawn)
      (unless (and (= w (● drawn post targets width)) (= h (● drawn post targets height)))
        (release-plane gpu (● drawn depth)) (release-plane gpu (● drawn output))
        (set! (● drawn depth) (batch-depth gpu w h)) (set! (● drawn output) (display-plane gpu w h))
        (set! (● drawn post) (resize-post gpu (● drawn post) w h)))
      drawn)

    ;; A surface for each of the frame's batches; those of batches gone
    ;; from it are released.
    (define (surfaced (gpu Gpu) (drawn Drawn) (frame Frame)) (→ Drawn)
      (let ((surfaces (map (lambda (batch) (batch-surface gpu drawn batch)) (● frame batches))))
        (for-each (lambda (kept)
                    (unless (any? (lambda (now) (= (● now key) (● kept key))) surfaces)
                      (release-surface gpu (● kept surface))))
                  (● drawn surfaces))
        (Drawn-surfaces-set drawn surfaces)))

    ;; The batch's surface, restyled when it shows the batch's version, and
    ;; made afresh, releasing the old, when it does not.
    (define (batch-surface (gpu Gpu) (drawn Drawn) (batch Batch)) (→ Kept)
      (match (find (lambda (kept) (= (● kept key) (● batch key))) (● drawn surfaces))
        ((Some kept)
         (if (and (= (● kept version) (● batch version))
                  (if (● kept surface translucent) (translucent? batch) (not (translucent? batch))))
             (Kept-surface-set kept (restyle-surface gpu (● kept surface) (batch-style batch)))
             (begin
               (release-surface gpu (● kept surface))
               (new-surface gpu drawn batch))))
        ((None) (new-surface gpu drawn batch))))

    (define (new-surface (gpu Gpu) (drawn Drawn) (batch Batch)) (→ Kept)
      (new Kept
        (key (● batch key))
        (version (● batch version))
        (surface (make-surface gpu (● drawn raster)
                               (batch-name batch)
                               (translucent? batch)
                               (batch-style batch)
                               (meshes (map instance-of ((● batch items))))))))

    ;; The kept surfaces that are translucent, or not, in order.
    (define (draw-surfaces (gpu Gpu) (pass GpuRenderPass) (drawn Drawn) (translucent Bool))
      (→ Unit)
      (for-each (lambda (kept)
                  (let ((surface (● kept surface)))
                    (when (if translucent (● surface translucent) (not (● surface translucent)))
                      (draw-surface gpu pass (● drawn raster) surface))))
                (● drawn surfaces)))

    (define (instance-of (item Item)) (→ (Pair Mesh Instance))
      (let ((position (● item position))
            (scale (● item scale))
            (from (● item from))
            (color (● item color)))
        (new Pair
          (first (● item mesh))
          (second (new Instance
                    (place (vec4 position (● item yaw)))
                    (scale (vec4 scale (● item glow)))
                    (color (new Vec4f
                             (x (channel color 16))
                             (y (channel color 8))
                             (z (channel color 0))
                             (w 1.0)))
                    (from (vec4 from 0.0))
                    (material (new Vec2f (x 0.0) (y 1.0))))))))

    (define (vec4 (v Vec3) (w F32)) (→ Vec4f)
      (new Vec4f (x (● v x)) (y (● v y)) (z (● v z)) (w w)))

    (define (channel (color I32) (shift I32)) (→ F32)
      (/ (i32->f32 (i32-and (i32-shift-right/logical color shift) 255)) 255.0))

    (define (frame-camera (frame Frame) (width I32) (height I32)) (→ Camera3D)
      (let ((view (● frame camera)))
        (camera-3d (vec3f (● view eye))
                   (vec3f (● view target))
                   (match (● view projection)
                     ((Perspective fov) (Pinhole (f32->f64 fov)))
                     ((Orthographic height) (Parallel (f32->f64 height))))
                   (/ (i32->f64 width) (i32->f64 (max 1 height)))
                   (● frame motion))))

    (define (vec3f (v Vec3)) (→ Vec3f) (new Vec3f (x (● v x)) (y (● v y)) (z (● v z))))

    (define (frame-sun (light Light)) (→ Sun)
      (new Sun (direction (vec4 (● light direction) (● light sun))) (ambient (● light ambient))))

    (define (translucent? (batch Batch)) (→ Bool)
      (match (● batch style)
        ((Translucent _) #t)
        (_ #f)))

    ;; Batch k's objects are labelled "batch k".
    (define (batch-name (batch Batch)) (→ String) (string-append "batch " (show (● batch key))))

    (define (batch-style (batch Batch)) (→ Raster-style)
      (match (● batch style)
        ((Solid) solid-style)
        ((Translucent opacity)
         (new Raster-style (opacity opacity) (center-x 0.0) (center-z 0.0) (radius -1.0)))
        ((Revealed center radius)
         (new Raster-style
           (opacity 1.0)
           (center-x (● center x))
           (center-z (● center z))
           (radius radius)))))

    ;; ---- Recording and replay ----

    ;; A batch version contributes its instances exactly once. Styles and camera
    ;; parameters can change every frame without invalidating the instance cache.
    (record BatchVersion
      ((key I32)
       (version I32)
       (style Style)) (deriving Serialize Deserialize))
    (record BatchView
      ((camera Camera)
       (light Light)
       (background I32)
       (motion F32)
       (order (List BatchVersion))) (deriving Serialize Deserialize))
    (define (batch-view (f Frame)) (→ BatchView)
      (new BatchView
        (camera (● f camera))
        (light (● f light))
        (background (● f background))
        (motion (● f motion))
        (order (map (lambda (b)
                      (new BatchVersion
                        (key (● b key))
                        (version (● b version))
                        (style (● b style))))
                    (● f batches)))))
    (define (capture-batch (out OutputPort) (b Batch)) (→ Batch)
      (Batch-items-set b (lambda ()
                           (let ((items ((● b items))))
                             (write-command! out
                                             "setBatch"
                                             (JsonInteger (i32->i64 (● b key)))
                                             (list (serialize items)))
                             items))))
    (define (render-batch-frame! (gpu Gpu) (encoder GpuCommandEncoder)
                                 (state BatchState)
                                 (f Frame)
                                 (w I32)
                                 (h I32)
                                 (out (Option OutputPort)))
      (→ Plane)
      (match out ((None) (drawn-frame gpu encoder state f w h))
             ((Some port)
              (let ((p (drawn-frame gpu encoder
                                    state
                                    (Frame-batches-set f
                                                       (map (lambda (b) (capture-batch port b))
                                                            (● f batches)))
                                    w
                                    h)))
                (write-command! port
                                "renderBatches"
                                (trace-object (list (trace-field "width" (JsonInteger (i32->i64 w)))
                                                    (trace-field "height"
                                                                 (JsonInteger (i32->i64 h)))))
                                (list (serialize (batch-view f))))
                p))))
    (define (restore-batch! (state BatchState) (cmd ApiCommand)) (→ Unit)
      (set! (● state instances)
            (table-set (● state instances) (show (trace-int (● cmd args))) (command-value cmd 0))))
    (define (saved-batch (state BatchState) (b BatchVersion)) (→ Batch)
      (new Batch (key (● b key)) (version (● b version)) (style (● b style))
           (items (lambda () (match (table-ref (● state instances) (show (● b key)))
                               ((Some items) items) ((None) (panic "missing renderer batch")))))))
    (define (replay-batch-frame! (gpu Gpu)
                                 (encoder GpuCommandEncoder)
                                 (state BatchState)
                                 (cmd ApiCommand)
                                 (w I32)
                                 (h I32))
      (→ Plane)
      (let* ((v (ann (command-value cmd 0) BatchView))
             (f (new Frame (camera (● v camera)) (light (● v light))
                     (background (● v background))
                     (motion (● v motion))
                     (batches (map (lambda (b) (saved-batch state b)) (● v order)))))
             (p (drawn-frame gpu encoder state f w h)))
        ;; Every newly uploaded version now lives on the GPU. A later cache miss
        ;; always has its own setBatch command, including after a removed batch returns.
        (set! (● state instances) (empty-table)) p))
    (define (release-batches! (gpu Gpu) (state BatchState)) (→ Unit)
      (match (● state drawn) ((None) (unit))
             ((Some d) (for-each (lambda (s) (release-surface gpu (● s surface))) (● d surfaces))
              (release-raster gpu (● d raster))
              (release-plane gpu (● d depth))
              (release-plane gpu (● d output))
              (release-post gpu (● d post)) (set! (● state drawn) (None))))))
  )
