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
   Camera
   Camera-eye
   Camera-target
   camera-fov
   Mesh
   Box
   Pyramid
   Prism
   Sphere
   Tile
   Item
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

    ;; The host uses a perspective projection with this vertical field of view.
    (struct Camera
      ((eye Vec3)
       (target Vec3)))

    (define camera-fov 0.8)

    (enum Mesh
      (Box)
      (Pyramid)
      (Prism)
      (Sphere)
      (Tile))

    ;; A mesh instance: position, scale, rotation about the vertical axis, and
    ;; a 0xRRGGBB color.
    (struct Item
      ((mesh Mesh)
       (position Vec3)
       (scale Vec3)
       (yaw F32)
       (color I32)))

    ;; The host keeps each batch's instances until its version changes, so
    ;; `items` runs only when the host does not already have them.
    (struct Batch
      ((key I32)
       (version I32)
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

    (struct Frame
      ((camera Camera)
       (background I32)
       (batches (List Batch))
       (panels (List Panel))))

    (: rgb (-> I32 I32 I32 I32))
    (define (rgb red green blue)
      (+ (* red 65536) (+ (* green 256) blue)))

    ;; ---- Drawing ----

    (effect screen
      ((frame-begin (-> F32 F32 F32 F32 F32 F32 I32 Unit))
       (batch-begin (-> I32 I32 Bool))
       (instance (-> I32 F32 F32 F32 F32 F32 F32 F32 I32 Unit))
       (panel-begin (-> I32 Unit))
       (widget-begin (-> I32 I32 F32 Unit))
       (text-character (-> Char Unit))
       (frame-end (-> Unit)))
      (host "snail.screen"
            ((frame-begin "frame-begin")
             (batch-begin "batch-begin")
             (instance "instance")
             (panel-begin "panel-begin")
             (widget-begin "widget-begin")
             (text-character "text-character")
             (frame-end "frame-end"))))

    (: render (-> Frame Unit ! screen))
    (define (render frame)
      (let ((eye (Camera-eye (Frame-camera frame))) (target (Camera-target (Frame-camera frame))))
        (frame-begin (Vec3-x eye) (Vec3-y eye) (Vec3-z eye) (Vec3-x target) (Vec3-y target) (Vec3-z target)
                     (Frame-background frame)))
      (for-each render-batch (Frame-batches frame))
      (for-each render-panel (Frame-panels frame))
      (frame-end))

    (: render-batch (-> Batch Unit ! screen))
    (define (render-batch batch)
      (unless (batch-begin (Batch-key batch) (Batch-version batch))
        (for-each render-item ((Batch-items batch)))))

    (: render-item (-> Item Unit ! screen))
    (define (render-item item)
      (let ((position (Item-position item)) (scale (Item-scale item)))
        (instance (mesh-index (Item-mesh item)) (Vec3-x position) (Vec3-y position) (Vec3-z position)
                  (Vec3-x scale) (Vec3-y scale) (Vec3-z scale) (Item-yaw item) (Item-color item))))

    (: mesh-index (-> Mesh I32))
    (define (mesh-index mesh)
      (match mesh
        ((Box) 0)
        ((Pyramid) 1)
        ((Prism) 2)
        ((Sphere) 3)
        ((Tile) 4)))

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

    ;; The point where the ray through pixel (x, y) meets the plane y = 0,
    ;; using the same projection as the host.
    (: ground-point (-> Camera I32 I32 I32 I32 (Option Vec3)))
    (define (ground-point camera x y width height)
      (let* ((eye (Camera-eye camera)) (forward (normalize (subtract (Camera-target camera) eye)))
             (right (normalize (cross forward (Vec3 0.0 1.0 0.0)))) (up (cross right forward))
             (half (f64->f32 (tan (/ (f32->f64 camera-fov) 2.0))))
             (aspect (/ (i32->f32 width) (i32->f32 (max height 1))))
             (px (* (- (* 2.0 (/ (+ (i32->f32 x) 0.5) (i32->f32 (max width 1)))) 1.0) (* half aspect)))
             (py (* (- 1.0 (* 2.0 (/ (+ (i32->f32 y) 0.5) (i32->f32 (max height 1))))) half))
             (direction (normalize (add forward (add (scale right px) (scale up py))))))
        (if (>= (Vec3-y direction) 0.0)
            (None)
            (let ((distance (/ (negate (Vec3-y eye)) (Vec3-y direction))))
              (Some (add eye (scale direction distance)))))))

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
