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
;; A script runs one with `run-scene`, given a SceneHandler of the six.
;; Its loop draws each event's state; (snail shell page) owns boot,
;; restore and durable saves for both browser engines.
;; Time is input, so the state decides how its simulation advances. The
;; host draws a Frame through `screen`; the HUD is a tree in the page's
;; document, changed through `dom` where it differs after each input
;; (after time, at most ten times a second). A durable save may be
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
   provide-screen
   render
   Ray
   pointer-ray
   screen-axes
   ground-point
   Event
   FrameEvent
   InputEvent
   HudEvent
   Hidden
   SaveRequested
   events
   next-event
   storage
   load-save
   store-save
   SceneHandler
   run-scene)
  (import
   (except (snail core base) instance)
   (only (snail core forms) host)
   (prefix (snail runtime browser screen) host-)
   (snail shell task)
   (snail shell math)
   (snail shell page)
   (only (snail core table) table-ref table-contains?)
   (only (snail shell dom) dom document-root no-event Allow)
   (only (snail shell dom page) with-page-dom)
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

    ;; What the host draws: a camera, the light, a 0xRRGGBB background,
    ;; how far from 0 to 1 every item has moved from where it was toward
    ;; where it is, the batches of items, and the pictures the batches and
    ;; the HUD may use as textures.
    (record Frame
      ((camera Camera)
       (light Light)
       (background I32)
       (motion F32)
       (batches (List Batch))
       (pictures (List Picture))))

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
    (record Rect
      ((x I32)
       (y I32)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    ;; An encoded image file, PNG or anything else the browser decodes. The
    ;; host decodes each key once, so `bytes` runs only when it has not.
    (record Source
      ((key I32)
       (bytes (Fn → Bytes))))

    ;; The pixels of `source` within `from`, drawn with their top left at
    ;; (x, y) of the picture. Each swap replaces the 0xRRGGBB color first in
    ;; the pair with the second, keeping alpha: art drawn in one palette can
    ;; be recolored, as LPC skin ramps are.
    (record Layer
      ((source Source)
       (from Rect)
       (x I32)
       (y I32)
       (swaps (List (Pair I32 I32)))))

    ;; A texture the host composes from layers, drawn in order over
    ;; transparency. Like a batch, it is kept until its version changes, so
    ;; `layers` runs only when the host lacks this version.
    (record Picture
      ((key I32)
       (version I32)
       (width I32)
       (height I32)
       (layers (Fn → (List Layer)))))

    ;; A region of a picture. With more than one frame it is a strip: the
    ;; host shows `frames` regions side by side, starting at `region` and
    ;; stepping right by its width, each for `period` milliseconds.
    (record Texture
      ((picture I32)
       (region Rect)
       (frames I32)
       (period I32)))

    (define (still (picture I32) (region Rect)) (→ Texture)
      (new Texture (picture picture) (region region) (frames 1) (period 1)))

    ;; How a surface reflects light, in the metallic-roughness model. The
    ;; texture times the item's color is the albedo of a dielectric, or the
    ;; specular color of a metal. Transparent texels are not drawn.
    (record Material
      ((texture (Option Texture))
       (metalness F32)
       (roughness F32)))

    ;; Untextured and fully rough, as a matte dielectric.
    (define plain (→ Material) (new Material (texture (None)) (metalness 0.0) (roughness 1.0)))

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
    (record Item
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
      (new Item
        (mesh mesh)
        (position position)
        (scale scale)
        (yaw yaw)
        (color color)
        (glow 0.0)
        (from position)
        (material plain)
        (facing (Fixed))))

    ;; A texture on a quad `width` by `height` world units, its bottom center
    ;; at `position`, standing upright toward the camera: a sprite in a 2.5D
    ;; scene.

    (define (sprite (texture Texture) (position Vec3) (width F32) (height F32)) (→ Item)
      (new Item (mesh (Quad))
           (position position)
           (scale (new Vec3 (x width) (y height) (z 1.0)))
           (yaw 0.0)
           (color (rgb 255 255 255))
           (glow 0.0)
           (from position)
           (material (new Material (texture (Some texture)) (metalness 0.0) (roughness 1.0)))
           (facing (Upright))))

    ;; A texture lying on the ground, `width` by `height` world units, its
    ;; top toward -z and the middle of its bottom edge at `position`: a sprite
    ;; in a 2D scene seen straight down, where -z is the top of the screen.
    ;; It shows the texture's own colors, unlit.

    (define (flat-sprite (texture Texture) (position Vec3) (width F32) (height F32)) (→ Item)
      (let ((center
             (new Vec3
               (x (● position x))
               (y (● position y))
               (z (- (● position z) (/ height 2.0))))))
        (new Item (mesh (Tile))
             (position center)
             (scale (new Vec3 (x width) (y 1.0) (z height)))
             (yaw 0.0)
             (color (rgb 255 255 255))
             (glow 1.0)
             (from center)
             (material (new Material (texture (Some texture)) (metalness 0.0) (roughness 1.0)))
             (facing (Fixed)))))

    ;; Solid batches hide what is behind them. Translucent ones are drawn
    ;; after, over them. A revealed batch shows only within `radius` of a
    ;; point on the ground. Styles cost nothing to change between frames.
    (enum Style
      (Solid)
      (Translucent ((opacity F32)))
      (Revealed ((center Vec3) (radius F32))))

    ;; The host keeps each batch's instances until its version changes, so
    ;; `items` runs only when the host does not already have them.
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

    (record Panel
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
       (picture-url (Fn I32 → String))))

    ;; The page's canvas, through the browser host.
    (define (provide-screen (work (Fn → T ! screen e))) (→ T) (! e) (∀ (T e))
      (handle screen
          ((frame-begin host-frame-begin)
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
           (picture-url host-url))
        (work)))

    ;; A string from the host crosses a scalar at a time.

    (define (host-url (picture I32)) (→ String)
      (string-generate (i32->i64 (host-picture-url picture))
                       (lambda (index)
                         (integer->char (i32->i64 (host-picture-url-scalar (i64->i32 index)))))))

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
      (let* ((bytes ((● source bytes))) (count (array-length bytes))
             (byte (lambda (index) (if (< index count) (u8->i32 (array-ref bytes index)) 0))))
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

    ;; ---- The HUD's document ----

    ;; The HUD as the trees the page's overlay holds: each corner with its
    ;; panels in columns, the banner with its, and the dialogs with theirs
    ;; over a backdrop that presses the last dialog's `dismiss`. The page's
    ;; style lays them out (host/browser/style.css), and an application's
    ;; own colors widgets by their data-key, data-icon, data-tone and
    ;; data-badge. A panel or widget keeps its node while its key and tag
    ;; stay, so hover and focus survive the updates; siblings' keys differ,
    ;; as (snail shell ui) requires. A listener's function makes the input
    ;; its event is.

    (define (hud-html (panels (List Panel))) (→ (List (ui:Html Input))) (! screen)
      (append (map (lambda (corner) (corner-html corner panels))
                   (list "top-left" "top-right" "bottom-left" "bottom-right"))
              (list (ui:Element "div"
                                (list (ui:Attr "class" "banner"))
                                (map panel-html (placed "banner" panels)))
                    (dialogs-html (placed "dialog" panels)))))

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

    (define (corner-html (corner String) (panels (List Panel))) (→ (ui:Html Input)) (! screen)
      (let ((here (placed corner panels)))
        (ui:Element "div"
                    (list (ui:Attr "class" (string-append "corner " corner)))
                    (map (lambda (column)
                           (ui:Element "div"
                                       (list (ui:Keyed (show column)) (ui:Attr "class" "column"))
                                       (map panel-html
                                            (filter (lambda (panel) (= (panel-column panel) column))
                                                    here))))
                         (list-sort < (delete-duplicates = (map panel-column here)))))))

    (define (dialogs-html (dialogs (List Panel))) (→ (ui:Html Input)) (! screen)
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
                          (map panel-html dialogs)))))

    (define (panel-html (panel Panel)) (→ (ui:Html Input)) (! screen)
      (ui:Element "div"
                  (list (ui:Keyed (● panel key))
                        (ui:Attr "class" "panel")
                        (ui:Attr "data-key" (● panel key)))
                  (map widget-html (● panel widgets))))

    ;; ---- Widgets ----

    ;; A widget is an icon the style draws and its text, a button also its
    ;; caption; a text's words are spans, strong in places.

    (define (widget-html (widget Widget)) (→ (ui:Html Input)) (! screen)
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
        ((Image face picture region scale) (image-html face (picture-url picture) region scale))))

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

    ;; An image is a window the size of its region at its scale, over the
    ;; whole picture moved and scaled so the region fills it; the style
    ;; keeps its texels crisp. Until the host has composed the picture, the
    ;; window is empty.

    (define (image-html (face Look) (url String) (region Rect) (scale I32)) (→ (ui:Html Input))
      (ui:Element "div"
                  (list (ui:Keyed (● face key))
                        (ui:Attr "class" "image")
                        (ui:Attr "data-key" (● face key))
                        (ui:Attr "title" (● face help))
                        (ui:Attr "style"
                                 (string-append "width: "
                                                (show (* (● region width) scale))
                                                "px; height: "
                                                (show (* (● region height) scale))
                                                "px; overflow: hidden")))
                  (if (string=? url "") (Nil) (list (picture-html url region scale)))))

    (define (picture-html (url String) (region Rect) (scale I32)) (→ (ui:Html Input))
      (ui:Element "img"
                  (list (ui:Attr "src" url)
                        (ui:Attr "style"
                                 (string-append "width: "
                                                (show (● region width))
                                                "px; height: "
                                                (show (● region height))
                                                "px; object-fit: none; object-position: -"
                                                (show (● region x))
                                                "px -"
                                                (show (● region y))
                                                "px; transform-origin: 0 0; transform: scale("
                                                (show scale)
                                                ")")))
                  (Nil)))

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
    (enum Event
      (FrameEvent ((elapsed I32)))
      (InputEvent ((input Input)))
      (HudEvent ((listener I32)))
      (Hidden)
      (SaveRequested))

    (define (next-event) (→ Event) (! events tasks)
      (match (poll-event)
        (0 (wait-event) (next-event))
        (11 (FrameEvent (event-field 0)))
        (12 (Hidden))
        (14 (HudEvent (event-field 0)))
        (16 (SaveRequested))
        (kind (InputEvent (decode-input kind
                                        (event-field 0)
                                        (event-field 1)
                                        (event-field 2)
                                        (event-field 3))))))

    ;; ---- Running a scene ----

    ;; A scene is a handler, in the style of winit's: a record of the six
    ;; functions over its state, which a script hands to `run-scene` as its
    ;; last statement.

    (record (SceneHandler S)
      ((initialize (Fn I32 I32 I32 → S))
       (update (Fn S Input → S))
       (view (Fn S → Frame))
       (hud (Fn S → (List Panel)))
       (save (Fn S → Bytes))
       (restore (Fn Bytes → S))))

    ;; The page's state, from its save or `initialize` with a seed and the
    ;; canvas's size, then the scene's loop, which never returns, over the
    ;; page's document.

    (define (run-scene (scene (SceneHandler S))) (→ Unit) (! screen events storage tasks) (∀ (S))
      (run-page (lambda ()
                  ((● scene initialize) (random-seed) (canvas-width) (canvas-height)))
                (● scene save)
                (● scene restore)
                (lambda (state save)
                  (with-page-dom
                   (lambda ()
                     (scene-loop scene save state (new Hud (shown (Nil)) (hovered (None))) 0))))))

    ;; Each event's state is drawn: a frame draws the scene and, at most ten
    ;; times a second, the HUD; an input shows its HUD. Saves share the
    ;; same queue, independently of display frames. A HUD listener that
    ;; fired gives its input; one the HUD has since dropped gives none.

    (define (scene-loop (scene (SceneHandler S))
                        (save (Fn S → Unit ! events storage tasks))
                        (state S)
                        (hud Hud)
                        (since-hud I32))
      (→ Unit)
      (! screen dom events storage tasks)
      (∀ (S))
      (match (next-event)
        ((FrameEvent elapsed)
         (let ((next ((● scene update) state (Elapsed elapsed)))
               (show-hud? (>= (+ since-hud elapsed) 100)))
           (render ((● scene view) next))
           (let ((shown (if show-hud?
                            (show-hud scene next hud)
                            (new Pair (first next) (second hud)))))
             (report-ready)
             (scene-loop scene
                         save
                         (● shown first)
                         (● shown second)
                         (if show-hud? 0 (+ since-hud elapsed))))))
        ((InputEvent input) (scene-input scene save state hud input))
        ((HudEvent listener)
         (match (table-ref (ui:listener-table (● hud shown)) (show listener))
           ((Some message)
            (let ((input (message (no-event))))
              (scene-input scene save state (hovering hud listener input) input)))
           ((None) (scene-loop scene save state hud since-hud))))
        ((Hidden) (save state) (scene-loop scene save state hud since-hud))
        ((SaveRequested) (save state) (scene-loop scene save state hud since-hud))))

    (define (scene-input (scene (SceneHandler S))
                         (save (Fn S → Unit ! events storage tasks))
                         (state S)
                         (hud Hud)
                         (input Input))
      (→ Unit)
      (! screen dom events storage tasks)
      (∀ (S))
      (let ((shown (show-hud scene ((● scene update) state input) hud)))
        (scene-loop scene save (● shown first) (● shown second) 0)))

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

    (define (show-hud (scene (SceneHandler S)) (state S) (hud Hud))
      (→ (Pair S Hud))
      (! screen dom)
      (∀ (S))
      (let ((shown (ui:patch-children (document-root)
                                      (● hud shown)
                                      (hud-html ((● scene hud) state)))))
        (if (match (● hud hovered)
              ((Some listener) (not (table-contains? (ui:listener-table shown) (show listener))))
              ((None) #f))
            (show-hud scene
                      ((● scene update) state (Hover 0 0))
                      (new Hud (shown shown) (hovered (None))))
            (new Pair (first state) (second (new Hud (shown shown) (hovered (● hud hovered))))))))

    ))
