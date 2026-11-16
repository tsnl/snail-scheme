;; The page's WebGPU device for the `gpu` effect: `provide-gpu` keeps the
;; books of (snail shell gpu) and runs each operation on the device
;; host/browser/gpu.mjs holds, which knows each object by the id the books
;; gave it. Every handle is checked against the books before the host sees
;; it, so a stale one panics here with what it was.
(define-library (snail shell gpu page)
  (export
   provide-gpu)
  (import
   (snail core base)
   (snail shell utf8)
   (snail shell task)
   (snail shell json)
   (snail shell gpu)
   (prefix (snail runtime browser gpu) host-))
  (begin

    ;; ---- Handling ----

    (define (provide-gpu (work (Fn → T ! gpu e))) (→ T) (! mut e) (∀ (T e))
      (let ((objects (make-objects 0)))
        (handle gpu
            ((request-device (lambda (budget) (requested! objects budget)))
             (create-buffer
              (lambda (descriptor)
                (let ((made (made! objects (buffer-request descriptor))))
                  (buffer-handle (● made first) (● made second)))))
             (write-buffer
              (lambda (buffer offset bytes)
                (host-write-buffer (used objects (● buffer id)) offset bytes)))
             (read-buffer
              (lambda (buffer offset size) (read-bytes (used objects (● buffer id)) offset size)))
             (create-texture
              (lambda (descriptor)
                (let ((made (made! objects (texture-request descriptor))))
                  (texture-handle (● made first) (● made second)))))
             (write-texture
              (lambda (copy bytes-per-row width height bytes)
                (host-write-texture (used objects (● (● copy texture) id))
                                    (● copy mip)
                                    (● copy x)
                                    (● copy y)
                                    (● copy layer)
                                    bytes-per-row
                                    width
                                    height
                                    bytes)))
             (decode-image (lambda (path bytes) (decoded! objects path bytes)))
             (create-sampler
              (lambda (descriptor)
                (let ((made (made! objects (sampler-request descriptor))))
                  (sampler-handle (● made first) (● made second)))))
             (create-shader-module
              (lambda (descriptor)
                (let ((made (made! objects (module-request descriptor))))
                  (module-handle (● made first) (● made second)))))
             (create-render-pipeline
              (lambda (descriptor)
                (let ((made (made! objects (pipeline-request descriptor))))
                  (pipeline-handle (● made first) (● made second)))))
             (create-bind-group
              (lambda (descriptor)
                (let ((made (made! objects (bind-group-request descriptor))))
                  (bind-group-handle (● made first) (● made second)))))
             (create-command-encoder
              (lambda ()
                (let ((id (transient! objects "encoder")))
                  (host-encoder id)
                  (new GpuCommandEncoder (id id)))))
             (copy-buffer-to-buffer
              (lambda (encoder source source-offset destination destination-offset size)
                (host-copy-buffer (used objects (● encoder id))
                                  (used objects (● source id))
                                  source-offset
                                  (used objects (● destination id))
                                  destination-offset
                                  size)))
             (copy-texture-to-buffer
              (lambda (encoder copy buffer offset bytes-per-row width height)
                (host-copy-texture-to-buffer (used objects (● encoder id))
                                             (used objects (● (● copy texture) id))
                                             (● copy mip)
                                             (● copy x)
                                             (● copy y)
                                             (● copy layer)
                                             (used objects (● buffer id))
                                             offset
                                             bytes-per-row
                                             width
                                             height)))
             (copy-texture-to-texture
              (lambda (encoder source destination width height)
                (host-copy-texture (used objects (● encoder id))
                                   (used objects (● (● source texture) id))
                                   (● source mip)
                                   (● source x)
                                   (● source y)
                                   (● source layer)
                                   (used objects (● (● destination texture) id))
                                   (● destination mip)
                                   (● destination x)
                                   (● destination y)
                                   (● destination layer)
                                   width
                                   height)))
             (begin-render-pass
              (lambda (encoder descriptor)
                (let ((pass (pass-json descriptor)) (encoder (used objects (● encoder id))))
                  (all-used! objects (● pass second))
                  (let ((id (transient! objects "pass")))
                    (host-begin-pass encoder id (string->utf8 (● pass first)))
                    (new GpuRenderPass (id id))))))
             (set-pipeline
              (lambda (pass pipeline)
                (host-set-pipeline (used objects (● pass id)) (used objects (● pipeline id)))))
             (set-bind-group
              (lambda (pass index group)
                (host-set-bind-group (used objects (● pass id)) index (used objects (● group id)))))
             (set-vertex-buffer
              (lambda (pass slot buffer offset)
                (host-set-vertex-buffer (used objects (● pass id))
                                        slot
                                        (used objects (● buffer id))
                                        offset)))
             (set-index-buffer
              (lambda (pass buffer format offset)
                (host-set-index-buffer (used objects (● pass id))
                                       (used objects (● buffer id))
                                       (match format
                                         ((Uint16Index) 0)
                                         ((Uint32Index) 1))
                                       offset)))
             (set-scissor-rect
              (lambda (pass x y width height)
                (host-set-scissor (used objects (● pass id)) x y width height)))
             (draw
              (lambda (pass vertices instances first-vertex first-instance)
                (host-draw (used objects (● pass id))
                           vertices
                           instances
                           first-vertex
                           first-instance)))
             (draw-indexed
              (lambda (pass indices instances first-index base-vertex first-instance)
                (host-draw-indexed (used objects (● pass id))
                                   indices
                                   instances
                                   first-index
                                   base-vertex
                                   first-instance)))
             (draw-indexed-indirect
              (lambda (pass buffer offset)
                (host-draw-indexed-indirect (used objects (● pass id))
                                            (used objects (● buffer id))
                                            offset)))
             (end-pass (lambda (pass) (host-end-pass (used objects (● pass id)))))
             (finish
              (lambda (encoder)
                (let ((encoder (used objects (● encoder id)))
                      (id (transient! objects "command-buffer")))
                  (host-finish encoder id)
                  (new GpuCommandBuffer (id id)))))
             (submit (lambda (buffers) (submitted! objects buffers)))
             (current-texture
              (lambda ()
                (let ((id (transient! objects "canvas")))
                  (host-current-texture id)
                  (new GpuTexture (id id) (generation 1) (fresh #t)))))
             (destroy
              (lambda (object)
                (gone! (retire! objects
                                (match object
                                  ((BufferObject buffer) (● buffer id))
                                  ((TextureObject texture) (● texture id)))
                                "destroyed")))))
          (work))))

    ;; ---- The device ----

    ;; The host asks the page's adapter for the baseline features, and for
    ;; the optional ones it has (host/browser/gpu.mjs).

    (define (requested! (objects Objects) (budget I64)) (→ DeviceInfo) (! mut tasks)
      (let ((status (through-host host-start-device host-finish-device)))
        (unless (= status 0)
          (panic "gpu: this page has no WebGPU device with the baseline features"))
        (set! (● objects budget) budget)
        (new DeviceInfo
          (format (texture-format-named (reply (host-device-format))))
          (features (words (reply (host-device-features)))))))

    (define (reply (count I32)) (→ String)
      (string-generate (i32->i64 count)
                       (lambda (index)
                         (integer->char (i32->i64 (host-reply-scalar (i64->i32 index)))))))

    ;; The words of a text separated by single spaces.

    (define (words (text String)) (→ (List String))
      (if (string=? text "")
          (Nil)
          (match (string-index text #\space)
            ((Some at)
             (Cons (substring text 0 at) (words (substring text (+ at 1) (string-length text)))))
            ((None) (list text)))))

    (define (requested (objects Objects)) (→ Unit)
      (when (= (● objects budget) 0)
        (panic "gpu: request-device first")))

    ;; ---- Objects ----

    ;; The host's constructor for each kind of object the books make.

    (define (kind-index (kind String)) (→ I32)
      (cond ((string=? kind "buffer") 0)
            ((string=? kind "texture") 1)
            ((string=? kind "sampler") 2)
            ((string=? kind "shader") 3)
            ((string=? kind "render-pipeline") 4)
            ((string=? kind "bind-group") 5)
            (else (panic (string-append "gpu: no constructor for " kind)))))

    ;; An object by its request, made on the host when the books say so,
    ;; and whether it was.

    (define (made! (objects Objects) (request Request)) (→ (Pair Entry Bool)) (! mut)
      (requested objects)
      (all-used! objects (● request depends))
      (match (claim! objects request)
        ((Existing entry) (new Pair (first entry) (second #f)))
        ((Create entry retired)
         (for-each gone! retired)
         (host-create (kind-index (● entry kind)) (● entry id) (string->utf8 (● entry descriptor)))
         (new Pair (first entry) (second #t)))))

    (define (transient! (objects Objects) (kind String)) (→ I32) (! mut)
      (requested objects)
      (match (claim! objects
                     (new Request
                       (kind kind)
                       (path (None))
                       (descriptor "")
                       (bytes 0)
                       (depends (Nil))
                       (width 0)
                       (height 0)))
        ((Create entry _) (● entry id))
        ((Existing entry) (● entry id))))

    (define (used (objects Objects) (id I32)) (→ I32) (! mut)
      (● (use! objects id) id))

    ;; The canvas's texture belongs to the canvas, so the host only forgets
    ;; it; every other object is destroyed.

    (define (gone! (entry Entry)) (→ Unit)
      (if (string=? (● entry kind) "canvas")
          (host-release (● entry id))
          (host-destroy (● entry id))))

    (define (submitted! (objects Objects) (buffers (List GpuCommandBuffer))) (→ Unit) (! mut)
      (host-submit
       (string->utf8
        (json->string
         (JsonArray (map (lambda (buffer) (JsonInteger (i32->i64 (used objects (● buffer id)))))
                         buffers)))))
      (for-each gone! (end-frame! objects)))

    ;; ---- Waits ----

    (define (read-bytes (buffer I32) (offset I32) (size I32)) (→ Bytes) (! tasks)
      (let ((count (through-host (lambda (ticket) (host-start-read ticket buffer offset size))
                                 host-finish-read)))
        (array-generate (i32->i64 count) (lambda (index) (host-read-byte (i64->i32 index))))))

    ;; An image already decoded by its path is answered at once; otherwise
    ;; the host decodes it and holds the texture until the books give it an
    ;; id.

    (define (decoded! (objects Objects) (path (List String)) (bytes Bytes)) (→ Image) (! mut tasks)
      (requested objects)
      (match (known! objects (image-request path 0 0))
        ((Some entry)
         (new Image
           (texture (texture-handle entry #f))
           (width (● entry width))
           (height (● entry height))))
        ((None)
         (let* ((width (through-host (lambda (ticket)
                                       (host-start-decode ticket
                                                          (texture-usage-bits (list (TextureBinding)
                                                                                    (TextureCopySrc)
                                                                                    (TextureCopyDst)
                                                                                    (RenderAttachment)))
                                                          bytes))
                                     host-finish-decode))
                (height (host-decoded-height)))
           (match (claim! objects (image-request path width height))
             ((Existing entry)
              (host-drop-decoded)
              (new Image
                (texture (texture-handle entry #f))
                (width (● entry width))
                (height (● entry height))))
             ((Create entry retired)
              (for-each gone! retired)
              (host-keep-decoded (● entry id))
              (new Image (texture (texture-handle entry #t)) (width width) (height height))))))))

    ))
