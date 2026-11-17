;; The page's WebGPU device for the `gpu` effect: `provide-gpu` runs each
;; operation on the device host/browser/gpu.mjs holds, which knows each
;; object by the id it gave it.
(define-library (snail shell gpu page)
  (export
   provide-gpu)
  (import
   (snail core base)
   (snail shell task)
   (snail shell gpu)
   (prefix (snail runtime browser gpu) host-))
  (begin

    ;; ---- Handling ----

    (define (provide-gpu (work (Fn → T ! gpu e))) (→ T) (! e) (∀ (T e))
      (handle gpu
          ((request-device requested)
           (create-buffer
            (lambda (descriptor) (new GpuBuffer (id (made 0 (buffer-fields descriptor))))))
           (write-buffer
            (lambda (buffer offset bytes) (host-write-buffer (● buffer id) offset bytes)))
           (read-buffer (lambda (buffer offset size) (read-bytes (● buffer id) offset size)))
           (create-texture
            (lambda (descriptor) (new GpuTexture (id (made 1 (texture-fields descriptor))))))
           (create-view
            (lambda (texture descriptor)
              (new GpuTextureView
                (id (host-create-view (● texture id) (fields-bytes (view-fields descriptor)))))))
           (write-texture
            (lambda (copy bytes-per-row width height bytes)
              (host-write-texture (● (● copy texture) id)
                                  (● copy mip)
                                  (● copy x)
                                  (● copy y)
                                  (● copy layer)
                                  bytes-per-row
                                  width
                                  height
                                  bytes)))
           (decode-image decoded)
           (create-sampler
            (lambda (descriptor) (new GpuSampler (id (made 2 (sampler-fields descriptor))))))
           (create-shader-module
            (lambda (descriptor) (new GpuShaderModule (id (made 3 (module-fields descriptor))))))
           (create-render-pipeline
            (lambda (descriptor)
              (new GpuRenderPipeline (id (made 4 (pipeline-fields descriptor))))))
           (create-bind-group
            (lambda (descriptor) (new GpuBindGroup (id (made 5 (bind-group-fields descriptor))))))
           (create-command-encoder (lambda () (new GpuCommandEncoder (id (host-encoder)))))
           (copy-buffer-to-buffer
            (lambda (encoder source source-offset destination destination-offset size)
              (host-copy-buffer (● encoder id)
                                (● source id)
                                source-offset
                                (● destination id)
                                destination-offset
                                size)))
           (copy-texture-to-buffer
            (lambda (encoder copy buffer offset bytes-per-row width height)
              (host-copy-texture-to-buffer (● encoder id)
                                           (● (● copy texture) id)
                                           (● copy mip)
                                           (● copy x)
                                           (● copy y)
                                           (● copy layer)
                                           (● buffer id)
                                           offset
                                           bytes-per-row
                                           width
                                           height)))
           (copy-texture-to-texture
            (lambda (encoder source destination width height)
              (host-copy-texture (● encoder id)
                                 (● (● source texture) id)
                                 (● source mip)
                                 (● source x)
                                 (● source y)
                                 (● source layer)
                                 (● (● destination texture) id)
                                 (● destination mip)
                                 (● destination x)
                                 (● destination y)
                                 (● destination layer)
                                 width
                                 height)))
           (begin-render-pass
            (lambda (encoder descriptor)
              (attachments descriptor)
              (new GpuRenderPass (id (host-begin-pass (● encoder id))))))
           (set-pipeline
            (lambda (pass pipeline) (host-set-pipeline (● pass id) (● pipeline id))))
           (set-bind-group
            (lambda (pass index group) (host-set-bind-group (● pass id) index (● group id))))
           (set-vertex-buffer
            (lambda (pass slot buffer offset)
              (host-set-vertex-buffer (● pass id) slot (● buffer id) offset)))
           (set-index-buffer
            (lambda (pass buffer format offset)
              (host-set-index-buffer (● pass id)
                                     (● buffer id)
                                     (match format
                                       ((Uint16Index) 0)
                                       ((Uint32Index) 1))
                                     offset)))
           (set-scissor-rect
            (lambda (pass x y width height) (host-set-scissor (● pass id) x y width height)))
           (draw
            (lambda (pass vertices instances first-vertex first-instance)
              (host-draw (● pass id) vertices instances first-vertex first-instance)))
           (draw-indexed
            (lambda (pass indices instances first-index base-vertex first-instance)
              (host-draw-indexed (● pass id)
                                 indices
                                 instances
                                 first-index
                                 base-vertex
                                 first-instance)))
           (draw-indexed-indirect
            (lambda (pass buffer offset)
              (host-draw-indexed-indirect (● pass id) (● buffer id) offset)))
           (end-pass (lambda (pass) (host-end-pass (● pass id))))
           (finish
            (lambda (encoder) (new GpuCommandBuffer (id (host-finish (● encoder id))))))
           (submit submitted)
           (current-texture
            (lambda ()
              (let ((id (host-current-texture)))
                (new Image
                  (texture (new GpuTexture (id id)))
                  (width (host-current-width))
                  (height (host-current-height))))))
           (destroy (lambda (object) (host-destroy (object-id object)))))
        (work)))

    ;; ---- Objects ----

    ;; An object of the host's kind `kind`, in the order of `made` in
    ;; host/browser/gpu.mjs, from its descriptor's fields.

    (define (made (kind I32) (fields (List Field))) (→ I32)
      (host-create kind (fields-bytes fields)))

    (define (object-id (object GpuObject)) (→ I32)
      (match object
        ((BufferObject buffer) (● buffer id))
        ((TextureObject texture) (● texture id))
        ((ViewObject view) (● view id))
        ((SamplerObject sampler) (● sampler id))
        ((ModuleObject module) (● module id))
        ((PipelineObject pipeline) (● pipeline id))
        ((BindGroupObject group) (● group id))))

    ;; Each command buffer is queued, then the queue submitted.

    (define (submitted (buffers (List GpuCommandBuffer))) (→ Unit)
      (for-each (lambda (buffer) (host-queue-buffer (● buffer id))) buffers)
      (host-submit))

    ;; ---- Passes ----

    ;; Each attachment is its view, its load and its store, in one call.

    (define (attachments (descriptor RenderPassDescriptor)) (→ Unit)
      (for-each color-attachment (● descriptor colors))
      (match (● descriptor depth)
        ((Some attachment) (depth-attachment attachment))
        ((None) (unit))))

    (define (color-attachment (attachment ColorAttachment)) (→ Unit)
      (let ((view (● attachment view id)) (store (store-flag (● attachment store))))
        (match (● attachment load)
          ((Clear color)
           (host-pass-color view
                            1
                            (● color red)
                            (● color green)
                            (● color blue)
                            (● color alpha)
                            store))
          ((Keep) (host-pass-color view 0 0.0 0.0 0.0 0.0 store)))))

    (define (depth-attachment (attachment DepthAttachment)) (→ Unit)
      (let ((view (● attachment view id)) (store (store-flag (● attachment store))))
        (match (● attachment load)
          ((ClearDepth depth) (host-pass-depth view 1 depth store))
          ((KeepDepth) (host-pass-depth view 0 0.0 store)))))

    (define (store-flag (store Bool)) (→ I32) (if store 1 0))

    ;; ---- The device ----

    ;; The host asks the page's adapter for the baseline features, and for
    ;; the optional ones it has (host/browser/gpu.mjs).

    (define (requested) (→ DeviceInfo) (! tasks)
      (let ((status (through-host host-start-device host-finish-device)))
        (unless (= status 0)
          (panic "gpu: this page has no WebGPU device with the baseline features"))
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

    ;; ---- Waits ----

    (define (read-bytes (buffer I32) (offset I32) (size I32)) (→ Bytes) (! tasks)
      (let ((count (through-host (lambda (ticket) (host-start-read ticket buffer offset size))
                                 host-finish-read)))
        (array-generate (i32->i64 count) (lambda (index) (host-read-byte (i64->i32 index))))))

    ;; The host decodes the image and holds its texture until it is kept.

    (define (decoded (bytes Bytes)) (→ Image) (! tasks)
      (let* ((width (through-host (lambda (ticket)
                                    (host-start-decode ticket
                                                       (texture-usage-bits (list (TextureBinding)
                                                                                 (TextureCopySrc)
                                                                                 (TextureCopyDst)
                                                                                 (RenderAttachment)))
                                                       bytes))
                                  host-finish-decode))
             (height (host-decoded-height)))
        (new Image
          (texture (new GpuTexture (id (host-keep-decoded))))
          (width width)
          (height height))))

    ))
