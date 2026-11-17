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
       (quads Quads)))

    (define (start-drawing) (→ Drawing) (new Drawing (drawn (None)) (portraits (empty-table))))

    ;; One page holds the shapes and eighteen walking pictures.
    (define (drawn-of (drawing Drawing)) (→ Drawn) (! gpu tasks)
      (match (● drawing drawn)
        ((Some drawn) drawn)
        ((None)
         (let* ((format (● (request-device) format)) (atlas (make-atlas "hearsay" 2048 2)))
           (new Drawn (atlas atlas) (quads (make-quads "hearsay" format (● atlas texture))))))))

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
    (define (draw-quads-frame (drawing Drawing)
                              (pictures (List Picture))
                              (background I32)
                              (view View2D)
                              (quads (Fn Atlas → (List Quad))))
      (→ Drawing)
      (! gpu tasks)
      (let* ((drawn (drawn-of drawing))
             (encoder (create-command-encoder))
             (atlas (atlas-pictures (● drawn atlas) encoder (append shapes pictures)))
             (canvas (current-texture))
             (pass (begin-render-pass encoder (canvas-pass canvas background)))
             (kept (draw-quads pass
                               (● drawn quads)
                               (View2D-pixels-set view
                                                  (new Vec2f
                                                    (x (i32->f32 (● canvas width)))
                                                    (y (i32->f32 (● canvas height)))))
                               (quads atlas))))
        (end-pass pass)
        (submit (list (finish encoder)))
        (portrait-read (new Drawing
                         (drawn (Some (new Drawn (atlas atlas) (quads kept))))
                         (portraits (● drawing portraits)))
                       atlas
                       pictures)))

    (define (canvas-pass (canvas Image) (background I32)) (→ RenderPassDescriptor) (! gpu)
      (new RenderPassDescriptor
        (colors (list (Some (new ColorAttachment
                              (view (view-of (● canvas texture) 1))
                              (load (Clear (new Color
                                             (red (f32->f64 (channel background 16)))
                                             (green (f32->f64 (channel background 8)))
                                             (blue (f32->f64 (channel background 0)))
                                             (alpha 1.0))))
                              (store #t)))))
        (depth (None))))

    ;; The first picture whose portrait is missing or shows another version.
    (define (portrait-read (drawing Drawing) (atlas Atlas) (pictures (List Picture)))
      (→ Drawing)
      (! gpu tasks)
      (match (find (lambda (picture) (not (portrayed? drawing picture))) pictures)
        ((Some picture)
         (Drawing-portraits-set drawing
                                (table-set (● drawing portraits)
                                           (show (● picture key))
                                           (new Pair
                                             (first (● picture version))
                                             (second (atlas-url atlas
                                                                (● picture key)
                                                                face-region))))))
        ((None) drawing)))

    (define (portrayed? (drawing Drawing) (picture Picture)) (→ Bool)
      (match (table-ref (● drawing portraits) (show (● picture key)))
        ((Some portrait) (= (● portrait first) (● picture version)))
        ((None) #f)))

    ))
