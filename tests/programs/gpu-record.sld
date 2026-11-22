;; What the recording handler notes of a frame: each object numbered as it
;; is made, with its descriptor's fields; the commands that use them; and
;; an object let go. Then a compute pass's dispatch.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (only (snail shell task) tasks))

(define shader "@vertex fn v() -> @builtin(position) vec4f { return vec4f(); }")

(define counting "@compute @workgroup_size(64) fn c() {}")

(define (frame (gpu Gpu)) (→ Unit) (! mut tasks)
  (request-device gpu)
  (let* ((buffer (create-buffer gpu
                  (new BufferDescriptor
                    (label "vertices")
                    (size 64)
                    (usage (list (Vertex) (CopyDst))))))
         (module (create-shader-module gpu (new ShaderModuleDescriptor (label "shader") (code shader))))
         (pipeline (create-render-pipeline gpu
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
         (group (create-bind-group gpu
                 (new BindGroupDescriptor
                   (label "group")
                   (pipeline (RenderPipeline pipeline))
                   (group 0)
                   (entries (list (BufferEntry 0 buffer 0 0))))))
         (encoder (create-command-encoder gpu))
         (pass (begin-render-pass gpu encoder
                                  (new RenderPassDescriptor
                                    (colors (list (Some (new ColorAttachment
                                                          (view
                                                           (view-of gpu (● (current-texture gpu) texture)
                                                                    1))
                                                          (load (Clear (new Color
                                                                         (red 0.0)
                                                                         (green 0.5)
                                                                         (blue 1.0)
                                                                         (alpha 1.0))))
                                                          (store #t)))))
                                    (depth (None))))))
    (write-buffer gpu buffer 0 (make-array 64 (i32->u8 0)))
    (set-pipeline gpu pass pipeline)
    (set-bind-group gpu pass 0 group)
    (draw gpu pass 3 1 0 0)
    (end-pass gpu pass)
    (submit gpu (list (finish gpu encoder)))
    (destroy gpu (BufferObject buffer))))

(define (compute (gpu Gpu)) (→ Unit) (! mut)
  (let* ((module
          (create-shader-module gpu (new ShaderModuleDescriptor (label "count") (code counting))))
         (pipeline (create-compute-pipeline gpu
                    (new ComputePipelineDescriptor (label "count") (module module) (entry "c"))))
         (counts (create-buffer gpu
                  (new BufferDescriptor (label "counts") (size 256) (usage (list (Storage))))))
         (group (create-bind-group gpu (new BindGroupDescriptor
                                     (label "counts")
                                     (pipeline (ComputePipeline pipeline))
                                     (group 0)
                                     (entries (list (BufferEntry 0 counts 0 0))))))
         (encoder (create-command-encoder gpu))
         (pass (begin-compute-pass gpu encoder)))
    (set-compute-pipeline gpu pass pipeline)
    (set-compute-bind-group gpu pass 0 group)
    (dispatch-workgroups gpu pass 4 1 1)
    (end-compute-pass gpu pass)
    (submit gpu (list (finish gpu encoder)))))

(for-each (lambda (text) (write-line out text)) (● (with-recorded-gpu (lambda () (frame gpu))) second))
(write-line out "compute:")
(for-each (lambda (text) (write-line out text)) (● (with-recorded-gpu (lambda () (compute gpu))) second))
