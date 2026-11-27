;; Drawing Hearsay with the graphics libraries: each frame composes the
;; pictures the screen needs into an atlas, clears the canvas to the
;; backdrop and draws the screen's quads, all unlit, in order. The plain
;; shapes are pictures too, white texels and a hexagon drawn here, so one
;; run of quads draws a whole screen. After the frame, one portrait a frame
;; is read back for the HUD.
(define-library (apps hearsay drawing)
  (export
   Drawing
   start-drawing
   draw-quads-frame
   drawing-url
   white
   hexagon
   tinted)
  (import
   (snail core base)
   (snail core io)
   (snail core table)
   (snail shell task)
   (snail shell png)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics atlas)
   (snail shell graphics quad)
   (snail shell graphics forward frame)
   (only (snail shell graphics raster) Plane release-plane)
   (snail shell graphics compositor)
   (only (lpc layout) face-region))
  (begin

    ;; ---- State ----

    ;; What drawing keeps between frames: the atlas and the quads drawn
    ;; from it, made on the first frame, once the device answers; and each
    ;; portrait read back, by picture key, with the version it shows.
    (record Drawing
      ((drawn (Option Drawn))
       (portraits (Table (Pair I32 String)))))

    (record Drawn
      ((atlas Atlas)
       (quads Quads)
       (output Plane)
       (compositor Compositor)
       (width I32)
       (height I32)))

    (define (start-drawing) (→ Drawing) (new Drawing (drawn (None)) (portraits (empty-table))))

    ;; One page holds the shapes and eighteen walking pictures.
    (define (drawn-of (gpu Gpu) (drawing Drawing)) (→ Drawn)
      (match (● drawing drawn)
        ((Some drawn) drawn)
        ((None)
         (let* ((format (● ((● gpu request-device)) format))
                (atlas (make-atlas gpu "hearsay" 2048 2)))
           (new Drawn
             (atlas atlas)
             (quads (make-quads gpu "hearsay" (Rgba8Unorm) (● atlas texture)))
             (output (display-plane gpu 1 1))
             (compositor (make-compositor gpu format))
             (width 1)
             (height 1))))))

    (define (fit-output! (gpu Gpu) (drawn Drawn) (image Image)) (→ Unit)
      (let ((w (● image width)) (h (● image height)))
        (unless (and (= w (● drawn width)) (= h (● drawn height)))
          (release-plane gpu (● drawn output))
          (set! (● drawn output) (display-plane gpu w h))
          (set! (● drawn width) w) (set! (● drawn height) h))))

    ;; The portrait of picture `key`, or "" until it is read back.
    (define (drawing-url (drawing Drawing) (key I32)) (→ String)
      (match (table-ref (● drawing portraits) (show key))
        ((Some portrait) (● portrait second))
        ((None) "")))

    ;; ---- Shapes ----

    ;; White texels, and a hexagon with a point up, as large as its cell.
    (define white (→ I32) 1)
    (define hexagon (→ I32) 2)

    (define (shape (key I32) (size I32) (inside? (Fn F64 F64 → Bool))) (→ Picture)
      (new Picture
        (key key)
        (version 1)
        (width size)
        (height size)
        (layers (lambda ()
                  (list (new Layer
                          (source (new Source
                                    (key key)
                                    (bytes (lambda () (rgba->png size size (mask size inside?))))))
                          (from (new Rect (x 0) (y 0) (width size) (height size)))
                          (x 0)
                          (y 0)
                          (swaps (Nil))))))))

    ;; White where `inside?` holds of the texel's center, in units of the
    ;; cell's half width from its middle; clear elsewhere.
    (define (mask (size I32) (inside? (Fn F64 F64 → Bool))) (→ Bytes)
      (let ((half (/ (i32->f64 size) 2.0)))
        (array-generate (* 4 (i32->i64 (* size size)))
                        (lambda (index)
                          (let* ((texel (quotient index 4))
                                 (x (/ (- (+ (i64->f64 (remainder texel (i32->i64 size))) 0.5) half)
                                       half))
                                 (y (/ (- (+ (i64->f64 (quotient texel (i32->i64 size))) 0.5) half)
                                       half)))
                            (if (inside? x y) (i32->u8 255) (i32->u8 0)))))))

    ;; A regular hexagon whose points touch the cell's top and bottom.
    (define (in-hexagon? (x F64) (y F64)) (→ Bool)
      (let ((across (abs x)) (up (abs y)))
        (and (<= across 0.8660254) (<= (+ up (* across 0.5773503)) 1.0))))

    (define shapes
      (→ (List Picture))
      (list (shape white 4 (lambda (x y) #t)) (shape hexagon 64 in-hexagon?)))

    ;; A quad showing all of picture `key`, `color` a 0xRRGGBB, centered at
    ;; (x, y), `width` by `height` world units, turned by `angle`.
    (define (tinted (atlas Atlas)
                    (key I32)
                    (region (Option Rect))
                    (x F32)
                    (y F32)
                    (width F32)
                    (height F32)
                    (angle F32)
                    (color I32))
      (→ (Option Quad))
      (match (atlas-slot atlas key)
        ((Some slot)
         (let ((place (slot-region slot
                                   (match region
                                     ((Some rect) rect)
                                     ((None)
                                      (new Rect
                                        (x 0)
                                        (y 0)
                                        (width (● slot width))
                                        (height (● slot height))))))))
           (Some (new Quad
                   (center (new Vec2f (x x) (y y)))
                   (size (new Vec2f (x width) (y height)))
                   (angle angle)
                   (page (● place first))
                   (region (● place second))
                   (color (new Vec4f
                            (x (channel color 16))
                            (y (channel color 8))
                            (z (channel color 0))
                            (w 1.0)))))))
        ((None) (None))))

    (define (channel (color I32) (shift I32)) (→ F32)
      (/ (i32->f32 (i32-and (i32-shift-right/logical color shift) 255)) 255.0))

    ;; ---- Frames ----

    ;; The pictures composed, the canvas cleared to `background` and the
    ;; quads `quads` makes from the atlas drawn under `view`, at the
    ;; canvas's own pixels; then a portrait the HUD lacks, if any.
    (define (draw-quads-frame (gpu Gpu) (drawing Drawing)
                              (pictures (List Picture))
                              (background I32)
                              (view View2D)
                              (quads (Fn Atlas → (List Quad))))
      (→ Drawing)
      (let* ((drawn (drawn-of gpu drawing))
             (encoder ((● gpu create-command-encoder)))
             (atlas (atlas-pictures gpu (● drawn atlas) encoder (append shapes pictures)))
             ;; Decoding new atlas layers can yield to the browser. Acquire its
             ;; short-lived surface only after every layer has arrived.
             (canvas ((● gpu current-texture)))
             (_ (fit-output! gpu drawn canvas))
             (pass (begin-forward-pass gpu encoder (● drawn output view) (None)
                                       (new Color
                                         (red (f32->f64 (channel background 16)))
                                         (green (f32->f64 (channel background 8)))
                                         (blue (f32->f64 (channel background 0))) (alpha 1.0))
                                       (None)))
             (kept (draw-quads gpu pass
                               (● drawn quads)
                               (View2D-pixels-set view
                                                  (new Vec2f
                                                    (x (i32->f32 (● canvas width)))
                                                    (y (i32->f32 (● canvas height)))))
                               (quads atlas))))
        ((● gpu end-pass) pass)
        (present! gpu (● drawn compositor) encoder (● drawn output view) canvas)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (portrait-read gpu (new Drawing
                             (drawn (Some (Drawn-quads-set (Drawn-atlas-set drawn atlas) kept)))
                             (portraits (● drawing portraits)))
                       atlas
                       pictures)))

    ;; The first picture whose portrait is missing or shows another version.
    (define (portrait-read (gpu Gpu) (drawing Drawing) (atlas Atlas) (pictures (List Picture)))
      (→ Drawing)
      (match (find (lambda (picture) (not (portrayed? drawing picture))) pictures)
        ((Some picture)
         (Drawing-portraits-set drawing
                                (table-set (● drawing portraits)
                                           (show (● picture key))
                                           (new Pair
                                             (first (● picture version))
                                             (second (atlas-url gpu atlas
                                                                (● picture key)
                                                                face-region))))))
        ((None) drawing)))

    (define (portrayed? (drawing Drawing) (picture Picture)) (→ Bool)
      (match (table-ref (● drawing portraits) (show (● picture key)))
        ((Some portrait) (= (● portrait first) (● picture version)))
        ((None) #f)))

    ))
