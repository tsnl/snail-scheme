;; Texture-array pages of pictures in padded slots. A picture is layers
;; of regions of encoded images, drawn in order over transparency, each
;; with its colors swapped as listed: art drawn in one palette is
;; recolored, as LPC skin ramps are. The host decodes the images
;; (`decode-image`), once each, and the atlas keeps them;
;; composing a picture is a render pass into its slot (atlas.wgsl.scm).
;; The Atlas value holds its pages, its pipeline and its decoded sources,
;; and records what each slot holds; the application keeps it, as it keeps
;; the rest of its state:
;;
;;   (let ((atlas (atlas-pictures atlas encoder pictures)))   ; compose the new ones
;;     (draw-quads pass quads view quad-list)                 ; quads over (● atlas texture)
;;     ...)
;;
;; A slot keeps a transparent texel around its picture, so nearest
;; sampling at its edge never reads a neighbour. Slots are placed on
;; shelves, left to right and down a page; when a picture no longer fits,
;; every page is cleared and the pictures asked for are placed again. A
;; call composes one picture, so a frame decodes one picture's sources.
(define-library (snail shell graphics atlas)
  (export
   Source
   Rect
   Layer
   Picture
   Slot
   Atlas
   make-atlas
   atlas-pictures
   atlas-slot
   slot-region
   atlas-url)
  (import
   (snail core base)
   (snail core table)
   (snail shell png)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics shaders))
  (begin

    ;; ---- Pictures ----

    ;; An encoded image, read only when a picture that needs it is
    ;; composed.
    (record Source
      ((key I32)
       (bytes (Fn → Bytes))))

    (record Rect
      ((x I32)
       (y I32)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    ;; The texels of `source` within `from`, with their top left at (x, y)
    ;; of the picture; each swap replaces the 0xRRGGBB color first in the
    ;; pair with the second, keeping alpha.
    (record Layer
      ((source Source)
       (from Rect)
       (x I32)
       (y I32)
       (swaps (List (Pair I32 I32)))))

    ;; Composed once per version: `layers` runs only for a version the
    ;; atlas lacks.
    (record Picture
      ((key I32)
       (version I32)
       (width I32)
       (height I32)
       (layers (Fn → (List Layer)))))

    ;; ---- Slots ----

    ;; Where a version of a picture lies: a page and its texels there.
    (record Slot
      ((page I32)
       (x I32)
       (y I32)
       (width I32)
       (height I32)
       (version I32)))

    ;; `size` texels square pages, `pages` of them, in `texture`. The
    ;; packer's cursor is on `page` at (x, y), and the shelf it fills is
    ;; `row` texels tall. `sources` holds each source decoded, by its key.
    (record Atlas
      ((name String)
       (size I32)
       (pages I32)
       (texture GpuTexture)
       (pipeline GpuRenderPipeline)
       (sources (Table GpuTextureView))
       (page I32)
       (x I32)
       (y I32)
       (row I32)
       (slots (Table Slot))))

    (define (make-atlas (gpu Gpu) (name String) (size I32) (pages I32)) (→ Atlas)
      (new Atlas
        (name name)
        (size size)
        (pages pages)
        (texture ((● gpu create-texture) (new TextureDescriptor
                                           (label (string-append "atlas/" name))
                                           (width size)
                                           (height size)
                                           (layers pages)
                                           (mips 1)
                                           (format (Rgba8Unorm))
                                           (usage (list (TextureBinding)
                                                        (TextureCopySrc)
                                                        (TextureCopyDst)
                                                        (RenderAttachment))))))
        (pipeline (compose-pipeline gpu))
        (sources (empty-table))
        (page 0)
        (x 0)
        (y 0)
        (row 0)
        (slots (empty-table))))

    ;; The pages cleared of pictures, keeping the objects.
    (define (emptied (atlas Atlas)) (→ Atlas)
      (Atlas-slots-set (Atlas-row-set (Atlas-y-set (Atlas-x-set (Atlas-page-set atlas 0) 0) 0) 0)
                       (empty-table)))

    (define (atlas-slot (atlas Atlas) (key I32)) (→ (Option Slot))
      (table-ref (● atlas slots) (show key)))

    ;; A region of a slot as a quad's page and region.

    (define (slot-region (slot Slot) (region Rect)) (→ (Pair I32 Vec4f))
      (new Pair
        (first (● slot page))
        (second (new Vec4f
                  (x (i32->f32 (+ (● slot x) (● region x))))
                  (y (i32->f32 (+ (● slot y) (● region y))))
                  (z (i32->f32 (● region width)))
                  (w (i32->f32 (● region height)))))))

    ;; The next slot for a picture, a texel in from its padded corner, or
    ;; None when the pages are full.

    (define (placed (atlas Atlas) (picture Picture)) (→ (Option (Pair Slot Atlas)))
      (let ((width (+ (● picture width) 2)) (height (+ (● picture height) 2)) (size (● atlas size)))
        (cond
         ((or (> width size) (> height size)) (None))
         ((> (+ (● atlas x) width) size)
          (placed
           (Atlas-row-set (Atlas-y-set (Atlas-x-set atlas 0) (+ (● atlas y) (● atlas row))) 0)
           picture))
         ((> (+ (● atlas y) height) size)
          (if (>= (+ (● atlas page) 1) (● atlas pages))
              (None)
              (placed (Atlas-row-set
                       (Atlas-y-set (Atlas-x-set (Atlas-page-set atlas (+ (● atlas page) 1)) 0) 0)
                       0)
                      picture)))
         (else (Some (new Pair
                       (first (slot-at atlas picture))
                       (second (advanced atlas picture width height))))))))

    (define (slot-at (atlas Atlas) (picture Picture)) (→ Slot)
      (new Slot
        (page (● atlas page))
        (x (+ (● atlas x) 1))
        (y (+ (● atlas y) 1))
        (width (● picture width))
        (height (● picture height))
        (version (● picture version))))

    (define (advanced (atlas Atlas) (picture Picture) (width I32) (height I32)) (→ Atlas)
      (Atlas-slots-set
       (Atlas-row-set (Atlas-x-set atlas (+ (● atlas x) width)) (max (● atlas row) height))
       (table-set (● atlas slots) (show (● picture key)) (slot-at atlas picture))))

    ;; ---- Composing ----

    ;; The first picture the atlas lacks at its version, composed in a pass
    ;; of `encoder`, which the caller submits: a frame decodes only one
    ;; picture's sources, and the rest follow, one a call. When it does not
    ;; fit, the pages are cleared, and the pictures asked for are composed
    ;; again in later calls.

    (define (atlas-pictures (gpu Gpu)
                            (atlas Atlas)
                            (encoder GpuCommandEncoder)
                            (pictures (List Picture)))
      (→ Atlas)
      (match (find (lambda (picture) (not (composed? atlas picture))) pictures)
        ((None) atlas)
        ((Some picture)
         (match (placed atlas picture)
           ((Some next) (compose gpu encoder (● next second) picture #f))
           ((None)
            (match (placed (emptied atlas) picture)
              ((Some next) (compose gpu encoder (● next second) picture #t))
              ((None)
               (panic (string-append "atlas: a picture is larger than the pages of atlas "
                                     (● atlas name))))))))))

    (define (composed? (atlas Atlas) (picture Picture)) (→ Bool)
      (match (atlas-slot atlas (● picture key))
        ((Some slot) (= (● slot version) (● picture version)))
        ((None) #f)))

    ;; One piece for each layer: the page's clip-space rectangle it covers,
    ;; within its picture, the offset from a page pixel to its source
    ;; texel, and its run of the swap table.
    (record Piece
      ((clip Vec4f)
       (offset Vec2f)
       (run Vec2i))
      (deriving Pod))

    ;; A layer placed: its piece, its source, and its swaps.
    (record Placed
      ((page I32)
       (piece Piece)
       (source Source)
       (swaps (List (Pair I32 I32)))))

    (define piece-shape (→ (Shape Piece)) (shape))

    (define swap-shape (→ (Shape Vec2i)) (shape))

    ;; Each page a pass: cleared first when `clear?`, then each layer over
    ;; what is there, its source bound with the swap table. The atlas
    ;; answered keeps the sources decoded; the buffers go at the submit.

    (define (compose (gpu Gpu)
                     (encoder GpuCommandEncoder)
                     (atlas Atlas)
                     (picture Picture)
                     (clear? Bool))
      (→ Atlas)
      (let* ((layers (laid atlas (list picture)))
             (atlas (decoded gpu atlas layers))
             (pieces (numbered-runs layers 0))
             (swaps (swap-buffer gpu atlas layers))
             (instances (piece-buffer gpu atlas pieces)))
        (for-each (lambda (page)
                    (let ((on-page (filter (lambda (indexed) (= (● indexed second page) page))
                                           (indexed pieces))))
                      (when (or clear? (not (null? on-page)))
                        (page-pass gpu encoder atlas page swaps instances on-page clear?))))
                  (map i64->i32 (iota (i32->i64 (● atlas pages)))))
        ((● gpu destroy) (BufferObject swaps))
        ((● gpu destroy) (BufferObject instances))
        atlas))

    ;; The atlas with each layer's source decoded.

    (define (decoded (gpu Gpu) (atlas Atlas) (layers (List Placed))) (→ Atlas)
      (fold-left (lambda (atlas layer)
                   (let ((key (show (● layer source key))))
                     (if (table-contains? (● atlas sources) key)
                         atlas
                         (Atlas-sources-set atlas
                                            (table-set (● atlas sources)
                                                       key
                                                       (decoded-view gpu layer))))))
                 atlas
                 layers))

    (define (decoded-view (gpu Gpu) (layer Placed)) (→ GpuTextureView)
      (match ((● gpu decode-image) ((● layer source bytes)))
        ((Some image) (view-of gpu (● image texture) 1))
        ((None) (panic "atlas: a source is no image the host decodes"))))

    (define (laid (atlas Atlas) (pictures (List Picture))) (→ (List Placed))
      (concatenate (map (lambda (picture)
                          (match (atlas-slot atlas (● picture key))
                            ((Some slot)
                             (map (lambda (layer) (place-layer atlas slot picture layer))
                                  ((● picture layers))))
                            ((None) (Nil))))
                        pictures)))

    ;; A layer reaches no further than its picture.

    (define (place-layer (atlas Atlas) (slot Slot) (picture Picture) (layer Layer)) (→ Placed)
      (let* ((from (● layer from))
             (left (+ (● slot x) (● layer x)))
             (top (+ (● slot y) (● layer y)))
             (width (max 0 (min (● from width) (- (● picture width) (● layer x)))))
             (height (max 0 (min (● from height) (- (● picture height) (● layer y)))))
             (size (i32->f32 (● atlas size)))
             (across (lambda (texel) (- (* 2.0 (/ (i32->f32 texel) size)) 1.0)))
             (down (lambda (texel) (- 1.0 (* 2.0 (/ (i32->f32 texel) size))))))
        (new Placed
          (page (● slot page))
          (piece (new Piece
                   (clip (new Vec4f
                           (x (across left))
                           (y (down top))
                           (z (across (+ left width)))
                           (w (down (+ top height)))))
                   (offset (new Vec2f
                             (x (i32->f32 (- (● from x) left)))
                             (y (i32->f32 (- (● from y) top)))))
                   (run (new Vec2i (x 0) (y 0)))))
          (source (● layer source))
          (swaps (● layer swaps)))))

    ;; Each layer's swaps follow the last's in the table.

    (define (numbered-runs (layers (List Placed)) (start I32)) (→ (List Placed))
      (match layers
        ((Nil) (Nil))
        ((Cons layer rest)
         (let ((count (i64->i32 (length (● layer swaps)))))
           (Cons
            (Placed-piece-set layer (Piece-run-set (● layer piece) (new Vec2i (x start) (y count))))
            (numbered-runs rest (+ start count)))))))

    (define (indexed (layers (List Placed))) (→ (List (Pair I32 Placed)))
      (map-indexed (lambda (index layer) (new Pair (first (i64->i32 index)) (second layer)))
                   layers))

    (define (page-pass (gpu Gpu) (encoder GpuCommandEncoder)
                       (atlas Atlas)
                       (page I32)
                       (swaps GpuBuffer)
                       (instances GpuBuffer)
                       (layers (List (Pair I32 Placed)))
                       (clear? Bool))
      (→ Unit)
      (let* ((target (layer-view gpu (● atlas texture) page))
             (pass ((● gpu begin-render-pass) encoder
                    (new RenderPassDescriptor
                      (colors (list (Some (new ColorAttachment
                                            (view target)
                                            (load (if clear?
                                                      (Clear (new Color
                                                               (red 0.0)
                                                               (green 0.0)
                                                               (blue 0.0)
                                                               (alpha 0.0)))
                                                      (Keep)))
                                            (store #t)))))
                      (depth (None))))))
        ((● gpu set-pipeline) pass (● atlas pipeline))
        ((● gpu set-vertex-buffer) pass 0 instances 0)
        (for-each (lambda (indexed) (draw-layer gpu pass atlas swaps indexed)) layers)
        ((● gpu end-pass) pass)
        ((● gpu destroy) (ViewObject target))))

    ;; A layer's draw, with its source and the swaps bound in a group that
    ;; goes once set: the pass holds what it binds.

    (define (draw-layer (gpu Gpu) (pass GpuRenderPass)
                        (atlas Atlas)
                        (swaps GpuBuffer)
                        (indexed (Pair I32 Placed)))
      (→ Unit)
      (let ((group ((● gpu create-bind-group)
                    (new BindGroupDescriptor
                      (label (string-append "atlas/" (● atlas name) "/source"))
                      (pipeline (RenderPipeline (● atlas pipeline)))
                      (group 0)
                      (entries (list (TextureEntry 0
                                                   (source-view atlas
                                                                (● indexed
                                                                   second
                                                                   source)))
                                     (BufferEntry 1 swaps 0 0)))))))
        ((● gpu set-bind-group) pass 0 group)
        ((● gpu draw) pass 4 1 0 (● indexed first))
        ((● gpu destroy) (BindGroupObject group))))

    (define (source-view (atlas Atlas) (source Source)) (→ GpuTextureView)
      (match (table-ref (● atlas sources) (show (● source key)))
        ((Some view) view)
        ((None) (panic "atlas: a source was not decoded"))))

    (define (compose-pipeline (gpu Gpu)) (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label "atlas/compose")
         (module ((● gpu create-shader-module)
                  (new ShaderModuleDescriptor
                    (label "atlas")
                    (code atlas-shader))))
         (vertex-entry "piece_vertex")
         (buffers (list (vertex-layout piece-shape (PerInstance) 0)))
         (fragment (Some (new FragmentState
                           (entry "piece_fragment")
                           (targets
                            (list
                             (Some (new ColorTarget
                                     (format (Rgba8Unorm))
                                     (blend (Some over)))))))))
         (topology (TriangleStrip))
         (cull (CullNone))
         (depth (None)))))

    ;; Storage needs a binding of at least one entry.

    (define (swap-buffer (gpu Gpu) (atlas Atlas) (layers (List Placed))) (→ GpuBuffer)
      (let ((pairs (map (lambda (swap) (new Vec2i (x (● swap first)) (y (● swap second))))
                        (concatenate (map (lambda (layer) (● layer swaps)) layers)))))
        (filled-buffer gpu atlas
                       "swaps"
                       (pack swap-shape (if (null? pairs) (list (new Vec2i (x 0) (y 0))) pairs))
                       (Storage))))

    (define (piece-buffer (gpu Gpu) (atlas Atlas) (layers (List Placed))) (→ GpuBuffer)
      (filled-buffer gpu atlas
                     "pieces"
                     (pack piece-shape (map (lambda (layer) (● layer piece)) layers))
                     (Vertex)))

    (define (filled-buffer (gpu Gpu) (atlas Atlas) (part String) (bytes Bytes) (usage BufferUsage))
      (→ GpuBuffer)
      (let ((buffer ((● gpu create-buffer) (new BufferDescriptor
                                             (label
                                              (string-append "atlas/" (● atlas name) "/" part))
                                             (size (i64->i32 (array-length bytes)))
                                             (usage (list usage (CopyDst)))))))
        ((● gpu write-buffer) buffer 0 bytes)
        buffer))

    ;; ---- Reading back ----

    ;; A region of a picture as a PNG data URL, for an `img`. It submits
    ;; its own copy and waits for it, so it ends the frame: call it after
    ;; the frame's own submit.

    (define (atlas-url (gpu Gpu) (atlas Atlas) (key I32) (region Rect)) (→ String)
      (match (atlas-slot atlas key)
        ((None) "")
        ((Some slot)
         (let* ((width (● region width))
                (height (● region height))
                (row (* 256 (quotient (+ (* 4 width) 255) 256)))
                (buffer ((● gpu create-buffer) (new BufferDescriptor
                                                 (label
                                                  (string-append "atlas/"
                                                                 (● atlas name)
                                                                 "/readback"))
                                                 (size (* row height))
                                                 (usage (list (MapRead) (CopyDst))))))
                (encoder ((● gpu create-command-encoder))))
           ((● gpu copy-texture-to-buffer) encoder
            (new TextureCopy
              (texture (● atlas texture))
              (mip 0)
              (x (+ (● slot x) (● region x)))
              (y (+ (● slot y) (● region y)))
              (layer (● slot page)))
            buffer
            0
            row
            width
            height)
           ((● gpu submit) (list ((● gpu finish) encoder)))
           (let ((bytes ((● gpu read-buffer) buffer 0 (* row height))))
             ((● gpu destroy) (BufferObject buffer))
             (png-data-url (rgba->png width height (unpadded bytes row width height))))))))

    (define (unpadded (bytes Bytes) (row I32) (width I32) (height I32)) (→ Bytes)
      (let ((line (* 4 (i32->i64 width))))
        (array-generate (* line (i32->i64 height))
                        (lambda (index)
                          (array-ref bytes
                                     (+ (* (quotient index line) (i32->i64 row))
                                        (remainder index line)))))))

    ))
