(define-library (snail shell graphics trace photography)
  (export LensSettings Photography make-photography release-photography photograph!)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics raster)
   (snail shell graphics kernel)
   (snail shell graphics bvh)
   (snail shell graphics environment)
   (only (snail shell graphics shaders) rays-shader)
   (snail shell graphics trace scene)
   (snail shell graphics trace shaders))
  (begin
    ;; Metres for the focus, effective aperture radius, fog level and range.
    ;; Density is extinction per metre at that level; falloff is per metre up.
    (record LensSettings
      ((focus F32)
       (aperture F32)
       (density F32)
       (level F32)
       (falloff F32)
       (range F32)
       (anisotropy F32)
       (exposure F32)) (deriving Pod))
    (define lens-shape (→ (Shape LensSettings)) (shape))
    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define material-shape (→ (Shape SurfaceMaterial)) (shape))
    (record Photography
      ((settings LensSettings)
       (uniform GpuBuffer)
       (mist GpuComputePipeline)
       (focus GpuComputePipeline)
       (volume Plane)
       (output Plane)
       (shadows GpuBindGroup)
       (cutouts GpuBindGroup)
       (scatter GpuBindGroup)
       (lens GpuBindGroup)
       (width I32)
       (height I32)))
    (define (pipeline (gpu Gpu) (code String) (entry String)) (→ GpuComputePipeline)
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor (label entry) (code code))))
             (kernel (compute-kernel gpu module "photography" entry)))
        ((● gpu destroy) (ModuleObject module)) kernel))
    (define (make-photography (gpu Gpu) (camera GpuBuffer) (bvh Bvh) (scene Scene) (sky Environment)
                              (depth GpuTextureView) (front GpuTextureView) (light GpuTextureView)
                              (width I32) (height I32) (settings LensSettings)) (→ Photography)
                              (let* ((code (string-append (declarations camera-shape)
                                                          (declarations lens-shape)))
                                     (mist (pipeline gpu
                                                     (string-append code
                                                                    (declarations material-shape)
                                                                    scene-shader
                                                                    rays-shader
                                                                    fog-shader)
                                                     "mist"))
                                     (focus
                                      (pipeline gpu (string-append code focus-shader) "photograph"))
                                     (uniform (uniform-buffer gpu
                                                              "photography/lens"
                                                              (pod-bytes lens-shape settings)))
                                     (plane (lambda (name w h)
                                              (make-plane gpu
                                                          name
                                                          w
                                                          h
                                                          (Rgba16Float)
                                                          (list (TextureBinding)
                                                                (StorageBinding)))))
                                     (volume (plane "photography/mist"
                                                    (quotient (+ width 5) 6)
                                                    (quotient (+ height 5) 6)))
                                     (output (plane "photography/film" width height))
                                     (inputs
                                      (list (BufferEntry 0 camera 0 0) (BufferEntry 1 uniform 0 0)
                                            (TextureEntry 2 depth) (TextureEntry 3 front))))
                                (new Photography
                                  (settings settings)
                                  (uniform uniform)
                                  (mist mist)
                                  (focus focus)
                                  (width width)
                                  (height height)
                                  (volume volume) (output output)
                                  (shadows (kernel-group gpu mist 0 "photography/tree"
                                                         (list
                                                          (BufferEntry 0 (● bvh trees slots) 0 0)
                                                          (BufferEntry 1
                                                                       (● bvh trees leaves)
                                                                       0
                                                                       0))))
                                  (cutouts (kernel-group gpu mist 1 "photography/leaves"
                                                         (list
                                                          (BufferEntry 0 (● scene vertices) 0 0)
                                                          (BufferEntry 1 (● scene indices) 0 0)
                                                          (BufferEntry 2 (● scene materials) 0 0)
                                                          (TextureEntry 3 (● scene layers-view))
                                                          (SamplerEntry 4 (● scene sampler)))))
                                  (scatter (kernel-group gpu mist 2 "photography/sun"
                                                         (append inputs
                                                                 (list
                                                                  (TextureEntry 4 (● sky disc view))
                                                                  (TextureEntry 5
                                                                                (● sky
                                                                                   radiance
                                                                                   view))
                                                                  (TextureEntry 6
                                                                                (● volume view))))))
                                  (lens (kernel-group gpu focus 0 "photography/focus"
                                                      (append inputs
                                                              (list (TextureEntry 4 (● volume view))
                                                                    (TextureEntry 5 light)
                                                                    (TextureEntry 6
                                                                                  (● output
                                                                                     view)))))))))
    (define (photograph! (gpu Gpu) (encoder GpuCommandEncoder) (p Photography) (exposure F32))
      (→ Unit)
      ((● gpu write-buffer)
       (● p uniform)
       0
       (pod-bytes lens-shape (LensSettings-exposure-set (● p settings) exposure)))
      (let ((pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu set-compute-pipeline) pass (● p mist))
        ((● gpu set-compute-bind-group) pass 0 (● p shadows))
        ((● gpu set-compute-bind-group) pass 1 (● p cutouts))
        ((● gpu set-compute-bind-group) pass 2 (● p scatter))
        (dispatch-texels gpu pass (quotient (+ (● p width) 5) 6) (quotient (+ (● p height) 5) 6))
        ((● gpu end-compute-pass) pass))
      (let ((pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu set-compute-pipeline) pass (● p focus))
        ((● gpu set-compute-bind-group) pass 0 (● p lens))
        (dispatch-texels gpu pass (● p width) (● p height)) ((● gpu end-compute-pass) pass)))
    (define (release-photography (gpu Gpu) (p Photography)) (→ Unit)
      (for-each (lambda (g) ((● gpu destroy) (BindGroupObject g)))
                (list (● p shadows) (● p cutouts) (● p scatter) (● p lens)))
      (release-plane gpu (● p volume)) (release-plane gpu (● p output))
      ((● gpu destroy) (BufferObject (● p uniform)))
      ((● gpu destroy) (ComputePipelineObject (● p mist)))
      ((● gpu destroy) (ComputePipelineObject (● p focus))))))
