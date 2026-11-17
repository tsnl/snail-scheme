;; The books (snail shell gpu) keeps, through the recording handler: a path
;; answers the object it made while its descriptor stays, a frame's objects
;; end at `submit`, a changed descriptor replaces its object, an object
;; over the budget evicts the least recently used one, and a handle to an
;; evicted object panics with what it was.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (only (snail shell task) tasks))

(define (vertices) (→ BufferDescriptor)
  (new BufferDescriptor
    (path (Some (list "test" "vertices")))
    (size 64)
    (usage (list (Vertex) (CopyDst)))))

(define shader "@vertex fn v() -> @builtin(position) vec4f { return vec4f(); }")

(define (frame) (→ GpuBuffer) (! gpu tasks output-port)
  (request-device 1000)
  (let* ((buffer (create-buffer (vertices)))
         (again (create-buffer (vertices)))
         (module (create-shader-module
                  (new ShaderModuleDescriptor (path (Some (list "test" "shader"))) (code shader))))
         (pipeline (create-render-pipeline
                    (new RenderPipelineDescriptor
                      (path (Some (list "test" "pipeline")))
                      (module module)
                      (vertex-entry "v")
                      (buffers (Nil))
                      (fragment (Some (new FragmentState
                                        (entry "f")
                                        (targets (list (new ColorTarget
                                                         (format (Bgra8Unorm))
                                                         (blend (Some over))))))))
                      (topology (TriangleList))
                      (cull (CullNone))
                      (depth (None)))))
         (group (create-bind-group
                 (new BindGroupDescriptor
                   (path (Some (list "test" "group")))
                   (pipeline pipeline)
                   (group 0)
                   (entries (list (BufferEntry 0 buffer 0 0))))))
         (encoder (create-command-encoder))
         (pass (begin-render-pass encoder
                                  (new RenderPassDescriptor
                                    (colors (list (new ColorAttachment
                                                    (view (view-of (● (current-texture) texture) 1))
                                                    (load (Clear (new Color
                                                                   (red 0.0)
                                                                   (green 0.5)
                                                                   (blue 1.0)
                                                                   (alpha 1.0))))
                                                    (store #t))))
                                    (depth (None))))))
    (write-line
     (string-append "fresh, then found: " (show (● buffer fresh)) " " (show (● again fresh))))
    (write-buffer buffer 0 (make-array 64 (i32->u8 0)))
    (set-pipeline pass pipeline)
    (set-bind-group pass 0 group)
    (draw pass 3 1 0 0)
    (end-pass pass)
    (submit (list (finish encoder)))
    buffer))

(define (bigger) (→ BufferDescriptor)
  (new BufferDescriptor (path (Some (list "test" "vertices"))) (size 128) (usage (list (Vertex)))))

(define (big) (→ BufferDescriptor)
  (new BufferDescriptor (path (Some (list "test" "big"))) (size 900) (usage (list (Storage)))))

;; A new descriptor replaces the buffer; the next frame's big buffer evicts
;; it, and the bind group that named the first one.

(define (evicting) (→ GpuBuffer) (! gpu)
  (let ((replaced (create-buffer (bigger))))
    (submit (Nil))
    (create-buffer (big))
    replaced))

(for-each write-line (● (with-recorded-gpu 1000 (lambda () (frame))) second))
(write-line "and later:")
(for-each write-line (● (with-recorded-gpu 1000 (lambda () (frame) (evicting))) second))
(write-line "and a handle to the evicted buffer:")
(with-recorded-gpu 1000 (lambda () (frame) (write-buffer (evicting) 0 (make-array 4 (i32->u8 0)))))
