;; Interactive applications. An application is three total functions over
;; its state, and two that convert the state to and from what it saves:
;;
;;   init    : seed width height -> State
;;   update  : State Input -> State
;;   view    : State alpha -> Frame
;;   save    : State -> Save
;;   restore : Save -> State
;;
;; `define-application` keeps the current state in one cell and exposes the
;; host entry points. The host forwards raw input and clock ticks, draws each
;; Frame through the `screen` effect, and stores the serialized Save. The
;; Save may be much smaller than the state: a record of how to rebuild it.
(define-library (lofi app)
  (export
   Input
   KeyDown
   KeyUp
   PointerMove
   PointerDown
   PointerUp
   Wheel
   Resize
   Press
   Tick
   key-left
   key-right
   key-up
   key-down
   key-escape
   key-enter
   key-space
   Vec3
   Vec3-x
   Vec3-y
   Vec3-z
   Projection
   Perspective
   Orthographic
   Camera
   Camera-eye
   Camera-target
   Camera-projection
   Light
   Mesh
   Box
   Pyramid
   Prism
   Sphere
   Tile
   Tetrahedron
   Octahedron
   Item
   Item-position
   Item-position-set
   Item-scale
   Item-yaw
   Item-yaw-set
   Item-glow-set
   Item-from
   Item-from-set
   item
   Style
   Solid
   Translucent
   Revealed
   Batch
   Anchor
   TopLeft
   TopRight
   BottomLeft
   BottomRight
   Widget
   Label
   Button
   Meter
   Panel
   Frame
   rgb
   screen
   render
   Ray
   Ray-origin
   Ray-direction
   pointer-ray
   ground-point
   define-application)
  (import
   (lofi base)
   (lofi wire)
   (lofi math))
  (begin

    ;; ---- Input ----

    ;; Keys are lower-case code points, or the named codes below. A press
    ;; reports the action number of a HUD button.
    (enum Input
      (KeyDown ((key I32)))
      (KeyUp ((key I32)))
      (PointerMove ((x I32) (y I32)))
      (PointerDown ((x I32) (y I32) (button I32)))
      (PointerUp ((x I32) (y I32) (button I32)))
      (Wheel ((delta I32)))
      (Resize ((width I32) (height I32)))
      (Press ((action I32)))
      (Tick))

    (define key-left 1)
    (define key-right 2)
    (define key-up 3)
    (define key-down 4)
    (define key-escape 27)
    (define key-enter 13)
    (define key-space 32)

    (: decode-input (-> I32 I32 I32 I32 Input))
    (define (decode-input kind a b c)
      (case kind
        ((1) (KeyDown a))
        ((2) (KeyUp a))
        ((3) (PointerMove a b))
        ((4) (PointerDown a b c))
        ((5) (PointerUp a b c))
        ((6) (Wheel a))
        ((7) (Resize a b))
        ((8) (Press a))
        (else (Tick))))

    ;; ---- Frames ----

    (struct Vec3
      ((x F32)
       (y F32)
       (z F32))
      (deriving Serialize Deserialize))

    ;; A perspective projection with a vertical field of view, or an
    ;; orthographic one showing `height` world units from the bottom of the
    ;; screen to the top.
    (enum Projection
      (Perspective ((fov F32)))
      (Orthographic ((height F32))))

    ;; Up is +y.
    (struct Camera
      ((eye Vec3)
       (target Vec3)
       (projection Projection)))

    ;; Sunlight shining from `direction` with strength `sun`, and the light
    ;; every surface receives whichever way it faces.
    (struct Light
      ((direction Vec3)
       (sun F32)
       (ambient F32)))

    ;; Every mesh stands on y = 0 within the unit cell around the origin; a
    ;; tile is a flat unit square at y = 0.
    (enum Mesh
      (Box)
      (Pyramid)
      (Prism)
      (Sphere)
      (Tile)
      (Tetrahedron)
      (Octahedron))

    ;; A mesh instance: position, scale, rotation about the vertical axis, a
    ;; 0xRRGGBB color, and a glow from 0, lit by the light, to 1, its own
    ;; color. It moves from `from` to `position` as the frame's motion goes
    ;; from 0 to 1, so the host animates it without asking for new items.
    (struct Item
      ((mesh Mesh)
       (position Vec3)
       (scale Vec3)
       (yaw F32)
       (color I32)
       (glow F32)
       (from Vec3)))

    ;; An unlit item standing still.
    (: item (-> Mesh Vec3 Vec3 F32 I32 Item))
    (define (item mesh position scale yaw color)
      (Item mesh position scale yaw color 0.0 position))

    ;; Solid batches hide what is behind them. Translucent ones are drawn
    ;; after, over them. A revealed batch shows only within `radius` of a
    ;; point on the ground. Styles cost nothing to change between frames.
    (enum Style
      (Solid)
      (Translucent ((opacity F32)))
      (Revealed ((center Vec3) (radius F32))))

    ;; The host keeps each batch's instances until its version changes, so
    ;; `items` runs only when the host does not already have them.
    (struct Batch
      ((key I32)
       (version I32)
       (style Style)
       (items (-> (List Item)))))

    (enum Anchor
      (TopLeft)
      (TopRight)
      (BottomLeft)
      (BottomRight))

    ;; A button reports its action through `Press`; a meter shows a fraction.
    (enum Widget
      (Label ((text String)))
      (Button ((text String) (action I32) (selected Bool)))
      (Meter ((text String) (fraction F32))))

    (struct Panel
      ((anchor Anchor)
       (widgets (List Widget))))

    ;; `motion` moves every item from where it was toward where it is.
    (struct Frame
      ((camera Camera)
       (light Light)
       (background I32)
       (motion F32)
       (batches (List Batch))
       (panels (List Panel))))

    (: rgb (-> I32 I32 I32 I32))
    (define (rgb red green blue)
      (+ (* red 65536) (+ (* green 256) blue)))

    ;; ---- Drawing ----

    (effect screen
      ((frame-begin (-> I32 F32 Unit))
       (camera (-> F32 F32 F32 F32 F32 F32 I32 F32 Unit))
       (light (-> F32 F32 F32 F32 F32 Unit))
       (batch-begin (-> I32 I32 I32 F32 F32 F32 F32 Bool))
       (instance (-> I32 F32 F32 F32 F32 F32 F32 F32 I32 F32 F32 F32 F32 Unit))
       (panel-begin (-> I32 Unit))
       (widget-begin (-> I32 I32 F32 Unit))
       (text-character (-> Char Unit))
       (frame-end (-> Unit)))
      (host "snail.screen"
            ((frame-begin "frame-begin")
             (camera "camera")
             (light "light")
             (batch-begin "batch-begin")
             (instance "instance")
             (panel-begin "panel-begin")
             (widget-begin "widget-begin")
             (text-character "text-character")
             (frame-end "frame-end"))))

    (: render (-> Frame Unit ! screen))
    (define (render frame)
      (frame-begin (Frame-background frame) (Frame-motion frame))
      (render-camera (Frame-camera frame))
      (render-light (Frame-light frame))
      (for-each render-batch (Frame-batches frame))
      (for-each render-panel (Frame-panels frame))
      (frame-end))

    (: render-camera (-> Camera Unit ! screen))
    (define (render-camera view)
      (let ((eye (Camera-eye view)) (target (Camera-target view)))
        (match (Camera-projection view)
          ((Perspective fov) (camera (Vec3-x eye) (Vec3-y eye) (Vec3-z eye) (Vec3-x target) (Vec3-y target) (Vec3-z target) 0 fov))
          ((Orthographic height) (camera (Vec3-x eye) (Vec3-y eye) (Vec3-z eye) (Vec3-x target) (Vec3-y target) (Vec3-z target) 1 height)))))

    (: render-light (-> Light Unit ! screen))
    (define (render-light sunlight)
      (let ((direction (Light-direction sunlight)))
        (light (Vec3-x direction) (Vec3-y direction) (Vec3-z direction) (Light-sun sunlight) (Light-ambient sunlight))))

    ;; The style travels with every frame; the items only when the host lacks
    ;; this version.
    (: render-batch (-> Batch Unit ! screen))
    (define (render-batch batch)
      (unless (match (Batch-style batch)
                ((Solid) (batch-begin (Batch-key batch) (Batch-version batch) 0 1.0 0.0 0.0 0.0))
                ((Translucent opacity) (batch-begin (Batch-key batch) (Batch-version batch) 1 opacity 0.0 0.0 0.0))
                ((Revealed center radius) (batch-begin (Batch-key batch) (Batch-version batch) 2 1.0 (Vec3-x center) (Vec3-z center) radius)))
        (for-each render-item ((Batch-items batch)))))

    (: render-item (-> Item Unit ! screen))
    (define (render-item item)
      (let ((position (Item-position item)) (scale (Item-scale item)) (from (Item-from item)))
        (instance (mesh-index (Item-mesh item)) (Vec3-x position) (Vec3-y position) (Vec3-z position)
                  (Vec3-x scale) (Vec3-y scale) (Vec3-z scale) (Item-yaw item) (Item-color item) (Item-glow item)
                  (Vec3-x from) (Vec3-y from) (Vec3-z from))))

    ;; The order matches the meshes in src/app/renderer.mjs.
    (: mesh-index (-> Mesh I32))
    (define (mesh-index mesh)
      (match mesh
        ((Box) 0)
        ((Pyramid) 1)
        ((Prism) 2)
        ((Sphere) 3)
        ((Tile) 4)
        ((Tetrahedron) 5)
        ((Octahedron) 6)))

    (: render-panel (-> Panel Unit ! screen))
    (define (render-panel panel)
      (panel-begin (match (Panel-anchor panel) ((TopLeft) 0) ((TopRight) 1) ((BottomLeft) 2) ((BottomRight) 3)))
      (for-each render-widget (Panel-widgets panel)))

    (: render-widget (-> Widget Unit ! screen))
    (define (render-widget widget)
      (match widget
        ((Label text) (widget-begin 0 0 0.0) (render-text text))
        ((Button text action selected) (widget-begin (if selected 2 1) action 0.0) (render-text text))
        ((Meter text fraction) (widget-begin 3 0 fraction) (render-text text))))

    (: render-text (-> String Unit ! screen))
    (define (render-text text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (text-character (string-ref text index))
          (loop (+ index 1)))))

    ;; ---- Picking ----

    ;; A ray from `origin` along the unit vector `direction`.
    (struct Ray
      ((origin Vec3)
       (direction Vec3)))

    ;; The ray through the center of pixel (x, y), using the same projection
    ;; as the host. A perspective ray leaves the eye; an orthographic one
    ;; leaves the pixel's point on the plane through the eye.
    (: pointer-ray (-> Camera I32 I32 I32 I32 Ray))
    (define (pointer-ray view x y width height)
      (let* ((eye (Camera-eye view)) (forward (normalize (subtract (Camera-target view) eye)))
             (right (normalize (cross forward (Vec3 0.0 1.0 0.0)))) (up (cross right forward))
             (aspect (/ (i32->f32 width) (i32->f32 (max height 1))))
             (px (- (* 2.0 (/ (+ (i32->f32 x) 0.5) (i32->f32 (max width 1)))) 1.0))
             (py (- 1.0 (* 2.0 (/ (+ (i32->f32 y) 0.5) (i32->f32 (max height 1)))))))
        (match (Camera-projection view)
          ((Perspective fov)
           (let ((half (f64->f32 (tan (/ (f32->f64 fov) 2.0)))))
             (Ray eye (normalize (add forward (add (scale right (* px (* half aspect))) (scale up (* py half))))))))
          ((Orthographic height)
           (let ((half (/ height 2.0)))
             (Ray (add eye (add (scale right (* px (* half aspect))) (scale up (* py half)))) forward))))))

    ;; Where the ray through pixel (x, y) meets the ground plane y = 0.
    (: ground-point (-> Camera I32 I32 I32 I32 (Option Vec3)))
    (define (ground-point view x y width height)
      (let* ((ray (pointer-ray view x y width height)) (origin (Ray-origin ray)) (direction (Ray-direction ray)))
        (if (>= (Vec3-y direction) 0.0)
            (None)
            (Some (add origin (scale direction (/ (negate (Vec3-y origin)) (Vec3-y direction))))))))

    (: add (-> Vec3 Vec3 Vec3))
    (define (add a b)
      (Vec3 (+ (Vec3-x a) (Vec3-x b)) (+ (Vec3-y a) (Vec3-y b)) (+ (Vec3-z a) (Vec3-z b))))

    (: subtract (-> Vec3 Vec3 Vec3))
    (define (subtract a b)
      (Vec3 (- (Vec3-x a) (Vec3-x b)) (- (Vec3-y a) (Vec3-y b)) (- (Vec3-z a) (Vec3-z b))))

    (: scale (-> Vec3 F32 Vec3))
    (define (scale v k)
      (Vec3 (* (Vec3-x v) k) (* (Vec3-y v) k) (* (Vec3-z v) k)))

    (: cross (-> Vec3 Vec3 Vec3))
    (define (cross a b)
      (Vec3 (- (* (Vec3-y a) (Vec3-z b)) (* (Vec3-z a) (Vec3-y b)))
            (- (* (Vec3-z a) (Vec3-x b)) (* (Vec3-x a) (Vec3-z b)))
            (- (* (Vec3-x a) (Vec3-y b)) (* (Vec3-y a) (Vec3-x b)))))

    (: normalize (-> Vec3 Vec3))
    (define (normalize v)
      (scale v (/ 1.0 (sqrt (+ (* (Vec3-x v) (Vec3-x v)) (+ (* (Vec3-y v) (Vec3-y v)) (* (Vec3-z v) (Vec3-z v))))))))

    ;; ---- Applications ----

    ;; Generates the host entry points for an application. Its Save type
    ;; must derive Serialize and Deserialize.
    (define-syntax define-application
      (syntax-rules ()
        ((_ State init update view save restore)
         (begin
           (define current (ref (ann (None) (Option State))))
           (define saved (ref (vector-generate 0 (lambda (index) (ann 0 U8)))))
           (define loading (ref (make-array 0 (ann 0 U8))))

           (: app-init (-> I32 I32 I32 Unit ! mut))
           (define (app-init seed width height)
             (ref-set! current (Some (init seed width height))))

           (: app-input (-> I32 I32 I32 I32 Unit ! mut))
           (define (app-input kind a b c)
             (match (ref-get current)
               ((Some state) (ref-set! current (Some (update state (decode-input kind a b c)))))
               ((None) (unit))))

           (: app-frame (-> F32 Unit ! mut screen))
           (define (app-frame alpha)
             (match (ref-get current)
               ((Some state) (render (view state alpha)))
               ((None) (unit))))

           (: app-save (-> I32 ! mut))
           (define (app-save)
             (match (ref-get current)
               ((Some state) (ref-set! saved (serialize (save state))) (i64->i32 (vector-length (ref-get saved))))
               ((None) 0)))

           (: app-save-byte (-> I32 I32 ! mut))
           (define (app-save-byte index)
             (u8->i32 (vector-ref (ref-get saved) (i32->i64 index))))

           (: app-load-begin (-> I32 Unit ! mut))
           (define (app-load-begin count)
             (ref-set! loading (make-array (i32->i64 count) (ann 0 U8))))

           (: app-load-byte (-> I32 I32 Unit ! mut))
           (define (app-load-byte index byte)
             (array-set! (ref-get loading) (i32->i64 index) (i32->u8 byte)))

           ;; Panics if the save was written for another schema; the host
           ;; then starts a new state instead.
           (: app-load-end (-> Unit ! mut))
           (define (app-load-end)
             (ref-set! current (Some (ann (restore (deserialize (array->vector (ref-get loading)))) State))))

           (expose app-init "app_init")
           (expose app-input "app_input")
           (expose app-frame "app_frame")
           (expose app-save "app_save")
           (expose app-save-byte "app_save_byte")
           (expose app-load-begin "app_load_begin")
           (expose app-load-byte "app_load_byte")
           (expose app-load-end "app_load_end")))))

    ))
