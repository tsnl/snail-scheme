;; Interactive applications. An application is four total functions over
;; its state, and two that convert the state to and from what it saves:
;;
;;   init    : seed width height -> State
;;   update  : State Input -> State
;;   view    : State -> Frame
;;   hud     : State -> (List Panel)
;;   save    : State -> Save
;;   restore : Save -> State
;;
;; `define-application` keeps the current state in one cell and exposes the
;; host entry points. Time reaches the state as input: before drawing each
;; display frame, the host reports the milliseconds since the last, so the
;; state decides how time passes, and can stop it at any frame. The host
;; draws a Frame through the `screen` effect, shows the HUD again after
;; each input (after time, at most ten times a second), and stores the
;; serialized Save. The Save may be much smaller than the state: a record
;; of how to rebuild it.
;;
;; Scenes are 3D. Meshes and sprites are both items, drawn by one shader in
;; the metallic-roughness model; a sprite is a textured quad that stands
;; upright toward the camera, so 2D and 2.5D are scenes too. Textures are
;; pictures the host composes from regions of encoded image files that the
;; program carries, typically as byte literals.
(define-library (lofi app)
  (export
   Input
   KeyDown
   KeyUp
   PointerDown
   PointerMove
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
   Quad
   Rect
   Rect-x
   Rect-y
   Rect-width
   Rect-height
   Source
   Layer
   Picture
   Texture
   Texture-picture
   Texture-region
   Texture-region-set
   Texture-frames
   Texture-period
   still
   Material
   Material-texture
   Material-metalness
   Material-roughness
   plain
   Facing
   Fixed
   Upright
   Item
   Item-position
   Item-position-set
   Item-scale
   Item-scale-set
   Item-yaw
   Item-yaw-set
   Item-color
   Item-color-set
   Item-glow
   Item-glow-set
   Item-from
   Item-from-set
   Item-material
   Item-material-set
   Item-facing
   Item-facing-set
   item
   sprite
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
   Control
   Enabled
   Disabled
   Selected
   Look
   Look-key
   Look-help
   Look-help-set
   Look-tone-set
   look
   Widget
   Label
   Button
   Dial
   Image
   Corner
   TopLeft
   TopRight
   BottomLeft
   BottomRight
   Place
   At
   Dialog
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

    ;; Keys are lower-case code points, or the named codes below. Pointer
    ;; events name the pointer, so several fingers can be told apart; the
    ;; wheel reports pixels. A press or hover reports the action and
    ;; argument of a HUD button; hovering off a button reports action 0.
    ;; Elapsed reports the milliseconds since the last display frame.
    (enum Input
      (KeyDown ((key I32)))
      (KeyUp ((key I32)))
      (PointerDown ((pointer I32) (x I32) (y I32) (button I32)))
      (PointerMove ((pointer I32) (x I32) (y I32)))
      (PointerUp ((pointer I32) (x I32) (y I32)))
      (PointerCancel ((pointer I32)))
      (Wheel ((pixels I32)))
      (Resize ((width I32) (height I32)))
      (Press ((action I32) (argument I32)))
      (Hover ((action I32) (argument I32)))
      (Elapsed ((milliseconds I32))))

    (define key-left 1)
    (define key-right 2)
    (define key-up 3)
    (define key-down 4)
    (define key-escape 27)
    (define key-enter 13)
    (define key-space 32)

    (: decode-input (-> I32 I32 I32 I32 I32 Input))
    (define (decode-input kind a b c d)
      (case kind
        ((1) (KeyDown a))
        ((2) (KeyUp a))
        ((3) (PointerDown a b c d))
        ((4) (PointerMove a b c))
        ((5) (PointerUp a b c))
        ((6) (PointerCancel a))
        ((7) (Wheel a))
        ((8) (Resize a b))
        ((9) (Press a b))
        ((10) (Hover a b))
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
    (struct Contact
      ((pointer I32)
       (button I32)
       (start-x I32)
       (start-y I32)
       (x I32)
       (y I32)
       (mode Mode)))

    ;; The pressed pointers, in the order they went down.
    (struct Gestures
      ((contacts (List Contact))))

    (: no-gestures Gestures)
    (define no-gestures (Gestures (Nil)))

    ;; Reads one input, returning the pointers still pressed and what the
    ;; input meant. Inputs other than pointers mean nothing here.
    (: recognize (-> Gestures Input (Pair Gestures (List Gesture))))
    (define (recognize gestures input)
      (let ((contacts (Gestures-contacts gestures)))
        (match input
          ((PointerDown pointer x y button) (Pair (Gestures (press-contact contacts (Contact pointer button x y x y (Holding)))) (Nil)))
          ((PointerMove pointer x y) (move-contact contacts pointer x y))
          ((PointerUp pointer x y) (release-contact contacts pointer x y))
          ((PointerCancel pointer) (Pair (Gestures (without-contact contacts pointer)) (Nil)))
          (_ (Pair gestures (Nil))))))

    ;; A pointer that goes down again replaces its old press, which also
    ;; recovers from a release that never arrived.
    (: press-contact (-> (List Contact) Contact (List Contact)))
    (define (press-contact contacts contact)
      (let ((pressed (append (without-contact contacts (Contact-pointer contact)) (list contact))))
        (if (null? (cdr-list pressed)) pressed (map (lambda (c) (Contact-mode-set c (Pinched))) pressed))))

    (: cdr-list (All (T) (-> (List T) (List T))))
    (define (cdr-list items)
      (match items
        ((Cons _ rest) rest)
        ((Nil) (Nil))))

    (: without-contact (-> (List Contact) I32 (List Contact)))
    (define (without-contact contacts pointer)
      (filter (lambda (c) (not (= (Contact-pointer c) pointer))) contacts))

    ;; A pointer pressed alone may drag; among others, moves pinch. A moving
    ;; pointer that is not pressed points.
    (: move-contact (-> (List Contact) I32 I32 I32 (Pair Gestures (List Gesture))))
    (define (move-contact contacts pointer x y)
      (match (find (lambda (c) (= (Contact-pointer c) pointer)) contacts)
        ((Some contact) (if (null? (cdr-list contacts))
                            (lone-move contact x y)
                            (let ((moved (map (lambda (c) (if (= (Contact-pointer c) pointer) (Contact-y-set (Contact-x-set c x) y) c)) contacts)))
                              (Pair (Gestures moved) (pinch contacts moved)))))
        ((None) (Pair (Gestures contacts) (list (Point x y))))))

    ;; A held pointer drags once it is eight pixels from where it went down,
    ;; and its first drag covers the whole way from there.
    (: lone-move (-> Contact I32 I32 (Pair Gestures (List Gesture))))
    (define (lone-move contact x y)
      (let ((moved (Contact-y-set (Contact-x-set contact x) y)))
        (match (Contact-mode contact)
          ((Dragging) (Pair (Gestures (list moved)) (list (Drag (- x (Contact-x contact)) (- y (Contact-y contact))))))
          ((Holding) (if (far? contact x y)
                         (Pair (Gestures (list (Contact-mode-set moved (Dragging)))) (list (Drag (- x (Contact-start-x contact)) (- y (Contact-start-y contact)))))
                         (Pair (Gestures (list moved)) (Nil))))
          ((Pinched) (Pair (Gestures (list moved)) (Nil))))))

    (: far? (-> Contact I32 I32 Bool))
    (define (far? contact x y)
      (let ((dx (- x (Contact-start-x contact))) (dy (- y (Contact-start-y contact))))
        (> (+ (* dx dx) (* dy dy)) 64)))

    (: pinch (-> (List Contact) (List Contact) (List Gesture)))
    (define (pinch before after)
      (let ((old (spread before)) (new (spread after)))
        (if (and (> old 0.0) (> new 0.0) (not (= old new))) (list (Pinch (/ old new))) (Nil))))

    ;; The distance between the first two pointers.
    (: spread (-> (List Contact) F32))
    (define (spread contacts)
      (match contacts
        ((Cons a (Cons b _)) (let ((dx (i32->f32 (- (Contact-x a) (Contact-x b)))) (dy (i32->f32 (- (Contact-y a) (Contact-y b)))))
                               (sqrt (+ (* dx dx) (* dy dy)))))
        (_ 0.0)))

    ;; Only a pointer still held, near where it went down, taps.
    (: release-contact (-> (List Contact) I32 I32 I32 (Pair Gestures (List Gesture))))
    (define (release-contact contacts pointer x y)
      (match (find (lambda (c) (= (Contact-pointer c) pointer)) contacts)
        ((Some contact) (Pair (Gestures (without-contact contacts pointer))
                              (match (Contact-mode contact)
                                ((Holding) (if (far? contact x y) (Nil) (list (Tap x y (Contact-button contact)))))
                                (_ (Nil)))))
        ((None) (Pair (Gestures contacts) (Nil)))))

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
    ;; tile is a flat unit square at y = 0, and a quad an upright one facing
    ;; +z. Each face maps a texture's whole region.
    (enum Mesh
      (Box)
      (Pyramid)
      (Prism)
      (Sphere)
      (Tile)
      (Tetrahedron)
      (Octahedron)
      (Quad))

    ;; ---- Pictures ----

    ;; A rectangle of pixels: its left and top edges, then its size.
    (struct Rect
      ((x I32)
       (y I32)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    ;; An encoded image file, PNG or anything else the browser decodes. The
    ;; host decodes each key once, so `bytes` runs only when it has not.
    (struct Source
      ((key I32)
       (bytes (-> Bytes))))

    ;; The pixels of `source` within `from`, drawn with their top left at
    ;; (x, y) of the picture. Each swap replaces the 0xRRGGBB color first in
    ;; the pair with the second, keeping alpha: art drawn in one palette can
    ;; be recolored, as LPC skin ramps are.
    (struct Layer
      ((source Source)
       (from Rect)
       (x I32)
       (y I32)
       (swaps (List (Pair I32 I32)))))

    ;; A texture the host composes from layers, drawn in order over
    ;; transparency. Like a batch, it is kept until its version changes, so
    ;; `layers` runs only when the host lacks this version.
    (struct Picture
      ((key I32)
       (version I32)
       (width I32)
       (height I32)
       (layers (-> (List Layer)))))

    ;; A region of a picture. With more than one frame it is a strip: the
    ;; host shows `frames` regions side by side, starting at `region` and
    ;; stepping right by its width, each for `period` milliseconds.
    (struct Texture
      ((picture I32)
       (region Rect)
       (frames I32)
       (period I32)))

    (: still (-> I32 Rect Texture))
    (define (still picture region)
      (Texture picture region 1 1))

    ;; How a surface reflects light, in the metallic-roughness model. The
    ;; texture times the item's color is the albedo of a dielectric, or the
    ;; specular color of a metal. Transparent texels are not drawn.
    (struct Material
      ((texture (Option Texture))
       (metalness F32)
       (roughness F32)))

    ;; Untextured and fully rough, as a matte dielectric.
    (define plain (Material (None) 0.0 1.0))

    ;; A fixed item turns by its yaw alone; an upright one also turns about
    ;; the vertical axis to face the camera, as sprites do.
    (enum Facing
      (Fixed)
      (Upright))

    ;; ---- Items ----

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
       (from Vec3)
       (material Material)
       (facing Facing)))

    ;; An unlit, plain item standing still.
    (: item (-> Mesh Vec3 Vec3 F32 I32 Item))
    (define (item mesh position scale yaw color)
      (Item mesh position scale yaw color 0.0 position plain (Fixed)))

    ;; A texture on a quad `width` by `height` world units, its bottom center
    ;; at `position`, standing upright toward the camera.
    (: sprite (-> Texture Vec3 F32 F32 Item))
    (define (sprite texture position width height)
      (Item (Quad) position (Vec3 width height 1.0) 0.0 (rgb 255 255 255) 0.0 position (Material (Some texture) 0.0 1.0)
            (Upright)))

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

    ;; ---- HUD ----

    (enum Tone
      (Plain)
      (Good)
      (Warning)
      (Danger)
      (Muted))

    (enum Control
      (Enabled)
      (Disabled)
      (Selected))

    ;; How a widget appears: `key` identifies it from one update to the next
    ;; and names it for the page's style, `icon` names a symbol the style
    ;; draws, `help` is its tooltip and accessible description, and `badge`
    ;; marks a corner of it.
    (struct Look
      ((key String)
       (icon String)
       (help String)
       (tone Tone)
       (badge String)))

    (: look (-> String Look))
    (define (look key)
      (Look key "" "" (Plain) ""))

    ;; A button reports its action and argument through `Press`, with a
    ;; caption beneath its text and a ring around it filled to a fraction,
    ;; when the fraction is not negative. A dial is a round readout. An image
    ;; shows a region of a picture, each texel `scale` pixels wide.
    (enum Widget
      (Label ((look Look) (text String)))
      (Button ((look Look) (text String) (caption String) (action I32) (argument I32) (control Control) (ring F32)))
      (Dial ((look Look) (text String) (fraction F32)))
      (Image ((look Look) (picture I32) (region Rect) (scale I32))))

    (enum Corner
      (TopLeft)
      (TopRight)
      (BottomLeft)
      (BottomRight))

    ;; Panels in a corner stack in columns: column 0 against the side of the
    ;; screen, later ones farther in, each running from the corner in the
    ;; order given. A dialog sits in the middle over a backdrop that presses
    ;; `dismiss` when touched.
    (enum Place
      (At ((corner Corner) (column I32)))
      (Dialog ((dismiss I32))))

    (struct Panel
      ((key String)
       (place Place)
       (widgets (List Widget))))

    ;; `motion` moves every item from where it was toward where it is.
    ;; `pictures` are the textures the batches and the HUD may use.
    (struct Frame
      ((camera Camera)
       (light Light)
       (background I32)
       (motion F32)
       (batches (List Batch))
       (pictures (List Picture))))

    (: rgb (-> I32 I32 I32 I32))
    (define (rgb red green blue)
      (+ (* red 65536) (+ (* green 256) blue)))

    ;; ---- Drawing ----

    (effect screen
      ((frame-begin (-> I32 F32 Unit))
       (camera (-> F32 F32 F32 F32 F32 F32 I32 F32 Unit))
       (light (-> F32 F32 F32 F32 F32 Unit))
       (picture-begin (-> I32 I32 I32 I32 Bool))
       (layer (-> I32 I32 I32 I32 I32 I32 I32 Bool))
       (source-begin (-> I32 I32 Unit))
       (source-word (-> I32 Unit))
       (swap (-> I32 I32 Unit))
       (picture-end (-> Unit))
       (batch-begin (-> I32 I32 I32 F32 F32 F32 F32 Bool))
       (instance (-> I32 F32 F32 F32 F32 F32 F32 F32 I32 F32 F32 F32 F32 Unit))
       (surface (-> F32 F32 I32 I32 I32 I32 I32 I32 I32 I32 Unit))
       (frame-end (-> Unit))
       (hud-begin (-> Unit))
       (panel-begin (-> I32 I32 I32 I32 Unit))
       (widget-begin (-> I32 I32 I32 I32 I32 F32 Unit))
       (widget-image (-> I32 I32 I32 I32 I32 I32 Unit))
       (field (-> I32 Unit))
       (text-character (-> Char Unit))
       (hud-end (-> Unit)))
      (host "snail.screen"
            ((frame-begin "frame-begin")
             (camera "camera")
             (light "light")
             (picture-begin "picture-begin")
             (layer "layer")
             (source-begin "source-begin")
             (source-word "source-word")
             (swap "swap")
             (picture-end "picture-end")
             (batch-begin "batch-begin")
             (instance "instance")
             (surface "surface")
             (frame-end "frame-end")
             (hud-begin "hud-begin")
             (panel-begin "panel-begin")
             (widget-begin "widget-begin")
             (widget-image "widget-image")
             (field "field")
             (text-character "text-character")
             (hud-end "hud-end"))))

    (: render (-> Frame Unit ! screen))
    (define (render frame)
      (frame-begin (Frame-background frame) (Frame-motion frame))
      (render-camera (Frame-camera frame))
      (render-light (Frame-light frame))
      (for-each render-picture (Frame-pictures frame))
      (for-each render-batch (Frame-batches frame))
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

    ;; A picture's layers travel only when the host lacks this version, and a
    ;; source's bytes only when the host has never decoded it.
    (: render-picture (-> Picture Unit ! screen))
    (define (render-picture picture)
      (unless (picture-begin (Picture-key picture) (Picture-version picture) (Picture-width picture) (Picture-height picture))
        (for-each render-layer ((Picture-layers picture)))
        (picture-end)))

    (: render-layer (-> Layer Unit ! screen))
    (define (render-layer piece)
      (let ((from (Layer-from piece)) (source (Layer-source piece)))
        (unless (layer (Source-key source) (Rect-x from) (Rect-y from) (Rect-width from) (Rect-height from) (Layer-x piece) (Layer-y piece))
          (send-source source))
        (for-each (lambda (pair) (swap (Pair-first pair) (Pair-second pair))) (Layer-swaps piece))))

    ;; Bytes go four at a time, little-endian, the last word padded.
    (: send-source (-> Source Unit ! screen))
    (define (send-source source)
      (let* ((bytes ((Source-bytes source))) (count (vector-length bytes))
             (byte (lambda (index) (if (< index count) (u8->i32 (vector-ref bytes index)) 0))))
        (source-begin (Source-key source) (i64->i32 count))
        (let loop ((index 0))
          (when (< index count)
            (source-word (+ (byte index)
                            (+ (i32-shift-left (byte (+ index 1)) 8) (+ (i32-shift-left (byte (+ index 2)) 16) (i32-shift-left (byte (+ index 3)) 24)))))
            (loop (+ index 4))))))

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
                  (Vec3-x from) (Vec3-y from) (Vec3-z from))
        (render-surface (Item-material item) (Item-facing item))))

    ;; A material and facing follow each instance: an untextured one names
    ;; picture -1.
    (: render-surface (-> Material Facing Unit ! screen))
    (define (render-surface material facing)
      (let ((turn (match facing ((Fixed) 0) ((Upright) 1))))
        (match (Material-texture material)
          ((Some texture)
           (let ((region (Texture-region texture)))
             (surface (Material-metalness material) (Material-roughness material) turn (Texture-picture texture)
                      (Rect-x region) (Rect-y region) (Rect-width region) (Rect-height region) (Texture-frames texture) (Texture-period texture))))
          ((None) (surface (Material-metalness material) (Material-roughness material) turn -1 0 0 0 0 1 1)))))

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
        ((Octahedron) 6)
        ((Quad) 7)))

    ;; The HUD is sent apart from frames, only when it may have changed.
    (: render-hud (-> (List Panel) Unit ! screen))
    (define (render-hud panels)
      (hud-begin)
      (for-each render-panel panels)
      (hud-end))

    (: render-panel (-> Panel Unit ! screen))
    (define (render-panel panel)
      (match (Panel-place panel)
        ((At corner column) (panel-begin 0 (corner-index corner) column 0))
        ((Dialog dismiss) (panel-begin 1 0 0 dismiss)))
      (render-field 0 (Panel-key panel))
      (for-each render-widget (Panel-widgets panel)))

    (: corner-index (-> Corner I32))
    (define (corner-index corner)
      (match corner
        ((TopLeft) 0)
        ((TopRight) 1)
        ((BottomLeft) 2)
        ((BottomRight) 3)))

    ;; A widget's kind and numbers, then its strings, each named by a field:
    ;; 0 key, 1 icon, 2 help, 3 badge, 4 text, 5 caption.
    (: render-widget (-> Widget Unit ! screen))
    (define (render-widget widget)
      (match widget
        ((Label face text) (widget-begin 0 (tone-index (Look-tone face)) 0 0 0 0.0) (render-look face) (render-field 4 text))
        ((Button face text caption action argument control ring)
         (widget-begin 1 (tone-index (Look-tone face)) action argument (control-index control) ring)
         (render-look face) (render-field 4 text) (render-field 5 caption))
        ((Dial face text fraction) (widget-begin 2 (tone-index (Look-tone face)) 0 0 0 fraction) (render-look face) (render-field 4 text))
        ((Image face picture region scale)
         (widget-begin 3 (tone-index (Look-tone face)) 0 0 0 0.0)
         (widget-image picture (Rect-x region) (Rect-y region) (Rect-width region) (Rect-height region) scale)
         (render-look face))))

    (: render-look (-> Look Unit ! screen))
    (define (render-look face)
      (render-field 0 (Look-key face))
      (render-field 1 (Look-icon face))
      (render-field 2 (Look-help face))
      (render-field 3 (Look-badge face)))

    (: tone-index (-> Tone I32))
    (define (tone-index tone)
      (match tone
        ((Plain) 0)
        ((Good) 1)
        ((Warning) 2)
        ((Danger) 3)
        ((Muted) 4)))

    (: control-index (-> Control I32))
    (define (control-index control)
      (match control
        ((Enabled) 0)
        ((Disabled) 1)
        ((Selected) 2)))

    ;; Empty strings are not sent.
    (: render-field (-> I32 String Unit ! screen))
    (define (render-field which text)
      (when (> (string-length text) 0)
        (field which)
        (let loop ((index 0))
          (when (< index (string-length text))
            (text-character (string-ref text index))
            (loop (+ index 1))))))

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
        ((_ State init update view hud save restore)
         (begin
           (define current (ref (ann (None) (Option State))))
           (define saved (ref (vector-generate 0 (lambda (index) (ann 0 U8)))))
           (define loading (ref (make-array 0 (ann 0 U8))))
           (define since-hud (ref (ann 0 I32)))

           ;; Replaces the state and shows its HUD.
           (: settle (-> State Unit ! mut screen))
           (define (settle state)
             (ref-set! current (Some state))
             (ref-set! since-hud 0)
             (render-hud (hud state)))

           ;; Time alone shows the HUD again only every tenth of a second.
           (: pass-time (-> State I32 Unit ! mut screen))
           (define (pass-time state milliseconds)
             (ref-set! since-hud (+ (ref-get since-hud) milliseconds))
             (if (>= (ref-get since-hud) 100) (settle state) (ref-set! current (Some state))))

           (: app-init (-> I32 I32 I32 Unit ! mut screen))
           (define (app-init seed width height)
             (settle (init seed width height)))

           (: app-input (-> I32 I32 I32 I32 I32 Unit ! mut screen))
           (define (app-input kind a b c d)
             (match (ref-get current)
               ((Some state) (let ((input (decode-input kind a b c d)))
                               (match input
                                 ((Elapsed milliseconds) (pass-time (update state input) milliseconds))
                                 (_ (settle (update state input))))))
               ((None) (unit))))

           (: app-frame (-> Unit ! mut screen))
           (define (app-frame)
             (match (ref-get current)
               ((Some state) (render (view state)))
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
           (: app-load-end (-> Unit ! mut screen))
           (define (app-load-end)
             (settle (ann (restore (deserialize (array->vector (ref-get loading)))) State)))

           (expose app-init "app_init")
           (expose app-input "app_input")
           (expose app-frame "app_frame")
           (expose app-save "app_save")
           (expose app-save-byte "app_save_byte")
           (expose app-load-begin "app_load_begin")
           (expose app-load-byte "app_load_byte")
           (expose app-load-end "app_load_end")))))

    ))
