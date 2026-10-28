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
;; `define-application` runs one loop inside the binder returned by reset.
;; The loop suspends on events and storage through JSPI. It checkpoints
;; complete events in one cell. Time reaches the state as input, so the
;; state decides how time passes, and can stop it at any frame. The host
;; draws a Frame through the `screen` effect, shows the HUD again after
;; each input (after time, at most ten times a second), and stores the
;; serialized Save. The Save may be much smaller than the state: a record
;; of how to rebuild it. A development server (`./scripts/snail-tool serve`) relinks a
;; running page's rebuilt modules and hands the state to the new program
;; as it is, or through the save when its types changed.
;;
;; Scenes are 3D. Meshes and sprites are both items, drawn by one shader in
;; the metallic-roughness model; a sprite is a textured quad that stands
;; upright toward the camera, so 2D and 2.5D are scenes too. Textures are
;; pictures the host composes from regions of encoded image files that the
;; program carries, typically as byte literals.
(define-library (snail-core app)
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
   flat-sprite
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
   Look-key
   Look-help
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
   screen
   render
   Ray
   Ray-origin
   Ray-direction
   pointer-ray
   screen-axes
   ground-point
   Event
   FrameEvent
   InputEvent
   Hidden
   Reload
   events
   next-event
   storage
   load-save
   store-save
   default-reset
   define-application)
  (import
   (snail-core base)
   (snail-core task)
   (snail-core wire)
   (snail-core math))
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
      (PointerUp ((pointer I32) (x I32) (y I32)))
      (PointerCancel ((pointer I32)))
      (Wheel ((pixels I32)))
      (Resize ((width I32) (height I32)))
      (Press ((action I32) (argument I32)))
      (Hover ((action I32) (argument I32)))
      (Elapsed ((milliseconds I32))))

    (: key-left I32)
    (define key-left 1)
    (: key-right I32)
    (define key-right 2)
    (: key-up I32)
    (define key-up 3)
    (: key-down I32)
    (define key-down 4)
    (: key-escape I32)
    (define key-escape 27)
    (: key-enter I32)
    (define key-enter 13)
    (: key-space I32)
    (define key-space 32)

    ;; The kinds match the input encoding in host/browser/host.mjs.
    (: decode-input (-> I32 I32 I32 I32 I32 Input))
    (define (decode-input kind a b c d)
      (case kind
        ((1) (KeyDown a (= b 1)))
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
          ((PointerDown pointer x y button)
           (Pair (Gestures (press-contact contacts (Contact pointer button x y x y (Holding))))
                 (Nil)))
          ((PointerMove pointer x y) (move-contact contacts pointer x y))
          ((PointerUp pointer x y) (release-contact contacts pointer x y))
          ((PointerCancel pointer) (Pair (Gestures (without-contact contacts pointer)) (Nil)))
          (_ (Pair gestures (Nil))))))

    ;; A pointer that goes down again replaces its old press, which also
    ;; recovers from a release that never arrived.
    (: press-contact (-> (List Contact) Contact (List Contact)))
    (define (press-contact contacts contact)
      (let ((pressed (append (without-contact contacts (Contact-pointer contact)) (list contact))))
        (if (null? (cdr-list pressed))
            pressed
            (map (lambda (c) (Contact-mode-set c (Pinched))) pressed))))

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
                            (let ((moved (map (lambda (c)
                                                (if (= (Contact-pointer c) pointer)
                                                    (Contact-y-set (Contact-x-set c x) y)
                                                    c))
                                              contacts)))
                              (Pair (Gestures moved) (pinch contacts moved)))))
        ((None) (Pair (Gestures contacts) (list (Point x y))))))

    ;; A held pointer drags once it is eight pixels from where it went down,
    ;; and its first drag covers the whole way from there.
    (: lone-move (-> Contact I32 I32 (Pair Gestures (List Gesture))))
    (define (lone-move contact x y)
      (let ((moved (Contact-y-set (Contact-x-set contact x) y)))
        (match (Contact-mode contact)
          ((Dragging)
           (Pair (Gestures (list moved))
                 (list (Drag (- x (Contact-x contact)) (- y (Contact-y contact))))))
          ((Holding) (if (far? contact x y)
                         (Pair (Gestures (list (Contact-mode-set moved (Dragging))))
                               (list (Drag (- x (Contact-start-x contact))
                                           (- y (Contact-start-y contact)))))
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
        ((Cons a (Cons b _))
         (let ((dx (i32->f32 (- (Contact-x a) (Contact-x b))))
               (dy (i32->f32 (- (Contact-y a) (Contact-y b)))))
           (sqrt (+ (* dx dx) (* dy dy)))))
        (_ 0.0)))

    ;; Only a pointer still held, near where it went down, taps.
    (: release-contact (-> (List Contact) I32 I32 I32 (Pair Gestures (List Gesture))))
    (define (release-contact contacts pointer x y)
      (match (find (lambda (c) (= (Contact-pointer c) pointer)) contacts)
        ((Some contact) (Pair (Gestures (without-contact contacts pointer))
                              (match (Contact-mode contact)
                                ((Holding)
                                 (if (far? contact x y)
                                     (Nil)
                                     (list (Tap x y (Contact-button contact)))))
                                (_ (Nil)))))
        ((None) (Pair (Gestures contacts) (Nil)))))

    ;; ---- Frames ----

    ;; What the host draws: a camera, the light, a 0xRRGGBB background,
    ;; how far from 0 to 1 every item has moved from where it was toward
    ;; where it is, the batches of items, and the pictures the batches and
    ;; the HUD may use as textures.
    (struct Frame
      ((camera Camera)
       (light Light)
       (background I32)
       (motion F32)
       (batches (List Batch))
       (pictures (List Picture))))

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

    ;; A 0xRRGGBB color.
    (: rgb (-> I32 I32 I32 I32))
    (define (rgb red green blue)
      (+ (* red 65536) (+ (* green 256) blue)))

    ;; An unlit, plain item standing still.
    (: item (-> Mesh Vec3 Vec3 F32 I32 Item))
    (define (item mesh position scale yaw color)
      (Item mesh position scale yaw color 0.0 position plain (Fixed)))

    ;; A texture on a quad `width` by `height` world units, its bottom center
    ;; at `position`, standing upright toward the camera: a sprite in a 2.5D
    ;; scene.
    (: sprite (-> Texture Vec3 F32 F32 Item))
    (define (sprite texture position width height)
      (Item (Quad)
            position
            (Vec3 width height 1.0)
            0.0
            (rgb 255 255 255)
            0.0
            position
            (Material (Some texture) 0.0 1.0)
            (Upright)))

    ;; A texture lying on the ground, `width` by `height` world units, its
    ;; top toward -z and the middle of its bottom edge at `position`: a sprite
    ;; in a 2D scene seen straight down, where -z is the top of the screen.
    ;; It shows the texture's own colors, unlit.
    (: flat-sprite (-> Texture Vec3 F32 F32 Item))
    (define (flat-sprite texture position width height)
      (let ((center
             (Vec3 (Vec3-x position) (Vec3-y position) (- (Vec3-z position) (/ height 2.0)))))
        (Item (Tile)
              center
              (Vec3 width 1.0 height)
              0.0
              (rgb 255 255 255)
              1.0
              center
              (Material (Some texture) 0.0 1.0)
              (Fixed))))

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
    ;; when the fraction is not negative. A dial is a round readout. A link
    ;; opens `url` in a new page and reports nothing. A text is a label
    ;; whose words may be strong in places. An image shows a region of a
    ;; picture, each texel `scale` pixels wide.
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
      (Image ((look Look) (picture I32) (region Rect) (scale I32))))

    (enum Span
      (Normal ((words String)))
      (Strong ((words String))))

    ;; The widgets most panels are made of: a plain label, and an enabled
    ;; button without caption or ring that presses `action` with argument
    ;; 0.
    (: label (-> String String Widget))
    (define (label key text)
      (Label (look key) text))

    (: button (-> String String I32 Widget))
    (define (button key text action)
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

    (struct Panel
      ((key String)
       (place Place)
       (widgets (List Widget))))

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

    ;; Kind 0 is perspective and 1 orthographic, as in host/browser/renderer.mjs.
    (: render-camera (-> Camera Unit ! screen))
    (define (render-camera view)
      (let ((eye (Camera-eye view)) (target (Camera-target view)))
        (match (Camera-projection view)
          ((Perspective fov)
           (camera (Vec3-x eye)
                   (Vec3-y eye)
                   (Vec3-z eye)
                   (Vec3-x target)
                   (Vec3-y target)
                   (Vec3-z target)
                   0
                   fov))
          ((Orthographic height)
           (camera (Vec3-x eye)
                   (Vec3-y eye)
                   (Vec3-z eye)
                   (Vec3-x target)
                   (Vec3-y target)
                   (Vec3-z target)
                   1
                   height)))))

    (: render-light (-> Light Unit ! screen))
    (define (render-light sunlight)
      (let ((direction (Light-direction sunlight)))
        (light (Vec3-x direction)
               (Vec3-y direction)
               (Vec3-z direction)
               (Light-sun sunlight)
               (Light-ambient sunlight))))

    ;; A picture's layers travel only when the host lacks this version, and a
    ;; source's bytes only when the host has never decoded it.
    (: render-picture (-> Picture Unit ! screen))
    (define (render-picture picture)
      (unless (picture-begin (Picture-key picture)
                             (Picture-version picture)
                             (Picture-width picture)
                             (Picture-height picture))
        (for-each render-layer ((Picture-layers picture)))
        (picture-end)))

    (: render-layer (-> Layer Unit ! screen))
    (define (render-layer piece)
      (let ((from (Layer-from piece)) (source (Layer-source piece)))
        (unless (layer (Source-key source)
                       (Rect-x from)
                       (Rect-y from)
                       (Rect-width from)
                       (Rect-height from)
                       (Layer-x piece)
                       (Layer-y piece))
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
                            (+ (i32-shift-left (byte (+ index 1)) 8)
                               (+ (i32-shift-left (byte (+ index 2)) 16)
                                  (i32-shift-left (byte (+ index 3)) 24)))))
            (loop (+ index 4))))))

    ;; The style travels with every frame; the items only when the host lacks
    ;; this version. Styles 0 to 2 match the `styles` of host/browser/host.mjs.
    (: render-batch (-> Batch Unit ! screen))
    (define (render-batch batch)
      (unless (match (Batch-style batch)
                ((Solid) (batch-begin (Batch-key batch) (Batch-version batch) 0 1.0 0.0 0.0 0.0))
                ((Translucent opacity)
                 (batch-begin (Batch-key batch) (Batch-version batch) 1 opacity 0.0 0.0 0.0))
                ((Revealed center radius)
                 (batch-begin (Batch-key batch)
                              (Batch-version batch)
                              2
                              1.0
                              (Vec3-x center)
                              (Vec3-z center)
                              radius)))
        (for-each render-item ((Batch-items batch)))))

    (: render-item (-> Item Unit ! screen))
    (define (render-item item)
      (let ((position (Item-position item)) (scale (Item-scale item)) (from (Item-from item)))
        (instance (mesh-index (Item-mesh item))
          (Vec3-x position)
          (Vec3-y position)
          (Vec3-z position)
          (Vec3-x scale)
          (Vec3-y scale)
          (Vec3-z scale)
          (Item-yaw item)
          (Item-color item)
          (Item-glow item)
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
             (surface (Material-metalness material)
                      (Material-roughness material)
                      turn
                      (Texture-picture texture)
                      (Rect-x region)
                      (Rect-y region)
                      (Rect-width region)
                      (Rect-height region)
                      (Texture-frames texture)
                      (Texture-period texture))))
          ((None)
           (surface (Material-metalness material)
                    (Material-roughness material)
                    turn
                    -1
                    0
                    0
                    0
                    0
                    1
                    1)))))

    ;; The order matches the meshes in host/browser/renderer.mjs.
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

    ;; Places and corners match host/browser/hud.mjs.
    (: render-panel (-> Panel Unit ! screen))
    (define (render-panel panel)
      (match (Panel-place panel)
        ((At corner column) (panel-begin 0 (corner-index corner) column 0))
        ((Dialog dismiss) (panel-begin 1 0 0 dismiss))
        ((Banner) (panel-begin 2 0 0 0)))
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
    ;; 0 key, 1 icon, 2 help, 3 badge, 4 text, 5 caption, 6 url, then each
    ;; span of a text, 7 normal or 8 strong. Kinds, tones and controls match
    ;; host/browser/hud.mjs, and fields host/browser/host.mjs.
    (: render-widget (-> Widget Unit ! screen))
    (define (render-widget widget)
      (match widget
        ((Label face text)
         (widget-begin 0 (tone-index (Look-tone face)) 0 0 0 0.0)
         (render-look face)
         (render-field 4 text))
        ((Button face text caption action argument control ring)
         (widget-begin 1 (tone-index (Look-tone face)) action argument (control-index control) ring)
         (render-look face) (render-field 4 text) (render-field 5 caption))
        ((Dial face text fraction)
         (widget-begin 2 (tone-index (Look-tone face)) 0 0 0 fraction)
         (render-look face)
         (render-field 4 text))
        ((Link face text url)
         (widget-begin 3 (tone-index (Look-tone face)) 0 0 0 0.0)
         (render-look face)
         (render-field 4 text)
         (render-field 6 url))
        ((Text face spans)
         (widget-begin 4 (tone-index (Look-tone face)) 0 0 0 0.0)
         (render-look face)
         (for-each render-span spans))
        ((Image face picture region scale)
         (widget-begin 5 (tone-index (Look-tone face)) 0 0 0 0.0)
         (widget-image picture
                       (Rect-x region)
                       (Rect-y region)
                       (Rect-width region)
                       (Rect-height region)
                       scale)
         (render-look face))))

    (: render-span (-> Span Unit ! screen))
    (define (render-span span)
      (match span
        ((Normal words) (render-field 7 words))
        ((Strong words) (render-field 8 words))))

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
        ((Muted) 4)
        ((Suggested) 5)))

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
             (axes (screen-axes view)) (right (Pair-first axes)) (up (Pair-second axes))
             (aspect (/ (i32->f32 width) (i32->f32 (max height 1))))
             (px (- (* 2.0 (/ (+ (i32->f32 x) 0.5) (i32->f32 (max width 1)))) 1.0))
             (py (- 1.0 (* 2.0 (/ (+ (i32->f32 y) 0.5) (i32->f32 (max height 1)))))))
        (match (Camera-projection view)
          ((Perspective fov)
           (let ((half (f64->f32 (tan (/ (f32->f64 fov) 2.0)))))
             (Ray eye
                  (normalize (add forward
                                  (add (scale right (* px (* half aspect)))
                                       (scale up (* py half))))))))
          ((Orthographic height)
           (let ((half (/ height 2.0)))
             (Ray (add eye (add (scale right (* px (* half aspect))) (scale up (* py half))))
                  forward))))))

    ;; The directions of the screen's right and up in the world. A camera
    ;; looking straight down has up toward -z, so it shows the ground as a
    ;; map with the far side at the top, as a camera tilted down from +z
    ;; would; the renderer uses the same rule.
    (: screen-axes (-> Camera (Pair Vec3 Vec3)))
    (define (screen-axes view)
      (let* ((forward (normalize (subtract (Camera-target view) (Camera-eye view))))
             (sky (if (> (abs (Vec3-y forward)) 0.999) (Vec3 0.0 0.0 -1.0) (Vec3 0.0 1.0 0.0)))
             (right (normalize (cross forward sky))))
        (Pair right (cross right forward))))

    ;; Where the ray through pixel (x, y) meets the ground plane y = 0.
    (: ground-point (-> Camera I32 I32 I32 I32 (Option Vec3)))
    (define (ground-point view x y width height)
      (let* ((ray (pointer-ray view x y width height))
             (origin (Ray-origin ray))
             (direction (Ray-direction ray)))
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
      (scale v
             (/ 1.0
                (sqrt (+ (* (Vec3-x v) (Vec3-x v))
                         (+ (* (Vec3-y v) (Vec3-y v)) (* (Vec3-z v) (Vec3-z v))))))))

    ;; ---- Application events ----

    ;; Frame already names the drawing data above; FrameEvent names a tick.
    (enum Event
      (FrameEvent ((elapsed I32)))
      (InputEvent ((input Input)))
      (Hidden)
      (Reload))

    (effect events
      ((poll-event (-> I32))
       (wait-event (-> Unit))
       (event-field (-> I32 I32))
       (random-seed (-> I32))
       (canvas-width (-> I32))
       (canvas-height (-> I32))
       (report-boot (-> I32 Unit)))
      (host "snail.events"
            ((poll-event "poll")
             (wait-event "wait")
             (event-field "field")
             (random-seed "seed")
             (canvas-width "width")
             (canvas-height "height")
             (report-boot "boot"))))

    (: next-event (-> Event ! events))
    (define (next-event)
      (match (poll-event)
        (0 (wait-event) (next-event))
        (11 (FrameEvent (event-field 0)))
        (12 (Hidden))
        (13 (Reload))
        (kind (InputEvent (decode-input kind
                                        (event-field 0)
                                        (event-field 1)
                                        (event-field 2)
                                        (event-field 3))))))

    ;; The application root owns this checkpoint protocol. Detached tasks
    ;; need their own storage binding; they cannot replace the loop's save.
    (effect storage
      ((load-count (-> I32))
       (loaded-byte (-> I32 U8))
       (store-save (-> Bytes Unit)))
      (host "snail.storage"
            ((load-count "load")
             (loaded-byte "byte")
             (store-save "store"))))

    (: load-save (-> (Option Bytes) ! storage))
    (define (load-save)
      (let ((count (load-count)))
        (if (< count 0)
            (None)
            (Some
             (vector-generate (i32->i64 count) (lambda (index) (loaded-byte (i64->i32 index))))))))

    ;; Instantiate the result and row on reset, not on the returned binder.
    ;; An application can replace this binder to install handlers for the run.
    (: default-reset (All (T e) (-> (-> (-> T ! e) T ! e))))
    (define (default-reset)
      (lambda (run) (run)))

    ;; ---- Applications ----

    ;; Only the loop calls application messages. The cell is the last state
    ;; whose entire event succeeded; a trap never publishes its candidate.
    ;; States must be immutable data, so a handed-over checkpoint stays reusable.
    ;; The loop itself performs `mut screen events storage`. A reset binder
    ;; that performs more, such as one that dispatches tasks, names those
    ;; effects with `effects:`, because the checker holds `app-main`'s row to
    ;; what its body performs.
    (define-syntax define-application
      (syntax-rules (reset: effects: init: update: view: hud: save: restore:)
        ((_ State (reset: reset-run) (init: initialize) more ...)
         (define-application State (reset: reset-run) (effects:) (init: initialize) more ...))
        ((_ State
            (reset: reset-run)
            (effects: effect ...)
            (init: initialize)
            (update: step)
            (view: draw)
            (hud: panels) (save: save-state) (restore: restore-state))
         (begin
           (define current (ref (ann (None) (Option State))))

           ;; A live migration must refuse an absent or incompatible save.
           ;; Cold startup alone may initialize when there is no saved game.
           (: app-restore (-> Bool (Option (Pair State I32)) ! events storage))
           (define (app-restore cold?)
             (match (load-save)
               ((Some bytes) (Some (Pair (app-restore-bytes bytes) 1)))
               ((None) (if cold?
                           (Some (Pair ((ann initialize (-> I32 I32 I32 State))
                                        (random-seed)
                                        (canvas-width)
                                        (canvas-height))
                                       2))
                           (None)))))

           (: app-boot (-> (Option Any) (Option (Pair State I32)) ! events storage))
           (define (app-boot handover)
             (match handover
               ((Some state) (if (type-test state State)
                                 (Some (Pair (ann (type-convert state State) State) 0))
                                 (app-restore #f)))
               ((None) (app-restore #t))))

           (: app-save-bytes (-> State Bytes))
           (define (app-save-bytes state)
             (serialize (save-state state)))

           (: app-restore-bytes (-> Bytes State))
           (define (app-restore-bytes bytes)
             (restore-state (deserialize bytes)))

           ;; Counters are loop variables, committed with the state. Build
           ;; pure frame/HUD values before their presentation can have effects.
           (: app-frame (-> State I32 I32 I32 (Option Any) ! mut screen events storage))
           (define (app-frame state elapsed since-hud since-save)
             (let* ((next ((ann step (-> State Input State)) state (Elapsed elapsed)))
                    (frame ((ann draw (-> State Frame)) next))
                    (hud-time (+ since-hud elapsed))
                    (save-time (+ since-save elapsed))
                    (show-hud? (>= hud-time 100))
                    (widgets (if show-hud? ((ann panels (-> State (List Panel))) next) (Nil))))
               (render frame)
               (when show-hud? (render-hud widgets))
               (when (>= save-time 5000) (store-save (app-save-bytes next)))
               (app-run next (if show-hud? 0 hud-time) (if (>= save-time 5000) 0 save-time))))

           (: app-run (-> State I32 I32 (Option Any) ! mut screen events storage))
           (define (app-run state since-hud since-save)
             (ref-set! current (Some state))
             (match (next-event)
               ((FrameEvent elapsed) (app-frame state elapsed since-hud since-save))
               ((InputEvent input)
                (let* ((next ((ann step (-> State Input State)) state input))
                       (widgets ((ann panels (-> State (List Panel))) next)))
                  (render-hud widgets)
                  (app-run next 0 since-save)))
               ((Hidden) (store-save (app-save-bytes state)) (app-run state since-hud 0))
               ((Reload) (store-save (app-save-bytes state)) (Some (type-convert state Any)))))

           ;; The host's first Resize and Frame(0) own initial presentation.
           ;; reset installs its handlers around this monomorphic run.
           (: app-main (-> (Option Any) (Option Any) ! mut screen events storage effect ...))
           (define (app-main handover)
             ((reset-run)
              (lambda ()
                (match (app-boot handover)
                  ((Some boot)
                   (let ((state (Pair-first boot)))
                     (ref-set! current (Some state))
                     (report-boot (Pair-second boot))
                     (app-run state 0 0)))
                  ((None) (None))))))

           (: app-state (-> Any ! mut))
           (define (app-state)
             (match (ref-get current)
               ((Some state) (type-convert state Any))
               ((None) (panic "the application has no state yet"))))

           (expose app-main "app_main")
           (expose app-state "app_state")))))

    ))
