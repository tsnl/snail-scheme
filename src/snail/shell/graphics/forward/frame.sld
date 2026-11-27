;; Every forward pass writes to a renderer-owned view. Geometry chooses its
;; own pipeline and projection. Only the compositor knows the surface format.
(define-library (snail shell graphics forward frame)
  (export display-plane begin-forward-pass rgb-color)
  (import
   (snail core base)
   (snail shell gpu)
   (only (snail shell graphics raster) Plane make-plane))
  (begin
    (define (display-plane (gpu Gpu) (w I32) (h I32)) (→ Plane)
      (make-plane gpu "forward/output" w h (Rgba8Unorm)
                  (list (RenderAttachment) (TextureBinding) (StorageBinding) (TextureCopySrc))))

    (define (rgb-color (rgb I32)) (→ Color)
      (let ((channel (lambda ((shift I32))
                       (→ F64)
                       (/ (i32->f64 (i32-and (i32-shift-right/logical rgb shift) 255)) 255.0))))
        (new Color (red (channel 16)) (green (channel 8)) (blue (channel 0)) (alpha 1.0))))
    ;; A multisampled color attachment resolves into target. Depth can be
    ;; cleared for lit meshes, read after a prepass, or absent for ordered sprites.
    (define (begin-forward-pass (gpu Gpu) (encoder GpuCommandEncoder) (target GpuTextureView)
                                (multi (Option Plane))
                                (background Color)
                                (depth (Option DepthAttachment)))
      (→ GpuRenderPass)
      (let ((color (match multi
                     ((None) (new ColorAttachment (view target) (resolve (None))
                                  (load (Clear background)) (store #t)))
                     ((Some plane)
                      (new ColorAttachment (view (● plane view)) (resolve (Some target))
                           (load (Clear background)) (store #f))))))
        ((● gpu begin-render-pass)
         encoder
         (new RenderPassDescriptor (colors (list (Some color))) (depth depth)))))))
