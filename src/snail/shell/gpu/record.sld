;; A `gpu` handler that runs nothing: it keeps the same books as the page's,
;; and records a line for each operation that would reach the host, so a
;; graphics library's test reads what it asked of WebGPU. A buffer reads as
;; zeros, and an image is as large as its PNG header says.
(define-library (snail shell gpu record)
  (export
   with-recorded-gpu)
  (import
   (snail core base)
   (snail shell json)
   (snail shell gpu))
  (begin

    ;; ---- Recording ----

    (record Recording
      ((objects Objects)
       (lines (List String))))

    (define (note! (recording Recording) (words (List String))) (→ Unit) (! mut)
      (set! (● recording lines) (Cons (string-join words " ") (● recording lines))))

    ;; The work's answer and the lines it recorded, in order.

    (define (with-recorded-gpu (budget I64) (work (Fn → T ! gpu e)))
      (→ (Pair T (List String)))
      (! mut e)
      (∀ (T e))
      (let ((recording (new Recording (objects (make-objects budget)) (lines (Nil)))))
        (let ((value (handle gpu
                         ((request-device
                           (lambda (budget)
                             (note! recording (list "request-device" (show budget)))
                             (new DeviceInfo (format (Bgra8Unorm)) (features (Nil)))))
                          (create-buffer
                           (lambda (descriptor)
                             (let ((made (made! recording (buffer-request descriptor))))
                               (buffer-handle (● made first) (● made second)))))
                          (write-buffer
                           (lambda (buffer offset bytes)
                             (note! recording
                                    (list "write-buffer"
                                          (used recording (● buffer id))
                                          (show offset)
                                          (show (array-length bytes))))))
                          (read-buffer
                           (lambda (buffer offset size)
                             (note! recording
                                    (list "read-buffer"
                                          (used recording (● buffer id))
                                          (show offset)
                                          (show size)))
                             (make-array (i32->i64 size) (i32->u8 0))))
                          (create-texture
                           (lambda (descriptor)
                             (let ((made (made! recording (texture-request descriptor))))
                               (texture-handle (● made first) (● made second)))))
                          (write-texture
                           (lambda (copy bytes-per-row width height bytes)
                             (note! recording
                                    (list "write-texture"
                                          (used recording (● (● copy texture) id))
                                          (copy-text copy)
                                          (show bytes-per-row)
                                          (show width)
                                          (show height)
                                          (show (array-length bytes))))))
                          (decode-image (lambda (path bytes) (decoded! recording path bytes)))
                          (create-sampler
                           (lambda (descriptor)
                             (let ((made (made! recording (sampler-request descriptor))))
                               (sampler-handle (● made first) (● made second)))))
                          (create-shader-module
                           (lambda (descriptor)
                             (let ((made (made! recording (module-request descriptor))))
                               (module-handle (● made first) (● made second)))))
                          (create-render-pipeline
                           (lambda (descriptor)
                             (let ((made (made! recording (pipeline-request descriptor))))
                               (pipeline-handle (● made first) (● made second)))))
                          (create-bind-group
                           (lambda (descriptor)
                             (let ((made (made! recording (bind-group-request descriptor))))
                               (bind-group-handle (● made first) (● made second)))))
                          (create-command-encoder
                           (lambda ()
                             (new GpuCommandEncoder (id (transient! recording "encoder" (Nil))))))
                          (copy-buffer-to-buffer
                           (lambda (encoder source
                                            source-offset
                                            destination
                                            destination-offset
                                            size)
                             (note! recording
                                    (list "copy-buffer-to-buffer"
                                          (used recording (● encoder id))
                                          (used recording (● source id))
                                          (show source-offset)
                                          (used recording (● destination id))
                                          (show destination-offset)
                                          (show size)))))
                          (copy-texture-to-buffer
                           (lambda (encoder copy buffer offset bytes-per-row width height)
                             (note! recording
                                    (list "copy-texture-to-buffer"
                                          (used recording (● encoder id))
                                          (used recording (● (● copy texture) id))
                                          (copy-text copy)
                                          (used recording (● buffer id))
                                          (show offset)
                                          (show bytes-per-row)
                                          (show width)
                                          (show height)))))
                          (copy-texture-to-texture
                           (lambda (encoder source destination width height)
                             (note! recording
                                    (list "copy-texture-to-texture"
                                          (used recording (● encoder id))
                                          (used recording (● (● source texture) id))
                                          (copy-text source)
                                          (used recording (● (● destination texture) id))
                                          (copy-text destination)
                                          (show width)
                                          (show height)))))
                          (begin-render-pass
                           (lambda (encoder descriptor)
                             (let ((pass (pass-json descriptor))
                                   (encoder (used recording (● encoder id))))
                               (all-used! (● recording objects) (● pass second))
                               (new GpuRenderPass
                                 (id
                                  (transient! recording "pass" (list encoder (● pass first))))))))
                          (set-pipeline
                           (lambda (pass pipeline)
                             (note! recording
                                    (list "set-pipeline"
                                          (used recording (● pass id))
                                          (used recording (● pipeline id))))))
                          (set-bind-group
                           (lambda (pass index group)
                             (note! recording
                                    (list "set-bind-group"
                                          (used recording (● pass id))
                                          (show index)
                                          (used recording (● group id))))))
                          (set-vertex-buffer
                           (lambda (pass slot buffer offset)
                             (note! recording
                                    (list "set-vertex-buffer"
                                          (used recording (● pass id))
                                          (show slot)
                                          (used recording (● buffer id))
                                          (show offset)))))
                          (set-index-buffer
                           (lambda (pass buffer format offset)
                             (note! recording
                                    (list "set-index-buffer"
                                          (used recording (● pass id))
                                          (used recording (● buffer id))
                                          (match format
                                            ((Uint16Index) "uint16")
                                            ((Uint32Index) "uint32"))
                                          (show offset)))))
                          (set-scissor-rect
                           (lambda (pass x y width height)
                             (note! recording
                                    (list "set-scissor-rect"
                                          (used recording (● pass id))
                                          (show x)
                                          (show y)
                                          (show width)
                                          (show height)))))
                          (draw
                           (lambda (pass vertices instances first-vertex first-instance)
                             (note! recording
                                    (list "draw"
                                          (used recording (● pass id))
                                          (show vertices)
                                          (show instances)
                                          (show first-vertex)
                                          (show first-instance)))))
                          (draw-indexed
                           (lambda (pass indices instances first-index base-vertex first-instance)
                             (note! recording
                                    (list "draw-indexed"
                                          (used recording (● pass id))
                                          (show indices)
                                          (show instances)
                                          (show first-index)
                                          (show base-vertex)
                                          (show first-instance)))))
                          (draw-indexed-indirect
                           (lambda (pass buffer offset)
                             (note! recording
                                    (list "draw-indexed-indirect"
                                          (used recording (● pass id))
                                          (used recording (● buffer id))
                                          (show offset)))))
                          (end-pass
                           (lambda (pass)
                             (note! recording (list "end-pass" (used recording (● pass id))))))
                          (finish
                           (lambda (encoder)
                             (let ((encoder (used recording (● encoder id))))
                               (new GpuCommandBuffer
                                 (id (transient! recording "command-buffer" (list encoder)))))))
                          (submit (lambda (buffers) (submitted! recording buffers)))
                          (current-texture
                           (lambda ()
                             (new GpuTexture
                               (id (transient! recording "canvas" (Nil)))
                               (generation 1)
                               (fresh #t))))
                          (destroy
                           (lambda (object)
                             (let ((entry (retire! (● recording objects)
                                                   (match object
                                                     ((BufferObject buffer) (● buffer id))
                                                     ((TextureObject texture) (● texture id)))
                                                   "destroyed")))
                               (note! recording (list "destroy" (show (● entry id))))))))
                       (work))))
          (new Pair (first value) (second (reverse (● recording lines)))))))

    ;; ---- Objects ----

    (define (made! (recording Recording) (request Request)) (→ (Pair Entry Bool)) (! mut)
      (all-used! (● recording objects) (● request depends))
      (match (claim! (● recording objects) request)
        ((Existing entry) (new Pair (first entry) (second #f)))
        ((Create entry retired)
         (for-each (lambda (gone) (note! recording (list "destroy" (show (● gone id))))) retired)
         (note! recording (list "create" (● entry kind) (show (● entry id)) (● entry descriptor)))
         (new Pair (first entry) (second #t)))))

    ;; A frame's object, recorded with what it was made from.

    (define (transient! (recording Recording) (kind String) (words (List String))) (→ I32) (! mut)
      (match (claim! (● recording objects)
                     (new Request
                       (kind kind)
                       (path (None))
                       (descriptor "")
                       (bytes 0)
                       (depends (Nil))
                       (width 0)
                       (height 0)))
        ((Create entry _)
         (note! recording (append (list kind (show (● entry id))) words))
         (● entry id))
        ((Existing entry) (● entry id))))

    ;; An object's id, as text, once the books have checked and marked it.

    (define (used (recording Recording) (id I32)) (→ String) (! mut)
      (show (● (use! (● recording objects) id) id)))

    (define (copy-text (copy TextureCopy)) (→ String)
      (string-append "mip "
                     (show (● copy mip))
                     " at "
                     (show (● copy x))
                     ","
                     (show (● copy y))
                     " layer "
                     (show (● copy layer))))

    (define (submitted! (recording Recording) (buffers (List GpuCommandBuffer))) (→ Unit) (! mut)
      (note! recording
             (Cons "submit" (map (lambda (buffer) (used recording (● buffer id))) buffers)))
      (end-frame! (● recording objects))
      (unit))

    ;; ---- Images ----

    ;; A PNG's size is in its header, big-endian after the signature and
    ;; the header's length and type; anything else is one texel.

    (define (decoded! (recording Recording) (path (List String)) (bytes Bytes)) (→ Image) (! mut)
      (let* ((png? (and (>= (array-length bytes) 24) (= (array-ref bytes 1) 80)))
             (width (if png? (big-endian bytes 16) 1))
             (height (if png? (big-endian bytes 20) 1))
             (objects (● recording objects)))
        (match (known! objects (image-request path width height))
          ((Some entry)
           (new Image
             (texture (texture-handle entry #f))
             (width (● entry width))
             (height (● entry height))))
          ((None)
           (match (claim! objects (image-request path width height))
             ((Create entry retired)
              (for-each (lambda (gone) (note! recording (list "destroy" (show (● gone id)))))
                        retired)
              (note! recording
                     (list "decode-image"
                           (show (● entry id))
                           (path-name path)
                           (show width)
                           (show height)))
              (new Image (texture (texture-handle entry #t)) (width width) (height height)))
             ((Existing entry)
              (new Image
                (texture (texture-handle entry #f))
                (width (● entry width))
                (height (● entry height)))))))))

    (define (big-endian (bytes Bytes) (at I64)) (→ I32)
      (fold-left (lambda (value index)
                   (i32-or (i32-shift-left value 8) (u8->i32 (array-ref bytes (+ at index)))))
                 0
                 (iota 4)))

    ))
