;; What the recorded `Gpu` notes of a frame: each object numbered as it
;; is made, with its descriptor's fields; the commands that use them; and
;; an object let go. Then a compute pass's dispatch, and a timed pass whose
;; times are read back: the recording reads zeros, none elapsed.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record))

(define shader "@vertex fn v() -> @builtin(position) vec4f { return vec4f(); }")

(define counting "@compute @workgroup_size(64) fn c() {}")

(define (frame (gpu Gpu)) (→ Unit)
  ((● gpu request-device))
  (let* ((buffer ((● gpu create-buffer)
                  (new BufferDescriptor
                    (label "vertices")
                    (size 64)
                    (usage (list (Vertex) (CopyDst))))))
         (module
          ((● gpu create-shader-module)
           (new ShaderModuleDescriptor (label "shader") (code shader))))
         (pipeline ((● gpu create-render-pipeline)
                    (new RenderPipelineDescriptor
                      (label "pipeline")
                      (module module)
                      (vertex-entry "v")
                      (buffers (Nil))
                      (fragment (Some (new FragmentState
                                        (entry "f")
                                        (targets (list (Some (new ColorTarget
                                                               (format
                                                                (Bgra8Unorm))
                                                               (blend
                                                                (Some
                                                                 over)))))))))
                      (topology (TriangleList))
                      (cull (CullNone))
                      (depth (None)))))
         (group ((● gpu create-bind-group)
                 (new BindGroupDescriptor
                   (label "group")
                   (pipeline (RenderPipeline pipeline))
                   (group 0)
                   (entries (list (BufferEntry 0 buffer 0 0))))))
         (encoder ((● gpu create-command-encoder)))
         (pass ((● gpu begin-render-pass) encoder
                (new RenderPassDescriptor
                  (colors (list (Some (new ColorAttachment (resolve (None))
                                           (view
                                            (view-of gpu
                                                     (● ((● gpu current-texture))
                                                        texture)
                                                     1))
                                           (load (Clear (new Color
                                                          (red 0.0)
                                                          (green 0.5)
                                                          (blue 1.0)
                                                          (alpha 1.0))))
                                           (store #t)))))
                  (depth (None))))))
    ((● gpu write-buffer) buffer 0 (make-array 64 (i32->u8 0)))
    ((● gpu set-pipeline) pass pipeline)
    ((● gpu set-bind-group) pass 0 group)
    ((● gpu draw) pass 3 1 0 0)
    ((● gpu end-pass) pass)
    ((● gpu submit) (list ((● gpu finish) encoder)))
    ((● gpu destroy) (BufferObject buffer))))

(define (compute (gpu Gpu)) (→ Unit)
  (let* ((module
          ((● gpu create-shader-module)
           (new ShaderModuleDescriptor (label "count") (code counting))))
         (pipeline ((● gpu create-compute-pipeline)
                    (new ComputePipelineDescriptor
                      (label "count")
                      (module module)
                      (entry "c"))))
         (counts ((● gpu create-buffer)
                  (new BufferDescriptor
                    (label "counts")
                    (size 256)
                    (usage (list (Storage))))))
         (group ((● gpu create-bind-group) (new BindGroupDescriptor
                                             (label "counts")
                                             (pipeline (ComputePipeline pipeline))
                                             (group 0)
                                             (entries (list (BufferEntry 0 counts 0 0))))))
         (encoder ((● gpu create-command-encoder)))
         (pass ((● gpu begin-compute-pass) encoder)))
    ((● gpu set-compute-pipeline) pass pipeline)
    ((● gpu set-compute-bind-group) pass 0 group)
    ((● gpu dispatch-workgroups) pass 4 1 1)
    ((● gpu end-compute-pass) pass)
    ((● gpu submit) (list ((● gpu finish) encoder)))))

(define (timed (gpu Gpu)) (→ F64)
  (let* ((queries ((● gpu create-query-set) (new QuerySetDescriptor (label "times") (count 2))))
         (encoder ((● gpu create-command-encoder)))
         (pass ((● gpu begin-timed-compute-pass) encoder
                (new TimestampWrites
                  (query-set queries)
                  (beginning 0)
                  (end 1)))))
    ((● gpu end-compute-pass) pass)
    (elapsed-seconds (submit-timed gpu encoder queries 2) 0 1)))

(define (main (out OutputPort)) (→ Unit)
  (for-each (lambda (text) (write-line out text))
            (● (with-recorded-gpu (lambda (gpu) (frame gpu))) second))
  (write-line out "compute:")
  (for-each (lambda (text) (write-line out text))
            (● (with-recorded-gpu (lambda (gpu) (compute gpu))) second))
  (let ((recorded (with-recorded-gpu timed)))
    (write-line out "timed:")
    (for-each (lambda (text) (write-line out text)) (● recorded second))
    (write-line out (string-append "elapsed: " (f64->string (● recorded first)))))
  (unit))
