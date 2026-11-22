;; What the recording handler notes of a frame: each object numbered as it
;; is made, with its descriptor's fields; the commands that use them; and
;; an object let go. Then a compute pass's dispatch, and a timed pass whose
;; times are read back: the recording reads zeros, none elapsed.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (only (snail shell task) tasks))

(define shader "@vertex fn v() -> @builtin(position) vec4f { return vec4f(); }")

(define counting "@compute @workgroup_size(64) fn c() {}")

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
                                        (targets (list (Some (new ColorTarget
                                                               (format (Bgra8Unorm))
                                                               (blend (Some over)))))))))
                      (topology (TriangleList))
                      (cull (CullNone))
                      (depth (None)))))
         (group (create-bind-group
                 (new BindGroupDescriptor
                   (label "group")
                   (pipeline (RenderPipeline pipeline))
                   (group 0)
                   (entries (list (BufferEntry 0 buffer 0 0))))))
         (encoder (create-command-encoder))
         (pass (begin-render-pass encoder
                                  (new RenderPassDescriptor
                                    (colors (list (Some (new ColorAttachment
                                                          (view
                                                           (view-of (● (current-texture) texture)
                                                                    1))
                                                          (load (Clear (new Color
                                                                         (red 0.0)
                                                                         (green 0.5)
                                                                         (blue 1.0)
                                                                         (alpha 1.0))))
                                                          (store #t)))))
                                    (depth (None))))))
    (write-buffer buffer 0 (make-array 64 (i32->u8 0)))
    (set-pipeline pass pipeline)
    (set-bind-group pass 0 group)
    (draw pass 3 1 0 0)
    (end-pass pass)
    (submit (list (finish encoder)))
    (destroy (BufferObject buffer))))

(define (compute) (→ Unit) (! gpu)
  (let* ((module
          (create-shader-module (new ShaderModuleDescriptor (label "count") (code counting))))
         (pipeline (create-compute-pipeline
                    (new ComputePipelineDescriptor (label "count") (module module) (entry "c"))))
         (counts (create-buffer
                  (new BufferDescriptor (label "counts") (size 256) (usage (list (Storage))))))
         (group (create-bind-group (new BindGroupDescriptor
                                     (label "counts")
                                     (pipeline (ComputePipeline pipeline))
                                     (group 0)
                                     (entries (list (BufferEntry 0 counts 0 0))))))
         (encoder (create-command-encoder))
         (pass (begin-compute-pass encoder)))
    (set-compute-pipeline pass pipeline)
    (set-compute-bind-group pass 0 group)
    (dispatch-workgroups pass 4 1 1)
    (end-compute-pass pass)
    (submit (list (finish encoder)))))

(define (timed) (→ F64) (! gpu tasks)
  (let* ((queries (create-query-set (new QuerySetDescriptor (label "times") (count 2))))
         (encoder (create-command-encoder))
         (pass (begin-timed-compute-pass encoder
                                         (new TimestampWrites
                                           (query-set queries)
                                           (beginning 0)
                                           (end 1)))))
    (end-compute-pass pass)
    (elapsed-seconds (submit-timed encoder queries 2) 0 1)))

(for-each write-line (● (with-recorded-gpu (lambda () (frame))) second))
(write-line "compute:")
(for-each write-line (● (with-recorded-gpu compute) second))
(let ((recorded (with-recorded-gpu timed)))
  (write-line "timed:")
  (for-each write-line (● recorded second))
  (write-line (string-append "elapsed: " (f64->string (● recorded first)))))
