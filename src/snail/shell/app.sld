;; Interactive applications. An application is four total functions over
;; its state, and two that convert the state to and from what it saves:
;;
;;   init    : seed width height -> State
;;   update  : State Input -> State
;;   view    : State -> Frame
;;   hud     : State -> (List Panel)
;;   save    : State -> Bytes
;;   restore : Bytes -> State
;;
;; `SceneApplication` implements the ordinary Application class. Its loop
;; presents complete events and commits them through (snail shell page),
;; which owns boot, restore and durable saves for both browser engines.
;; Time is input, so the state decides how its simulation advances. The
;; host draws a Frame through `screen` and updates HUD values after each
;; input (after time, at most ten times a second). A durable save may be
;; much smaller than the state: a record of how to rebuild it.
;;
;; Scenes are 3D. Meshes and sprites are both items, drawn by one shader in
;; the metallic-roughness model; a sprite is a textured quad that stands
;; upright toward the camera, so 2D and 2.5D are scenes too. Textures are
;; pictures the host composes from regions of encoded image files that the
;; program carries, typically as byte literals.
(define-library (snail shell app)
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
   Quad
   Rect
   Source
   Layer
   Picture
   Texture
   Texture-region-set
   still
   Material
   plain
   Facing
   Fixed
   Upright
   Item
   Item-position-set
   Item-scale-set
   Item-yaw-set
   Item-color-set
   Item-glow-set
   Item-from-set
   Item-material-set
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
   pointer-ray
   screen-axes
   ground-point
   Event
   FrameEvent
   InputEvent
   Hidden
   SaveRequested
   Reload
   events
   next-event
   storage
   load-save
   store-save
   PageState
   define-page-state
   Scene
   SceneApplication
   scene-initialize
   scene-update
   scene-view
   scene-hud
   scene-save
   scene-restore)
  (import
   (rename (snail core base) (instance class-instance))
   (only (snail core forms) host)
   (prefix (snail runtime browser screen) host-)
   (snail shell task)
   (snail shell application)
   (snail shell math)
   (snail shell page))
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

    (define key-left (→ I32) 1)

    (define key-right (→ I32) 2)

    (define key-up (→ I32) 3)

    (define key-down (→ I32) 4)

    (define key-escape (→ I32) 27)

    (define key-enter (→ I32) 13)

    (define key-space (→ I32) 32)

    ;; The kinds match the input encoding in host/browser/host.mjs.

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

    (define no-gestures (→ Gestures) (Gestures (Nil)))

    ;; Reads one input, returning the pointers still pressed and what the
    ;; input meant. Inputs other than pointers mean nothing here.

    (define (recognize (gestures Gestures) (input Input)) (→ (Pair Gestures (List Gesture)))
      (let ((contacts (● gestures contacts)))
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
                              (Pair (Gestures moved) (pinch contacts moved)))))
        ((None) (Pair (Gestures contacts) (list (Point x y))))))

    ;; A held pointer drags once it is eight pixels from where it went down,
    ;; and its first drag covers the whole way from there.

    (define (lone-move (contact Contact) (x I32) (y I32)) (→ (Pair Gestures (List Gesture)))
      (let ((moved (Contact-y-set (Contact-x-set contact x) y)))
        (match (● contact mode)
          ((Dragging)
           (Pair (Gestures (list moved))
                 (list (Drag (- x (● contact x)) (- y (● contact y))))))
          ((Holding) (if (far? contact x y)
                         (Pair (Gestures (list (Contact-mode-set moved (Dragging))))
                               (list (Drag (- x (● contact start-x))
                                           (- y (● contact start-y)))))
                         (Pair (Gestures (list moved)) (Nil))))
          ((Pinched) (Pair (Gestures (list moved)) (Nil))))))

    (define (far? (contact Contact) (x I32) (y I32)) (→ Bool)
      (let ((dx (- x (● contact start-x))) (dy (- y (● contact start-y))))
        (> (+ (* dx dx) (* dy dy)) 64)))

    (define (pinch (before (List Contact)) (after (List Contact))) (→ (List Gesture))
      (let ((old (spread before)) (new (spread after)))
        (if (and (> old 0.0) (> new 0.0) (not (= old new))) (list (Pinch (/ old new))) (Nil))))

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
        ((Some contact) (Pair (Gestures (without-contact contacts pointer))
                              (match (● contact mode)
                                ((Holding)
                                 (if (far? contact x y)
                                     (Nil)
                                     (list (Tap x y (● contact button)))))
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
       (bytes (Fn → Bytes))))

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
       (layers (Fn → (List Layer)))))

    ;; A region of a picture. With more than one frame it is a strip: the
    ;; host shows `frames` regions side by side, starting at `region` and
    ;; stepping right by its width, each for `period` milliseconds.
    (struct Texture
      ((picture I32)
       (region Rect)
       (frames I32)
       (period I32)))

    (define (still (picture I32) (region Rect)) (→ Texture)
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

    (define (rgb (red I32) (green I32) (blue I32)) (→ I32)
      (+ (* red 65536) (+ (* green 256) blue)))

    ;; An unlit, plain item standing still.

    (define (item (mesh Mesh) (position Vec3) (scale Vec3) (yaw F32) (color I32)) (→ Item)
      (Item mesh position scale yaw color 0.0 position plain (Fixed)))

    ;; A texture on a quad `width` by `height` world units, its bottom center
    ;; at `position`, standing upright toward the camera: a sprite in a 2.5D
    ;; scene.

    (define (sprite (texture Texture) (position Vec3) (width F32) (height F32)) (→ Item)
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

    (define (flat-sprite (texture Texture) (position Vec3) (width F32) (height F32)) (→ Item)
      (let ((center
             (Vec3 (● position x) (● position y) (- (● position z) (/ height 2.0)))))
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
    (struct Look
      ((key String)
       (icon String)
       (help String)
       (tone Tone)
       (badge String)))

    (define (look (key String)) (→ Look)
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

    (struct Panel
      ((key String)
       (place Place)
       (widgets (List Widget))))

    ;; ---- Drawing ----

    (effect screen
      ((frame-begin (Fn I32 F32 → Unit))
       (camera (Fn F32 F32 F32 F32 F32 F32 I32 F32 → Unit))
       (light (Fn F32 F32 F32 F32 F32 → Unit))
       (picture-begin (Fn I32 I32 I32 I32 → Bool))
       (layer (Fn I32 I32 I32 I32 I32 I32 I32 → Bool))
       (source-begin (Fn I32 I32 → Unit))
       (source-word (Fn I32 → Unit))
       (swap (Fn I32 I32 → Unit))
       (picture-end (Fn → Unit))
       (batch-begin (Fn I32 I32 I32 F32 F32 F32 F32 → Bool))
       (instance (Fn I32 F32 F32 F32 F32 F32 F32 F32 I32 F32 F32 F32 F32 → Unit))
       (surface (Fn F32 F32 I32 I32 I32 I32 I32 I32 I32 I32 → Unit))
       (frame-end (Fn → Unit))
       (hud-begin (Fn → Unit))
       (panel-begin (Fn I32 I32 I32 I32 → Unit))
       (widget-begin (Fn I32 I32 I32 I32 I32 F32 → Unit))
       (widget-image (Fn I32 I32 I32 I32 I32 I32 → Unit))
       (field (Fn I32 → Unit))
       (text-character (Fn Char → Unit))
       (hud-end (Fn → Unit)))
      (default ((frame-begin host-frame-begin)
                (camera host-camera)
                (light host-light)
                (picture-begin host-picture-begin)
                (layer host-layer)
                (source-begin host-source-begin)
                (source-word host-source-word)
                (swap host-swap)
                (picture-end host-picture-end)
                (batch-begin host-batch-begin)
                (instance host-instance)
                (surface host-surface)
                (frame-end host-frame-end)
                (hud-begin host-hud-begin)
                (panel-begin host-panel-begin)
                (widget-begin host-widget-begin)
                (widget-image host-widget-image)
                (field host-field)
                (text-character host-text-character)
                (hud-end host-hud-end))))

    (define (render (frame Frame)) (→ Unit) (! screen)
      (frame-begin (● frame background) (● frame motion))
      (render-camera (● frame camera))
      (render-light (● frame light))
      (for-each render-picture (● frame pictures))
      (for-each render-batch (● frame batches))
      (frame-end))

    ;; Kind 0 is perspective and 1 orthographic, as in host/browser/renderer.mjs.

    (define (render-camera (view Camera)) (→ Unit) (! screen)
      (let ((eye (● view eye)) (target (● view target)))
        (match (● view projection)
          ((Perspective fov)
           (camera (● eye x)
                   (● eye y)
                   (● eye z)
                   (● target x)
                   (● target y)
                   (● target z)
                   0
                   fov))
          ((Orthographic height)
           (camera (● eye x)
                   (● eye y)
                   (● eye z)
                   (● target x)
                   (● target y)
                   (● target z)
                   1
                   height)))))

    (define (render-light (sunlight Light)) (→ Unit) (! screen)
      (let ((direction (● sunlight direction)))
        (light (● direction x)
               (● direction y)
               (● direction z)
               (● sunlight sun)
               (● sunlight ambient))))

    ;; A picture's layers travel only when the host lacks this version, and a
    ;; source's bytes only when the host has never decoded it.

    (define (render-picture (picture Picture)) (→ Unit) (! screen)
      (unless (picture-begin (● picture key)
                             (● picture version)
                             (● picture width)
                             (● picture height))
        (for-each render-layer ((● picture layers)))
        (picture-end)))

    (define (render-layer (piece Layer)) (→ Unit) (! screen)
      (let ((from (● piece from)) (source (● piece source)))
        (unless (layer (● source key)
                       (● from x)
                       (● from y)
                       (● from width)
                       (● from height)
                       (● piece x)
                       (● piece y))
          (send-source source))
        (for-each (lambda (pair) (swap (● pair first) (● pair second))) (● piece swaps))))

    ;; Bytes go four at a time, little-endian, the last word padded.

    (define (send-source (source Source)) (→ Unit) (! screen)
      (let* ((bytes ((● source bytes))) (count (vector-length bytes))
             (byte (lambda (index) (if (< index count) (u8->i32 (vector-ref bytes index)) 0))))
        (source-begin (● source key) (i64->i32 count))
        (let loop ((index 0))
          (when (< index count)
            (source-word (+ (byte index)
                            (+ (i32-shift-left (byte (+ index 1)) 8)
                               (+ (i32-shift-left (byte (+ index 2)) 16)
                                  (i32-shift-left (byte (+ index 3)) 24)))))
            (loop (+ index 4))))))

    ;; The style travels with every frame; the items only when the host lacks
    ;; this version. Styles 0 to 2 match the `styles` of host/browser/host.mjs.

    (define (render-batch (batch Batch)) (→ Unit) (! screen)
      (unless (match (● batch style)
                ((Solid) (batch-begin (● batch key) (● batch version) 0 1.0 0.0 0.0 0.0))
                ((Translucent opacity)
                 (batch-begin (● batch key) (● batch version) 1 opacity 0.0 0.0 0.0))
                ((Revealed center radius)
                 (batch-begin (● batch key)
                              (● batch version)
                              2
                              1.0
                              (● center x)
                              (● center z)
                              radius)))
        (for-each render-item ((● batch items)))))

    (define (render-item (item Item)) (→ Unit) (! screen)
      (let ((position (● item position)) (scale (● item scale)) (from (● item from)))
        (instance (mesh-index (● item mesh))
          (● position x)
          (● position y)
          (● position z)
          (● scale x)
          (● scale y)
          (● scale z)
          (● item yaw)
          (● item color)
          (● item glow)
          (● from x) (● from y) (● from z))
        (render-surface (● item material) (● item facing))))

    ;; A material and facing follow each instance: an untextured one names
    ;; picture -1.

    (define (render-surface (material Material) (facing Facing)) (→ Unit) (! screen)
      (let ((turn (match facing ((Fixed) 0) ((Upright) 1))))
        (match (● material texture)
          ((Some texture)
           (let ((region (● texture region)))
             (surface (● material metalness)
                      (● material roughness)
                      turn
                      (● texture picture)
                      (● region x)
                      (● region y)
                      (● region width)
                      (● region height)
                      (● texture frames)
                      (● texture period))))
          ((None)
           (surface (● material metalness)
                    (● material roughness)
                    turn
                    -1
                    0
                    0
                    0
                    0
                    1
                    1)))))

    ;; The order matches the meshes in host/browser/renderer.mjs.

    (define (mesh-index (mesh Mesh)) (→ I32)
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

    (define (render-hud (panels (List Panel))) (→ Unit) (! screen)
      (hud-begin)
      (for-each render-panel panels)
      (hud-end))

    ;; Places and corners match host/browser/hud.mjs.

    (define (render-panel (panel Panel)) (→ Unit) (! screen)
      (match (● panel place)
        ((At corner column) (panel-begin 0 (corner-index corner) column 0))
        ((Dialog dismiss) (panel-begin 1 0 0 dismiss))
        ((Banner) (panel-begin 2 0 0 0)))
      (render-field 0 (● panel key))
      (for-each render-widget (● panel widgets)))

    (define (corner-index (corner Corner)) (→ I32)
      (match corner
        ((TopLeft) 0)
        ((TopRight) 1)
        ((BottomLeft) 2)
        ((BottomRight) 3)))

    ;; A widget's kind and numbers, then its strings, each named by a field:
    ;; 0 key, 1 icon, 2 help, 3 badge, 4 text, 5 caption, 6 url, then each
    ;; span of a text, 7 normal or 8 strong. Kinds, tones and controls match
    ;; host/browser/hud.mjs, and fields host/browser/host.mjs.

    (define (render-widget (widget Widget)) (→ Unit) (! screen)
      (match widget
        ((Label face text)
         (widget-begin 0 (tone-index (● face tone)) 0 0 0 0.0)
         (render-look face)
         (render-field 4 text))
        ((Button face text caption action argument control ring)
         (widget-begin 1 (tone-index (● face tone)) action argument (control-index control) ring)
         (render-look face) (render-field 4 text) (render-field 5 caption))
        ((Dial face text fraction)
         (widget-begin 2 (tone-index (● face tone)) 0 0 0 fraction)
         (render-look face)
         (render-field 4 text))
        ((Link face text url)
         (widget-begin 3 (tone-index (● face tone)) 0 0 0 0.0)
         (render-look face)
         (render-field 4 text)
         (render-field 6 url))
        ((Text face spans)
         (widget-begin 4 (tone-index (● face tone)) 0 0 0 0.0)
         (render-look face)
         (for-each render-span spans))
        ((Image face picture region scale)
         (widget-begin 5 (tone-index (● face tone)) 0 0 0 0.0)
         (widget-image picture
                       (● region x)
                       (● region y)
                       (● region width)
                       (● region height)
                       scale)
         (render-look face))))

    (define (render-span (span Span)) (→ Unit) (! screen)
      (match span
        ((Normal words) (render-field 7 words))
        ((Strong words) (render-field 8 words))))

    (define (render-look (face Look)) (→ Unit) (! screen)
      (render-field 0 (● face key))
      (render-field 1 (● face icon))
      (render-field 2 (● face help))
      (render-field 3 (● face badge)))

    (define (tone-index (tone Tone)) (→ I32)
      (match tone
        ((Plain) 0)
        ((Good) 1)
        ((Warning) 2)
        ((Danger) 3)
        ((Muted) 4)
        ((Suggested) 5)))

    (define (control-index (control Control)) (→ I32)
      (match control
        ((Enabled) 0)
        ((Disabled) 1)
        ((Selected) 2)))

    ;; Empty strings are not sent.

    (define (render-field (which I32) (text String)) (→ Unit) (! screen)
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

    (define (pointer-ray (view Camera) (x I32) (y I32) (width I32) (height I32)) (→ Ray)
      (let* ((eye (● view eye)) (forward (normalize (subtract (● view target) eye)))
             (axes (screen-axes view)) (right (● axes first)) (up (● axes second))
             (aspect (/ (i32->f32 width) (i32->f32 (max height 1))))
             (px (- (* 2.0 (/ (+ (i32->f32 x) 0.5) (i32->f32 (max width 1)))) 1.0))
             (py (- 1.0 (* 2.0 (/ (+ (i32->f32 y) 0.5) (i32->f32 (max height 1)))))))
        (match (● view projection)
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

    (define (screen-axes (view Camera)) (→ (Pair Vec3 Vec3))
      (let* ((forward (normalize (subtract (● view target) (● view eye))))
             (sky (if (> (abs (● forward y)) 0.999) (Vec3 0.0 0.0 -1.0) (Vec3 0.0 1.0 0.0)))
             (right (normalize (cross forward sky))))
        (Pair right (cross right forward))))

    ;; Where the ray through pixel (x, y) meets the ground plane y = 0.

    (define (ground-point (view Camera) (x I32) (y I32) (width I32) (height I32)) (→ (Option Vec3))
      (let* ((ray (pointer-ray view x y width height))
             (origin (● ray origin))
             (direction (● ray direction)))
        (if (>= (● direction y) 0.0)
            (None)
            (Some (add origin (scale direction (/ (negate (● origin y)) (● direction y))))))))

    (define (add (a Vec3) (b Vec3)) (→ Vec3)
      (Vec3 (+ (● a x) (● b x)) (+ (● a y) (● b y)) (+ (● a z) (● b z))))

    (define (subtract (a Vec3) (b Vec3)) (→ Vec3)
      (Vec3 (- (● a x) (● b x)) (- (● a y) (● b y)) (- (● a z) (● b z))))

    (define (scale (v Vec3) (k F32)) (→ Vec3)
      (Vec3 (* (● v x) k) (* (● v y) k) (* (● v z) k)))

    (define (cross (a Vec3) (b Vec3)) (→ Vec3)
      (Vec3 (- (* (● a y) (● b z)) (* (● a z) (● b y)))
            (- (* (● a z) (● b x)) (* (● a x) (● b z)))
            (- (* (● a x) (● b y)) (* (● a y) (● b x)))))

    (define (normalize (v Vec3)) (→ Vec3)
      (scale v
             (/ 1.0
                (sqrt (+ (* (● v x) (● v x))
                         (+ (* (● v y) (● v y)) (* (● v z) (● v z))))))))

    ;; ---- Application events ----

    ;; Frame already names the drawing data above; FrameEvent names a tick.
    (enum Event
      (FrameEvent ((elapsed I32)))
      (InputEvent ((input Input)))
      (Hidden)
      (SaveRequested)
      (Reload))

    (define (next-event) (→ Event) (! events tasks)
      (match (poll-event)
        (0 (wait-event) (next-event))
        (11 (FrameEvent (event-field 0)))
        (12 (Hidden))
        (13 (Reload))
        (16 (SaveRequested))
        (kind (InputEvent (decode-input kind
                                        (event-field 0)
                                        (event-field 1)
                                        (event-field 2)
                                        (event-field 3))))))

    ;; ---- Scene applications ----

    (typeclass (Scene S)
      (declare (scene-initialize (width I32) (height I32) (seed I32)) (→ S))
      (declare (scene-update (state S) (input Input)) (→ S))
      (declare (scene-view (value S)) (→ Frame))
      (declare (scene-hud (value S)) (→ (List Panel)))
      (declare (scene-save (value S)) (→ Bytes))
      (declare (scene-restore (bytes Bytes)) (→ S)))

    ;; This adapter supplies Application through ordinary instance evidence.
    ;; A project's selected type may be an alias for (SceneApplication Game).
    (struct (SceneApplication S)
      ())

    (class-instance (Application (! mut screen events storage tasks page) (SceneApplication S))
                    (⊨ (Scene S) (PageState S) (Copy S) (Drop (!) S))
                    (define start
                      (lambda (entry)
                        (run-page (lambda () (initial-scene entry)) scene-save scene-restore
                                  (lambda (state save) (scene-loop save state 0))))))

    ;; The witness selects the state type before initialization; subsequent
    ;; calls select their Scene evidence from the state itself.

    (define (initial-scene (entry (Entry (SceneApplication S))))
      (→ S)
      (! events)
      (∀ (S))
      (⊨ (Scene S))
      (scene-initialize (random-seed) (canvas-width) (canvas-height)))

    ;; Only successful events publish their resulting state. A frame owns
    ;; drawing and HUD throttling; an input owns its HUD. Save events share
    ;; the same queue, independently of display frames.

    (define (scene-loop (save (Fn S → Unit ! events storage tasks)) (state S) (since-hud I32))
      (→ Unit)
      (! mut screen events storage tasks page)
      (∀ (S))
      (⊨ (Scene S) (PageState S) (Copy S) (Drop (!) S))
      (match (next-event)
        ((FrameEvent elapsed)
         (let* ((next (scene-update state (Elapsed elapsed))) (frame (scene-view next))
                (hud-time (+ since-hud elapsed))
                (show-hud? (>= hud-time 100)) (widgets (if show-hud? (scene-hud next) (Nil))))
           (render frame)
           (when show-hud? (render-hud widgets))
           (commit-page next)
           (report-ready)
           (scene-loop save next (if show-hud? 0 hud-time))))
        ((InputEvent input)
         (let* ((next (scene-update state input)) (widgets (scene-hud next)))
           (render-hud widgets)
           (commit-page next)
           (scene-loop save next 0)))
        ((Hidden) (save state) (scene-loop save state since-hud))
        ((SaveRequested) (save state) (scene-loop save state since-hud))
        ((Reload) (save state) (unit))))

    ))
