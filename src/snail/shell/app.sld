;; Interactive applications. An application is pure functions over its
;; state, two that convert the state to and from what it saves, and two
;; that draw it, with a drawing state of their own:
;;
;;   init    : seed width height -> State
;;   update  : State Input -> State
;;   start   : -> Drawing
;;   draw    : State Drawing -> Drawing, through `gpu`
;;   hud     : State -> (List Panel)
;;   image-url : Drawing Key -> String, the address of an image the HUD shows
;;   save    : State -> Bytes
;;   restore : Bytes -> State
;;
;; A script runs one with `run-scene`, given a SceneHandler of the eight.
;; Its loop draws each event's state; (snail shell page) owns boot,
;; restore and durable saves for both browser engines. The drawing state
;; holds what drawing keeps between frames, such as an atlas and the
;; images it has read back for the HUD's `Image` widgets; it is never
;; saved, and starts again with each page or module, as the GPU's objects
;; do.
;; Time is input, so the state decides how its simulation advances. A
;; scene draws with its `Gpu`, itself or as a 3D `Frame` that
;; `draw-frame` draws; the HUD is a tree in the page's
;; document, changed through `dom` where it differs after each input
;; (after time, at most ten times a second). A durable save may be
;; much smaller than the state: a record of how to rebuild it.
;;
;; A Frame's items are mesh instances in batches, rasterized into a
;; G-buffer and lit by the sun in the metallic-roughness model
;; (`(snail shell graphics raster)`). A 2D scene with pictures draws them
;; as quads from an atlas (`(snail shell graphics quad)`), as Hearsay does.
(define-library (snail shell app)
  (export
   Input
   KeyDown
   KeyUp
   PointerDown
   PointerMove
   PointerDelta
   PointerLock
   PointerUp
   PointerCancel
   Wheel
   Resize
   Press
   Hover
   Elapsed
   key-left
   key-right
   key-up
   key-down
   key-escape
   key-enter
   key-space
   Vec3
   Projection
   Perspective
   Orthographic
   Camera
   Light
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
   Style
   Solid
   Translucent
   Revealed
   Batch
   Gesture
   Point
   Tap
   Drag
   Pinch
   Gestures
   no-gestures
   recognize
   Tone
   Plain
   Good
   Warning
   Danger
   Muted
   Suggested
   Control
   Enabled
   Disabled
   Selected
   Look
   Look-help-set
   Look-tone-set
   look
   Widget
   Label
   Button
   Dial
   Link
   Text
   Span
   Normal
   Strong
   Image
   label
   button
   Corner
   TopLeft
   TopRight
   BottomLeft
   BottomRight
   Place
   At
   Dialog
   Banner
   Panel
   Frame
   rgb
   Frames
   start-frames
   draw-frame
   Ray
   pointer-ray
   screen-axes
   ground-point
   Event
   FrameEvent
   InputEvent
   HudEvent
   FilesEvent
   Hidden
   SaveRequested
   Events
   next-event
   FramePacer
   frame-pacer
   pace-frame!
   PageStorage
   load-save
   SceneHandler
   run-scene)
  (import
   (except (snail core base) instance)
   (snail shell task)
   (snail shell math)
   (snail shell page)
   (snail core table)
   (only (snail shell dom) Dom no-event Allow)
   (only (snail core io) Clock)
   (rename (snail shell gpu) (Image GpuImage))
   (snail shell graphics pod)
   (snail shell graphics mesh)
   (rename (snail shell graphics raster) (Style Raster-style) (solid solid-style))
   (snail shell graphics passes)
   (prefix (snail shell ui) ui:))
  (begin

    ;; ---- Input ----

    ;; Keys are lower-case code points, or the named codes below, and a key
    ;; pressed with Shift says so; keys pressed with Ctrl, Alt or Meta stay
    ;; with the browser and never arrive. Pointer
    ;; events name the pointer, so several fingers can be told apart; the
    ;; wheel reports pixels. A press or hover reports the action and
    ;; argument of a HUD button; hovering off a button reports action 0.
    ;; Elapsed reports the milliseconds since the last display frame.
    (enum Input
      (KeyDown ((key I32) (shift Bool)))
      (KeyUp ((key I32)))
      (PointerDown ((pointer I32) (x I32) (y I32) (button I32)))
      (PointerMove ((pointer I32) (x I32) (y I32)))
      (PointerDelta ((dx I32) (dy I32)))
      (PointerLock ((locked Bool)))
      (PointerUp ((pointer I32) (x I32) (y I32)))
      (PointerCancel ((pointer I32)))
      (Wheel ((pixels I32)))
      (Resize ((width I32) (height I32)))
      (Press ((action I32) (argument I32)))
      (Hover ((action I32) (argument I32)))
      (Elapsed ((milliseconds I32))))

    (define key-left (→ I32) 1)

    (define key-right (→ I32) 2)

    (define key-up (→ I32) 3)

    (define key-down (→ I32) 4)

    (define key-escape (→ I32) 27)

    (define key-enter (→ I32) 13)

    (define key-space (→ I32) 32)

    ;; The kinds match the input encoding in host/browser/host.mjs. A press
    ;; or hover is no kind: a HUD listener's function makes it.

    (define (decode-input (kind I32) (a I32) (b I32) (c I32) (d I32)) (→ Input)
      (case kind
        ((1) (KeyDown a (= b 1)))
        ((2) (KeyUp a))
        ((3) (PointerDown a b c d))
        ((4) (PointerMove a b c))
        ((5) (PointerUp a b c))
        ((6) (PointerCancel a))
        ((7) (Wheel a))
        ((8) (Resize a b))
        ((18) (PointerDelta a b))
        ((19) (PointerLock (= a 1)))
        (else (Elapsed a))))

    ;; ---- Gestures ----

    ;; What pointers mean, the same for a mouse, a pen and fingers: a press
    ;; released within eight pixels is a tap, one that moves farther drags,
    ;; two fingers pinch, and a pointer moving with nothing pressed points.
    ;; A pinch reports how much the fingers' distance shrank, as a ratio.
    (enum Gesture
      (Point ((x I32) (y I32)))
      (Tap ((x I32) (y I32) (button I32)))
      (Drag ((dx I32) (dy I32)))
      (Pinch ((ratio F32))))

    ;; A pressed pointer is held until it moves eight pixels from where it
    ;; went down, and then drags. One that shared the screen with another is
    ;; part of a pinch for good: it never taps or drags, so lifting one
    ;; finger of a pinch does not pan.
    (enum Mode
      (Holding)
      (Dragging)
      (Pinched))

    ;; A pressed pointer: where it went down, and where it was last.
    (record Contact
      ((pointer I32)
       (button I32)
       (start-x I32)
       (start-y I32)
       (x I32)
       (y I32)
       (mode Mode)))

    ;; The pressed pointers, in the order they went down.
    (record Gestures
      ((contacts (List Contact))))

    (define no-gestures (→ Gestures) (new Gestures (contacts (Nil))))

    ;; Reads one input, returning the pointers still pressed and what the
    ;; input meant. Inputs other than pointers mean nothing here.

    (define (recognize (gestures Gestures) (input Input)) (→ (Pair Gestures (List Gesture)))
      (let ((contacts (● gestures contacts)))
        (match input
          ((PointerDown pointer x y button)
           (new Pair
             (first (new Gestures
                      (contacts (press-contact contacts
                                               (new Contact
                                                 (pointer pointer)
                                                 (button button)
                                                 (start-x x)
                                                 (start-y y)
                                                 (x x)
                                                 (y y)
                                                 (mode (Holding)))))))
             (second (Nil))))
          ((PointerMove pointer x y) (move-contact contacts pointer x y))
          ((PointerUp pointer x y) (release-contact contacts pointer x y))
          ((PointerCancel pointer)
           (new Pair
             (first (new Gestures (contacts (without-contact contacts pointer))))
             (second (Nil))))
          (_ (new Pair (first gestures) (second (Nil)))))))

    ;; A pointer that goes down again replaces its old press, which also
    ;; recovers from a release that never arrived.

    (define (press-contact (contacts (List Contact)) (contact Contact)) (→ (List Contact))
      (let ((pressed (append (without-contact contacts (● contact pointer)) (list contact))))
        (match pressed
          ((Cons _ (Nil)) pressed)
          (_ (map (lambda (c) (Contact-mode-set c (Pinched))) pressed)))))

    (define (without-contact (contacts (List Contact)) (pointer I32)) (→ (List Contact))
      (filter (lambda (c) (not (= (● c pointer) pointer))) contacts))

    ;; A pointer pressed alone may drag; among others, moves pinch. A moving
    ;; pointer that is not pressed points.

    (define (move-contact (contacts (List Contact)) (pointer I32) (x I32) (y I32))
      (→ (Pair Gestures (List Gesture)))
      (match (find (lambda (c) (= (● c pointer) pointer)) contacts)
        ((Some contact) (if (match contacts ((Cons _ (Nil)) #t) (_ #f))
                            (lone-move contact x y)
                            (let ((moved (map (lambda (c)
                                                (if (= (● c pointer) pointer)
                                                    (Contact-y-set (Contact-x-set c x) y)
                                                    c))
                                              contacts)))
                              (new Pair
                                (first (new Gestures (contacts moved)))
                                (second (pinch contacts moved))))))
        ((None) (new Pair (first (new Gestures (contacts contacts))) (second (list (Point x y)))))))

    ;; A held pointer drags once it is eight pixels from where it went down,
    ;; and its first drag covers the whole way from there.

    (define (lone-move (contact Contact) (x I32) (y I32)) (→ (Pair Gestures (List Gesture)))
      (let ((moved (Contact-y-set (Contact-x-set contact x) y)))
        (match (● contact mode)
          ((Dragging)
           (new Pair (first (new Gestures (contacts (list moved))))
                (second (list (Drag (- x (● contact x)) (- y (● contact y)))))))
          ((Holding) (if (far? contact x y)
                         (new Pair
                           (first
                            (new Gestures (contacts (list (Contact-mode-set moved (Dragging))))))
                           (second (list (Drag (- x (● contact start-x))
                                               (- y (● contact start-y))))))
                         (new Pair (first (new Gestures (contacts (list moved)))) (second (Nil)))))
          ((Pinched) (new Pair (first (new Gestures (contacts (list moved)))) (second (Nil)))))))

    (define (far? (contact Contact) (x I32) (y I32)) (→ Bool)
      (let ((dx (- x (● contact start-x))) (dy (- y (● contact start-y))))
        (> (+ (* dx dx) (* dy dy)) 64)))

    (define (pinch (before (List Contact)) (after (List Contact))) (→ (List Gesture))
      (let ((old (spread before)) (updated (spread after)))
        (if (and (> old 0.0) (> updated 0.0) (not (= old updated)))
            (list (Pinch (/ old updated)))
            (Nil))))

    ;; The distance between the first two pointers.

    (define (spread (contacts (List Contact))) (→ F32)
      (match contacts
        ((Cons a (Cons b _))
         (let ((dx (i32->f32 (- (● a x) (● b x))))
               (dy (i32->f32 (- (● a y) (● b y)))))
           (sqrt (+ (* dx dx) (* dy dy)))))
        (_ 0.0)))

    ;; Only a pointer still held, near where it went down, taps.

    (define (release-contact (contacts (List Contact)) (pointer I32) (x I32) (y I32))
      (→ (Pair Gestures (List Gesture)))
      (match (find (lambda (c) (= (● c pointer) pointer)) contacts)
        ((Some contact)
         (new Pair (first (new Gestures (contacts (without-contact contacts pointer))))
              (second (match (● contact mode)
                        ((Holding)
                         (if (far? contact x y)
                             (Nil)
                             (list (Tap x y (● contact button)))))
                        (_ (Nil))))))
        ((None) (new Pair (first (new Gestures (contacts contacts))) (second (Nil))))))

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
      (Orthographic ((height F32))))

    ;; Up is +y.
    (record Camera
      ((eye Vec3)
       (target Vec3)
       (projection Projection)))

    ;; Sunlight shining from `direction` with strength `sun`, and the light
    ;; every surface receives whichever way it faces.
    (record Light
      ((direction Vec3)
       (sun F32)
       (ambient F32)))

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
       (from Vec3)))

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
      (Revealed ((center Vec3) (radius F32))))

    ;; A batch's instances are kept until its version changes, so `items`
    ;; runs only when its version is new.
    (record Batch
      ((key I32)
       (version I32)
       (style Style)
       (items (Fn → (List Item)))))

    ;; ---- HUD ----

    ;; `Suggested` marks the control to use next.
    (enum Tone
      (Plain)
      (Good)
      (Warning)
      (Danger)
      (Muted)
      (Suggested))

    (enum Control
      (Enabled)
      (Disabled)
      (Selected))

    ;; How a widget appears: `key` identifies it from one update to the next
    ;; and names it for the page's style, `icon` names a symbol the style
    ;; draws, `help` is its tooltip and accessible description, and `badge`
    ;; marks a corner of it.
    (record Look
      ((key String)
       (icon String)
       (help String)
       (tone Tone)
       (badge String)))

    (define (look (key String)) (→ Look)
      (new Look (key key) (icon "") (help "") (tone (Plain)) (badge "")))

    ;; A button reports its action and argument through `Press`, with a
    ;; caption beneath its text and a ring around it filled to a fraction,
    ;; when the fraction is not negative. A dial is a round readout. A link
    ;; opens `url` in a new page and reports nothing. A text is a label
    ;; whose words may be strong in places. An image shows the
    ;; application's image `image`, `width` by `height` texels, each
    ;; `scale` pixels wide; the scene's `image-url` gives its address.
    (enum Widget
      (Label ((look Look) (text String)))
      (Button ((look Look)
               (text String)
               (caption String)
               (action I32)
               (argument I32)
               (control Control)
               (ring F32)))
      (Dial ((look Look) (text String) (fraction F32)))
      (Link ((look Look) (text String) (url String)))
      (Text ((look Look) (spans (List Span))))
      (Image ((look Look) (image I32) (width I32) (height I32) (scale I32))))

    (enum Span
      (Normal ((words String)))
      (Strong ((words String))))

    ;; The widgets most panels are made of: a plain label, and an enabled
    ;; button without caption or ring that presses `action` with argument
    ;; 0.

    (define (label (key String) (text String)) (→ Widget)
      (Label (look key) text))

    (define (button (key String) (text String) (action I32)) (→ Widget)
      (Button (look key) text "" action 0 (Enabled) -1.0))

    (enum Corner
      (TopLeft)
      (TopRight)
      (BottomLeft)
      (BottomRight))

    ;; Panels in a corner stack in columns: column 0 against the side of the
    ;; screen, later ones farther in, each running from the corner in the
    ;; order given. A dialog sits in the middle over a backdrop that presses
    ;; `dismiss` when touched. A banner sits across the top and lets input
    ;; through to the game beneath it, except on its links.
    (enum Place
      (At ((corner Corner) (column I32)))
      (Dialog ((dismiss I32)))
      (Banner))

    (record Panel
      ((key String)
       (place Place)
       (widgets (List Widget))))

    ;; ---- Drawing ----

    ;; What drawing keeps across frames, from the first, once the device
    ;; answers: the raster, the G-buffer for the canvas's size with the
    ;; sunlight over it and the post passes from its light to the canvas,
    ;; and a surface for each of the last frame's batches, in its order.
    (record Drawn
      ((raster Raster)
       (gbuffer GBuffer)
       (width I32)
       (height I32)
       (light Sunlight)
       (post Post)
       (surfaces (List Kept))))

    ;; A batch's surface, and the version it shows.
    (record Kept
      ((key I32)
       (version I32)
       (surface Surface)))

    (record Frames
      ((drawn (Option Drawn))))

    (define (start-frames) (→ Frames) (new Frames (drawn (None))))

    ;; The frame drawn to the canvas: solid and revealed batches into the
    ;; G-buffer, lit by the sun over the background, then translucent ones
    ;; over them, into the light, which is tone-mapped and smoothed into the
    ;; canvas. A batch's surface is made only when its version is new.
    (define (draw-frame (gpu Gpu) (frame Frame) (frames Frames)) (→ Frames)
      (match (● frames drawn)
        ((Some drawn) (drawn-frame gpu frame drawn ((● gpu current-texture))))
        ((None)
         (let* ((format (● ((● gpu request-device)) format)) (canvas ((● gpu current-texture))))
           (drawn-frame gpu frame (started gpu format canvas) canvas)))))

    (define (started (gpu Gpu) (format TextureFormat) (canvas GpuImage)) (→ Drawn)
      (let* ((width (● canvas width))
             (height (● canvas height))
             (r (make-raster gpu color-planes light-format))
             (g (make-gbuffer gpu color-planes width height)))
        (new Drawn
          (raster r)
          (gbuffer g)
          (width width)
          (height height)
          (light (make-sunlight gpu light-format g r))
          (post (make-post gpu format width height (Neutral)))
          (surfaces (Nil)))))

    (define (drawn-frame (gpu Gpu) (frame Frame) (drawn Drawn) (canvas GpuImage)) (→ Frames)
      (let* ((drawn (surfaced gpu (resized gpu drawn canvas) frame))
             (drawn (Drawn-raster-set drawn
                                      (write-raster gpu (● drawn raster)
                                                    (frame-camera frame
                                                                  (● canvas width)
                                                                  (● canvas height))
                                                    (frame-sun (● frame light)))))
             (target (view-of gpu (● canvas texture) 1))
             (encoder ((● gpu create-command-encoder))))
        (let ((pass (begin-gbuffer gpu encoder (● drawn gbuffer))))
          (draw-surfaces gpu pass drawn #f)
          ((● gpu end-pass) pass))
        (let ((pass (begin-lit gpu encoder
                               (● drawn post targets light-view)
                               (backdrop (● frame background))
                               (● drawn gbuffer))))
          (draw-sun gpu pass (● drawn light))
          (draw-surfaces gpu pass drawn #t)
          ((● gpu end-pass) pass))
        (draw-post gpu encoder target (● drawn post))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (new Frames (drawn (Some drawn)))))

    ;; The G-buffer and the post targets remade, and the sunlight over
    ;; them, when the canvas's size changes.
    (define (resized (gpu Gpu) (drawn Drawn) (canvas GpuImage)) (→ Drawn)
      (if (and (= (● drawn width) (● canvas width)) (= (● drawn height) (● canvas height)))
          drawn
          (let ((g (make-gbuffer gpu color-planes (● canvas width) (● canvas height))))
            (release-gbuffer gpu (● drawn gbuffer))
            (new Drawn
              (raster (● drawn raster))
              (gbuffer g)
              (width (● canvas width))
              (height (● canvas height))
              (light (relight gpu (● drawn light) g (● drawn raster)))
              (post (resize-post gpu (● drawn post) (● canvas width) (● canvas height)))
              (surfaces (● drawn surfaces))))))

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
                    (material (new Vec2f (x 0.0) (y 1.0)))
                    (id 0))))))

    (define (vec4 (v Vec3) (w F32)) (→ Vec4f)
      (new Vec4f (x (● v x)) (y (● v y)) (z (● v z)) (w w)))

    (define (channel (color I32) (shift I32)) (→ F32)
      (/ (i32->f32 (i32-and (i32-shift-right/logical color shift) 255)) 255.0))

    (define (backdrop (color I32)) (→ Color)
      (new Color
        (red (f32->f64 (channel color 16)))
        (green (f32->f64 (channel color 8)))
        (blue (f32->f64 (channel color 0)))
        (alpha 1.0)))

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

    ;; ---- The HUD's document ----

    ;; The HUD as the trees the page's overlay holds: each corner with its
    ;; panels in columns, the banner with its, and the dialogs with theirs
    ;; over a backdrop that presses the last dialog's `dismiss`. The page's
    ;; style lays them out (host/browser/style.css), and an application's
    ;; own colors widgets by their data-key, data-icon, data-tone and
    ;; data-badge. A panel or widget keeps its node while its key and tag
    ;; stay, so hover and focus survive the updates; siblings' keys differ,
    ;; as (snail shell ui) requires. A listener's function makes the input
    ;; its event is. `url` gives the address of the application's image
    ;; by its key.

    (define (hud-html (panels (List Panel)) (url (Fn I32 → String))) (→ (List (ui:Html Input)))
      (append (map (lambda (corner) (corner-html corner panels url))
                   (list "top-left" "top-right" "bottom-left" "bottom-right"))
              (list (ui:Element "div"
                                (list (ui:Attr "class" "banner"))
                                (map (lambda (panel) (panel-html panel url))
                                     (placed "banner" panels)))
                    (dialogs-html (placed "dialog" panels) url))))

    ;; Where a panel goes: a corner by its class in the page's style, the
    ;; banner or the dialogs.

    (define (place-name (place Place)) (→ String)
      (match place
        ((At (TopLeft) _) "top-left")
        ((At (TopRight) _) "top-right")
        ((At (BottomLeft) _) "bottom-left")
        ((At (BottomRight) _) "bottom-right")
        ((Dialog _) "dialog")
        ((Banner) "banner")))

    (define (placed (name String) (panels (List Panel))) (→ (List Panel))
      (filter (lambda (panel) (string=? (place-name (● panel place)) name)) panels))

    (define (panel-column (panel Panel)) (→ I32)
      (match (● panel place)
        ((At _ column) column)
        (_ 0)))

    ;; A corner's columns, column 0 first, each holding its panels in the
    ;; order given.

    (define (corner-html (corner String) (panels (List Panel)) (url (Fn I32 → String)))
      (→ (ui:Html Input))
      (let ((here (placed corner panels)))
        (ui:Element "div"
                    (list (ui:Attr "class" (string-append "corner " corner)))
                    (map (lambda (column)
                           (ui:Element "div"
                                       (list (ui:Keyed (show column)) (ui:Attr "class" "column"))
                                       (map (lambda (panel) (panel-html panel url))
                                            (filter (lambda (panel) (= (panel-column panel) column))
                                                    here))))
                         (list-sort < (delete-duplicates = (map panel-column here)))))))

    (define (dialogs-html (dialogs (List Panel)) (url (Fn I32 → String))) (→ (ui:Html Input))
      (let ((dismiss (fold-left (lambda (dismiss panel)
                                  (match (● panel place)
                                    ((Dialog action) action)
                                    (_ dismiss)))
                                0
                                dialogs)))
        (ui:Element "div"
                    (list (ui:Attr "class" (if (null? dialogs) "dialogs" "dialogs open")))
                    (Cons (ui:Element "div"
                                      (list (ui:Attr "class" "backdrop")
                                            (ui:On "click"
                                                   (Nil)
                                                   (Allow)
                                                   (lambda (_) (Press dismiss 0))))
                                      (Nil))
                          (map (lambda (panel) (panel-html panel url)) dialogs)))))

    (define (panel-html (panel Panel) (url (Fn I32 → String))) (→ (ui:Html Input))
      (ui:Element "div"
                  (list (ui:Keyed (● panel key))
                        (ui:Attr "class" "panel")
                        (ui:Attr "data-key" (● panel key)))
                  (map (lambda (widget) (widget-html widget url)) (● panel widgets))))

    ;; ---- Widgets ----

    ;; A widget is an icon the style draws and its text, a button also its
    ;; caption; a text's words are spans, strong in places.

    (define (widget-html (widget Widget) (url (Fn I32 → String))) (→ (ui:Html Input))
      (match widget
        ((Label face text)
         (ui:Element "div" (faced "label" face text) (list (part "icon" "") (part "text" text))))
        ((Button face text caption action argument control ring)
         (ui:Element "button"
                     (append (faced "button" face text) (pressing action argument control ring))
                     (list (part "icon" "") (part "text" text) (part "caption" caption))))
        ((Dial face text fraction)
         (ui:Element "div"
                     (Cons (filled fraction) (faced "dial" face text))
                     (list (part "icon" "") (part "text" text))))
        ((Link face text url)
         (ui:Element "a"
                     (append (faced "link" face text)
                             (list (ui:Attr "target" "_blank")
                                   (ui:Attr "rel" "noopener")
                                   (ui:Attr "href" url)))
                     (list (part "icon" "") (part "text" text))))
        ((Text face spans)
         (ui:Element "div"
                     (faced "label" face "")
                     (list (part "icon" "")
                           (ui:Element "span"
                                       (list (ui:Attr "class" "text"))
                                       (map span-html spans)))))
        ((Image face image width height scale) (image-html face (url image) width height scale))))

    ;; What every widget but an image says of itself: its class, the key
    ;; that keeps its node, its look for the page's style, and for
    ;; assistive technology its help after its text. An attribute given ""
    ;; is absent.

    (define (faced (class String) (face Look) (text String)) (→ (List (ui:Attribute Input)))
      (let ((help (● face help)))
        (list (ui:Keyed (● face key))
              (ui:Attr "class" class)
              (ui:Attr "data-key" (● face key))
              (ui:Attr "data-icon" (● face icon))
              (ui:Attr "data-badge" (● face badge))
              (ui:Attr "data-tone" (tone-name (● face tone)))
              (ui:Attr "title" help)
              (ui:Attr "aria-label"
                       (cond ((string=? help "") "")
                             ((string=? text "") help)
                             (else (string-append text " " help)))))))

    (define (tone-name (tone Tone)) (→ String)
      (match tone
        ((Plain) "plain")
        ((Good) "good")
        ((Warning) "warning")
        ((Danger) "danger")
        ((Muted) "muted")
        ((Suggested) "suggested")))

    ;; A part of a widget, empty when it has no text, so the style can hide
    ;; it.

    (define (part (class String) (text String)) (→ (ui:Html Input))
      (ui:Element "span"
                  (list (ui:Attr "class" class))
                  (if (string=? text "") (Nil) (list (ui:Text text)))))

    (define (span-html (span Span)) (→ (ui:Html Input))
      (match span
        ((Normal words) (ui:Element "span" (Nil) (list (ui:Text words))))
        ((Strong words) (ui:Element "strong" (Nil) (list (ui:Text words))))))

    ;; A button's state, its ring, and its listeners: a click presses it,
    ;; and the pointer entering and leaving it hover on and off it.

    (define (pressing (action I32) (argument I32) (control Control) (ring F32))
      (→ (List (ui:Attribute Input)))
      (list (ui:FlagProperty "disabled" (match control ((Disabled) #t) (_ #f)))
            (ui:Attr "aria-pressed" (match control ((Selected) "true") (_ "")))
            (ui:Attr "data-ring" (if (>= ring 0.0) "true" ""))
            (filled ring)
            (ui:On "click" (Nil) (Allow) (lambda (_) (Press action argument)))
            (ui:On "pointerenter" (Nil) (Allow) (lambda (_) (Hover action argument)))
            (ui:On "pointerleave" (Nil) (Allow) (lambda (_) (Hover 0 0)))))

    ;; How full a dial or ring is, for the style's gradients: a fraction
    ;; within 0 and 1 as a percentage to a tenth.

    (define (filled (fraction F32)) (→ (ui:Attribute Input))
      (let ((tenths (f32->i32 (round (* 1000.0 (max 0.0 (min 1.0 fraction)))))))
        (ui:Attr "style"
                 (string-append "--fraction: "
                                (show (quotient tenths 10))
                                "."
                                (show (remainder tenths 10))
                                "%"))))

    ;; An image's texels stay crisp at its scale. Until it has a URL, its
    ;; box is empty.

    (define (image-html (face Look) (url String) (width I32) (height I32) (scale I32))
      (→ (ui:Html Input))
      (ui:Element "div"
                  (list (ui:Keyed (● face key))
                        (ui:Attr "class" "image")
                        (ui:Attr "data-key" (● face key))
                        (ui:Attr "title" (● face help))
                        (ui:Attr "style" (box-style (* width scale) (* height scale))))
                  (if (string=? url "")
                      (Nil)
                      (list (ui:Element "img"
                                        (list (ui:Attr "src" url)
                                              (ui:Attr "style"
                                                       (string-append
                                                        (box-style (* width scale) (* height scale))
                                                        "; image-rendering: pixelated")))
                                        (Nil))))))

    (define (box-style (width I32) (height I32)) (→ String)
      (string-append "width: " (show width) "px; height: " (show height) "px"))

    ;; ---- Picking ----

    ;; A ray from `origin` along the unit array `direction`.
    (record Ray
      ((origin Vec3)
       (direction Vec3)))

    ;; The ray through the center of pixel (x, y), using the same projection
    ;; as the host. A perspective ray leaves the eye; an orthographic one
    ;; leaves the pixel's point on the plane through the eye.

    (define (pointer-ray (view Camera) (x I32) (y I32) (width I32) (height I32)) (→ Ray)
      (let* ((eye (● view eye)) (forward (normalize (subtract (● view target) eye)))
             (axes (screen-axes view)) (right (● axes first)) (up (● axes second))
             (aspect (/ (i32->f32 width) (i32->f32 (max height 1))))
             (px (- (* 2.0 (/ (+ (i32->f32 x) 0.5) (i32->f32 (max width 1)))) 1.0))
             (py (- 1.0 (* 2.0 (/ (+ (i32->f32 y) 0.5) (i32->f32 (max height 1)))))))
        (match (● view projection)
          ((Perspective fov)
           (let ((half (f64->f32 (tan (/ (f32->f64 fov) 2.0)))))
             (new Ray (origin eye)
                  (direction (normalize (add forward
                                             (add (scale right (* px (* half aspect)))
                                                  (scale up (* py half)))))))))
          ((Orthographic height)
           (let ((half (/ height 2.0)))
             (new Ray
               (origin (add eye (add (scale right (* px (* half aspect))) (scale up (* py half)))))
               (direction forward)))))))

    ;; The directions of the screen's right and up in the world. A camera
    ;; looking straight down has up toward -z, so it shows the ground as a
    ;; map with the far side at the top, as a camera tilted down from +z
    ;; would; the renderer uses the same rule.

    (define (screen-axes (view Camera)) (→ (Pair Vec3 Vec3))
      (let* ((forward (normalize (subtract (● view target) (● view eye))))
             (sky (if (> (abs (● forward y)) 0.999)
                      (new Vec3 (x 0.0) (y 0.0) (z -1.0))
                      (new Vec3 (x 0.0) (y 1.0) (z 0.0))))
             (right (normalize (cross forward sky))))
        (new Pair (first right) (second (cross right forward)))))

    ;; Where the ray through pixel (x, y) meets the ground plane y = 0.

    (define (ground-point (view Camera) (x I32) (y I32) (width I32) (height I32)) (→ (Option Vec3))
      (let* ((ray (pointer-ray view x y width height))
             (origin (● ray origin))
             (direction (● ray direction)))
        (if (>= (● direction y) 0.0)
            (None)
            (Some (add origin (scale direction (/ (negate (● origin y)) (● direction y))))))))

    (define (add (a Vec3) (b Vec3)) (→ Vec3)
      (new Vec3 (x (+ (● a x) (● b x))) (y (+ (● a y) (● b y))) (z (+ (● a z) (● b z)))))

    (define (subtract (a Vec3) (b Vec3)) (→ Vec3)
      (new Vec3 (x (- (● a x) (● b x))) (y (- (● a y) (● b y))) (z (- (● a z) (● b z)))))

    (define (scale (v Vec3) (k F32)) (→ Vec3)
      (new Vec3 (x (* (● v x) k)) (y (* (● v y) k)) (z (* (● v z) k))))

    (define (cross (a Vec3) (b Vec3)) (→ Vec3)
      (new Vec3 (x (- (* (● a y) (● b z)) (* (● a z) (● b y))))
           (y (- (* (● a z) (● b x)) (* (● a x) (● b z))))
           (z (- (* (● a x) (● b y)) (* (● a y) (● b x))))))

    (define (normalize (v Vec3)) (→ Vec3)
      (scale v
             (/ 1.0
                (sqrt (+ (* (● v x) (● v x))
                         (+ (* (● v y) (● v y)) (* (● v z) (● v z))))))))

    ;; ---- Application events ----

    ;; Frame already names the drawing data above; FrameEvent names a tick.
    ;; FilesEvent says the user dropped or picked files, which `chosen-files` lists
    ;; ((snail shell files)).
    (enum Event
      (FrameEvent ((elapsed I32)))
      (InputEvent ((input Input)))
      (HudEvent ((listener I32)))
      (FilesEvent ((count I32)))
      (Hidden)
      (SaveRequested))

    (define (next-event (events Events)) (→ Event)
      (match ((● events poll-event))
        (0 ((● events wait-event)) (next-event events))
        (11 (FrameEvent ((● events event-field) 0)))
        (12 (Hidden))
        (14 (HudEvent ((● events event-field) 0)))
        (16 (SaveRequested))
        (17 (FilesEvent ((● events event-field) 0)))
        (kind (InputEvent (decode-input kind
                                        ((● events event-field) 0)
                                        ((● events event-field) 1)
                                        ((● events event-field) 2)
                                        ((● events event-field) 3))))))

    ;; Frame events carry display time. Count thousandths of a presentation
    ;; slot so rates such as 30 Hz do not accumulate integer-millisecond drift.
    (record FramePacer
      ((rate I64)
       (phase I64)
       (elapsed I64)))
    (define (frame-pacer (fps I64)) (→ FramePacer)
      (unless (and (> fps 0) (<= fps 1000)) (panic "frame rate must be 1 to 1000"))
      (new FramePacer (rate fps) (phase (min fps 500)) (elapsed -1)))
    (define (pace-frame! (p FramePacer) (ms I32)) (→ (Option I32))
      (let* ((dt (max 0 (i32->i64 ms))) (rate (● p rate))
             (phase (+ (● p phase) (* dt rate))) (elapsed (+ (● p elapsed) dt)))
        (cond ((< (● p elapsed) 0) (set! (● p elapsed) 0) (Some 0))
              ((< phase 1000) (set! (● p phase) phase) (set! (● p elapsed) elapsed) (None))
              (else
               ;; One millisecond covers the host's timestamp rounding. After a
               ;; missed refresh longer than a slot, start a new period here.
               (set! (● p phase)
                     (if (> (* dt rate) (+ 1000 rate)) (min rate 500) (modulo phase 1000)))
               (set! (● p elapsed) 0)
               (Some (i64->i32 (min elapsed 2147483647)))))))

    ;; ---- Running a scene ----

    ;; A scene is a handler, in the style of winit's: a record of the
    ;; functions over its state and its drawing state, which a script hands
    ;; to `run-scene` as its last statement.

    (record (SceneHandler S D)
      ((initialize (Fn I32 I32 I32 → S))
       (update (Fn S Input → S))
       (start (Fn → D))
       (draw (Fn S D → D))
       (hud (Fn S → (List Panel)))
       (image-url (Fn D I32 → String))
       (save (Fn S → Bytes))
       (restore (Fn Bytes → S))))

    ;; The page's state, from its save or `initialize` with a seed and the
    ;; canvas's size, then the scene's loop, which never returns, over the
    ;; page's document.

    (define (run-scene
             (dom Dom)
             (events Events)
             (storage PageStorage)
             (scene (SceneHandler S D)))
      (→ Unit)
      (∀ (S D))
      (run-page events storage (lambda ()
                                 ((● scene initialize)
                                  ((● events random-seed))
                                  ((● events canvas-width))
                                  ((● events canvas-height))))
                (● scene save)
                (● scene restore)
                (lambda (state save)
                  (scene-loop dom events scene
                              save
                              state
                              ((● scene start))
                              (new Hud (shown (Nil)) (hovered (None)))))))

    ;; Each event's state is drawn: a frame draws the scene and, at most ten
    ;; times a second, the HUD; an input shows its HUD. Saves share the
    ;; same queue, independently of display frames. A HUD listener that
    ;; fired gives its input; one the HUD has since dropped gives none.

    (define (scene-loop (dom Dom)
                        (events Events)
                        (scene (SceneHandler S D))
                        (save (Fn S → Unit))
                        (state S)
                        (drawing D)
                        (hud Hud))
      (→ Unit)
      (∀ (S D))
      (let loop ((state state) (drawing drawing) (hud hud) (since-hud 0))
        (match (next-event events)
          ((FrameEvent elapsed)
           (let* ((next ((● scene update) state (Elapsed elapsed)))
                  (drawn ((● scene draw) next drawing))
                  (show-hud? (>= (+ since-hud elapsed) 100))
                  (shown (if show-hud?
                             (show-hud dom scene next drawn hud)
                             (new Pair (first next) (second hud)))))
             ((● events report-ready))
             (loop (● shown first)
                   drawn
                   (● shown second)
                   (if show-hud? 0 (+ since-hud elapsed)))))
          ((InputEvent input)
           (match (scene-input dom scene state drawing hud input)
             ((Pair state hud) (loop state drawing hud 0))))
          ((HudEvent listener)
           (match (table-ref (ui:listener-table (● hud shown)) (show listener))
             ((Some message)
              (let ((input (message no-event)))
                (match (scene-input dom scene state drawing (hovering hud listener input) input)
                  ((Pair state hud) (loop state drawing hud 0)))))
             ((None) (loop state drawing hud since-hud))))
          ((Hidden)
           (save state)
           (loop state drawing hud since-hud))
          ((SaveRequested)
           (save state)
           (loop state drawing hud since-hud))
          ((FilesEvent _) (loop state drawing hud since-hud)))))

    (define (scene-input (dom Dom)
                         (scene (SceneHandler S D))
                         (state S)
                         (drawing D)
                         (hud Hud)
                         (input Input))
      (→ (Pair S Hud))
      (∀ (S D))
      (show-hud dom scene ((● scene update) state input) drawing hud))

    ;; ---- Showing the HUD ----

    ;; The HUD as the document holds it, and the listener of the button
    ;; under the pointer, the one that heard the pointer enter.
    (record Hud
      ((shown (List (ui:Shown Input)))
       (hovered (Option I32))))

    (define (hovering (hud Hud) (listener I32) (input Input)) (→ Hud)
      (match input
        ((Hover 0 _) (new Hud (shown (● hud shown)) (hovered (None))))
        ((Hover _ _) (new Hud (shown (● hud shown)) (hovered (Some listener))))
        (_ hud)))

    ;; The state's HUD shown, in place where it differs. A button removed
    ;; while the pointer is over it never hears the pointer leave, so the
    ;; state is told, and its HUD shown.

    (define (show-hud (dom Dom) (scene (SceneHandler S D)) (state S) (drawing D) (hud Hud))
      (→ (Pair S Hud))
      (∀ (S D))
      (let ((shown (ui:patch-children dom ((● dom document-root))
                                      (● hud shown)
                                      (hud-html ((● scene hud) state)
                                                (lambda (image)
                                                  ((● scene image-url) drawing image))))))
        (if (match (● hud hovered)
              ((Some listener) (not (table-contains? (ui:listener-table shown) (show listener))))
              ((None) #f))
            (show-hud dom scene
                      ((● scene update) state (Hover 0 0))
                      drawing
                      (new Hud (shown shown) (hovered (None))))
            (new Pair (first state) (second (new Hud (shown shown) (hovered (● hud hovered))))))))

    ))
