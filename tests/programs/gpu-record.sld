;; What the recording handler notes of a frame: each object numbered as it
;; is made, with its descriptor's fields; the commands that use them; and
;; an object let go.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (only (snail shell task) tasks))

(define shader "@vertex fn v() -> @builtin(position) vec4f { return vec4f(); }")

(define (frame) (→ Unit) (! gpu tasks)
  (request-device)
  (let* ((buffer (create-buffer
                  (new BufferDescriptor
                    (label "vertices")
                    (size 64)
                    (usage (list (Vertex) (CopyDst))))))
         (module (create-shader-module (new ShaderModuleDescriptor (label "shader") (code shader))))
         (pipeline (create-render-pipeline
                    (new RenderPipelineDescriptor
                      (label "pipeline")
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
                   (label "group")
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
    (write-buffer buffer 0 (make-array 64 (i32->u8 0)))
    (set-pipeline pass pipeline)
    (set-bind-group pass 0 group)
    (draw pass 3 1 0 0)
    (end-pass pass)
    (submit (list (finish encoder)))
    (destroy (BufferObject buffer))))

(for-each write-line (● (with-recorded-gpu (lambda () (frame))) second))
