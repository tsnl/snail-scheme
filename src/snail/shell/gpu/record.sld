;; A `gpu` handler that runs nothing: it numbers the objects a program
;; makes and records a line for each operation the page would send to the
;; host, so a graphics library's test reads what it asked of WebGPU. A
;; buffer reads as zeros, an image is as large as its PNG header says, and
;; the canvas is 640 by 480.
(define-library (snail shell gpu record)
  (export
   with-recorded-gpu)
  (import
   (snail core base)
   (snail shell gpu))
  (begin

    ;; ---- Recording ----

    (record Recording
      ((next I32)
       (lines (List String))))

    (define (note! (recording Recording) (words (List String))) (→ Unit) (! mut)
      (set! (● recording lines) (Cons (string-join words " ") (● recording lines))))

    ;; The work's answer and the lines it recorded, in order.

    (define (with-recorded-gpu (work (Fn Gpu → T ! mut e)))
      (→ (Pair T (List String)))
      (! mut e)
      (∀ (T e))
      (let ((recording (new Recording (next 1) (lines (Nil)))))
        (let ((value (work (new Gpu
                             (request-device
                              (lambda ()
                                (note! recording (list "request-device"))
                                (new DeviceInfo (format (Bgra8Unorm)) (features (Nil)))))
                             (create-buffer
                              (lambda (descriptor)
                                (new GpuBuffer
                                  (id (made! recording "buffer" (buffer-fields descriptor))))))
                             (write-buffer
                              (lambda (buffer offset bytes)
                                (note! recording
                                       (list "write-buffer"
                                             (show (● buffer id))
                                             (show offset)
                                             (show (array-length bytes))))))
                             (read-buffer
                              (lambda (buffer offset size)
                                (note! recording
                                       (list "read-buffer"
                                             (show (● buffer id))
                                             (show offset)
                                             (show size)))
                                (make-array (i32->i64 size) (i32->u8 0))))
                             (create-texture
                              (lambda (descriptor)
                                (new GpuTexture
                                  (id (made! recording "texture" (texture-fields descriptor))))))
                             (create-view
                              (lambda (texture descriptor)
                                (new GpuTextureView
                                  (id (made! recording
                                             "view"
                                             (Cons (Text (show (● texture id)))
                                                   (view-fields descriptor)))))))
                             (write-texture
                              (lambda (copy bytes-per-row width height bytes)
                                (note! recording
                                       (list "write-texture"
                                             (show (● (● copy texture) id))
                                             (copy-text copy)
                                             (show bytes-per-row)
                                             (show width)
                                             (show height)
                                             (show (array-length bytes))))))
                             (decode-image (lambda (bytes) (decoded! recording bytes)))
                             (create-sampler
                              (lambda (descriptor)
                                (new GpuSampler
                                  (id (made! recording "sampler" (sampler-fields descriptor))))))
                             (create-shader-module
                              (lambda (descriptor)
                                (new GpuShaderModule
                                  (id (made! recording "shader" (module-fields descriptor))))))
                             (create-render-pipeline
                              (lambda (descriptor)
                                (new GpuRenderPipeline
                                  (id
                                   (made! recording
                                          "render-pipeline"
                                          (pipeline-fields descriptor))))))
                             (create-bind-group
                              (lambda (descriptor)
                                (new GpuBindGroup
                                  (id
                                   (made! recording "bind-group" (bind-group-fields descriptor))))))
                             (create-command-encoder
                              (lambda ()
                                (new GpuCommandEncoder
                                  (id (transient! recording "encoder" (Nil))))))
                             (copy-buffer-to-buffer
                              (lambda (encoder source
                                               source-offset
                                               destination
                                               destination-offset
                                               size)
                                (note! recording
                                       (list "copy-buffer-to-buffer"
                                             (show (● encoder id))
                                             (show (● source id))
                                             (show source-offset)
                                             (show (● destination id))
                                             (show destination-offset)
                                             (show size)))))
                             (copy-texture-to-buffer
                              (lambda (encoder copy buffer offset bytes-per-row width height)
                                (note! recording
                                       (list "copy-texture-to-buffer"
                                             (show (● encoder id))
                                             (show (● (● copy texture) id))
                                             (copy-text copy)
                                             (show (● buffer id))
                                             (show offset)
                                             (show bytes-per-row)
                                             (show width)
                                             (show height)))))
                             (copy-texture-to-texture
                              (lambda (encoder source destination width height)
                                (note! recording
                                       (list "copy-texture-to-texture"
                                             (show (● encoder id))
                                             (show (● (● source texture) id))
                                             (copy-text source)
                                             (show (● (● destination texture) id))
                                             (copy-text destination)
                                             (show width)
                                             (show height)))))
                             (begin-render-pass
                              (lambda (encoder descriptor)
                                (let* ((encoder (show (● encoder id)))
                                       (attachments (pass-words descriptor)))
                                  (new GpuRenderPass
                                    (id
                                     (transient! recording "pass" (Cons encoder attachments)))))))
                             (set-pipeline
                              (lambda (pass pipeline)
                                (note! recording
                                       (list "set-pipeline"
                                             (show (● pass id))
                                             (show (● pipeline id))))))
                             (set-bind-group
                              (lambda (pass index group)
                                (note! recording
                                       (list "set-bind-group"
                                             (show (● pass id))
                                             (show index)
                                             (show (● group id))))))
                             (set-vertex-buffer
                              (lambda (pass slot buffer offset)
                                (note! recording
                                       (list "set-vertex-buffer"
                                             (show (● pass id))
                                             (show slot)
                                             (show (● buffer id))
                                             (show offset)))))
                             (set-index-buffer
                              (lambda (pass buffer format offset)
                                (note! recording
                                       (list "set-index-buffer"
                                             (show (● pass id))
                                             (show (● buffer id))
                                             (match format
                                               ((Uint16Index) "uint16")
                                               ((Uint32Index) "uint32"))
                                             (show offset)))))
                             (set-scissor-rect
                              (lambda (pass x y width height)
                                (note! recording
                                       (list "set-scissor-rect"
                                             (show (● pass id))
                                             (show x)
                                             (show y)
                                             (show width)
                                             (show height)))))
                             (draw
                              (lambda (pass vertices instances first-vertex first-instance)
                                (note! recording
                                       (list "draw"
                                             (show (● pass id))
                                             (show vertices)
                                             (show instances)
                                             (show first-vertex)
                                             (show first-instance)))))
                             (draw-indexed
                              (lambda (pass indices
                                            instances
                                            first-index
                                            base-vertex
                                            first-instance)
                                (note! recording
                                       (list "draw-indexed"
                                             (show (● pass id))
                                             (show indices)
                                             (show instances)
                                             (show first-index)
                                             (show base-vertex)
                                             (show first-instance)))))
                             (draw-indexed-indirect
                              (lambda (pass buffer offset)
                                (note! recording
                                       (list "draw-indexed-indirect"
                                             (show (● pass id))
                                             (show (● buffer id))
                                             (show offset)))))
                             (end-pass
                              (lambda (pass)
                                (note! recording (list "end-pass" (show (● pass id))))))
                             (create-compute-pipeline
                              (lambda (descriptor)
                                (new GpuComputePipeline
                                  (id (made! recording
                                             "compute-pipeline"
                                             (compute-pipeline-fields descriptor))))))
                             (begin-compute-pass
                              (lambda (encoder)
                                (new GpuComputePass
                                  (id (transient! recording
                                                  "compute-pass"
                                                  (list (show (● encoder id))))))))
                             (set-compute-pipeline
                              (lambda (pass pipeline)
                                (note! recording
                                       (list "set-compute-pipeline"
                                             (show (● pass id))
                                             (show (● pipeline id))))))
                             (set-compute-bind-group
                              (lambda (pass index group)
                                (note! recording
                                       (list "set-compute-bind-group"
                                             (show (● pass id))
                                             (show index)
                                             (show (● group id))))))
                             (dispatch-workgroups
                              (lambda (pass x y z)
                                (note! recording
                                       (list "dispatch-workgroups"
                                             (show (● pass id))
                                             (show x)
                                             (show y)
                                             (show z)))))
                             (dispatch-workgroups-indirect
                              (lambda (pass buffer offset)
                                (note! recording
                                       (list "dispatch-workgroups-indirect"
                                             (show (● pass id))
                                             (show (● buffer id))
                                             (show offset)))))
                             (end-compute-pass
                              (lambda (pass)
                                (note! recording (list "end-compute-pass" (show (● pass id))))))
                             (finish
                              (lambda (encoder)
                                (let ((encoder (show (● encoder id))))
                                  (new GpuCommandBuffer
                                    (id (transient! recording "command-buffer" (list encoder)))))))
                             (submit (lambda (buffers) (submitted! recording buffers)))
                             (work-done (lambda () (note! recording (list "work-done"))))
                             (current-texture
                              (lambda ()
                                (new Image
                                  (texture
                                   (new GpuTexture (id (transient! recording "canvas" (Nil)))))
                                  (width 640)
                                  (height 480))))
                             (destroy
                              (lambda (object)
                                (note! recording (list "destroy" (show (object-id object))))))))))
          (new Pair (first value) (second (reverse (● recording lines)))))))

    ;; ---- Objects ----

    ;; Objects are numbered from 1 in the order they are made.

    (define (numbered! (recording Recording)) (→ I32) (! mut)
      (let ((id (● recording next)))
        (set! (● recording next) (+ id 1))
        id))

    (define (made! (recording Recording) (kind String) (fields (List Field))) (→ I32) (! mut)
      (let ((id (numbered! recording)))
        (note! recording (list "create" kind (show id) (fields-text fields)))
        id))

    ;; A frame's object, recorded with what it was made from.

    (define (transient! (recording Recording) (kind String) (words (List String))) (→ I32) (! mut)
      (let ((id (numbered! recording)))
        (note! recording (append (list kind (show id)) words))
        id))

    (define (object-id (object GpuObject)) (→ I32)
      (match object
        ((BufferObject buffer) (● buffer id))
        ((TextureObject texture) (● texture id))
        ((ViewObject view) (● view id))
        ((SamplerObject sampler) (● sampler id))
        ((ModuleObject module) (● module id))
        ((PipelineObject pipeline) (● pipeline id))
        ((ComputePipelineObject pipeline) (● pipeline id))
        ((BindGroupObject group) (● group id))))

    ;; A pass's attachments as the page's calls send them: each view, its
    ;; load and its store.

    (define (pass-words (descriptor RenderPassDescriptor)) (→ (List String))
      (append (concatenate
               (map (lambda (optional)
                      (match optional
                        ((Some attachment) (attachment-words attachment))
                        ((None) (list "none"))))
                    (● descriptor colors)))
              (match (● descriptor depth)
                ((Some attachment)
                 (concatenate
                  (list (list "depth" (show (● attachment view id)))
                        (match (● attachment load)
                          ((ClearDepth depth) (list "clear" (show depth)))
                          ((KeepDepth) (list "load"))
                          ((ReadOnlyDepth) (list "read-only")))
                        (list (if (● attachment store) "store" "discard")))))
                ((None) (Nil)))))

    (define (attachment-words (attachment ColorAttachment)) (→ (List String))
      (concatenate (list (list (show (● attachment view id)))
                         (match (● attachment load)
                           ((Clear color)
                            (list "clear"
                                  (show (● color red))
                                  (show (● color green))
                                  (show (● color blue))
                                  (show (● color alpha))))
                           ((Keep) (list "load")))
                         (list (if (● attachment store) "store" "discard")))))

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
             (Cons "submit" (map (lambda (buffer) (show (● buffer id))) buffers))))

    ;; ---- Images ----

    ;; A PNG's size is in its header, big-endian after the signature and
    ;; the header's length and type; anything else is one texel.

    (define (decoded! (recording Recording) (bytes Bytes)) (→ (Option Image)) (! mut)
      (let* ((png? (and (>= (array-length bytes) 24) (= (array-ref bytes 1) 80)))
             (width (if png? (big-endian bytes 16) 1))
             (height (if png? (big-endian bytes 20) 1)))
        (Some (new Image
                (texture
                 (new GpuTexture
                   (id (transient! recording "decode-image" (list (show width) (show height))))))
                (width width)
                (height height)))))

    (define (big-endian (bytes Bytes) (at I64)) (→ I32)
      (fold-left (lambda (value index)
                   (i32-or (i32-shift-left value 8) (u8->i32 (array-ref bytes (+ at index)))))
                 0
                 (iota 4)))

    ))
