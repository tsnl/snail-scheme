;; Trace a stationary camera into an offscreen RGBA texture. The caller owns
;; the tracer, so another view can reuse the pipelines, geometry and BVH.
(define-library (snail shell graphics still)
  (export render-still read-rgba)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics raster)
   (snail shell graphics trace render))
  (begin
    (define (read-rgba (gpu Gpu) (target Plane) (width I32) (height I32)) (→ Bytes)
      (let* ((row (* 4 (i32->i64 width))) (h (i32->i64 height))
             (pitch (* 256 (quotient (+ row 255) 256))) (size (i64->i32 (* pitch h)))
             (buffer
              ((● gpu create-buffer) (new BufferDescriptor (label "still/readback") (size size)
                                          (usage (list (CopyDst) (MapRead))))))
             (encoder ((● gpu create-command-encoder))))
        ((● gpu copy-texture-to-buffer)
         encoder
         (whole-texture (● target texture))
         buffer
         0
         (i64->i32 pitch)
         width
         height)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let* ((padded ((● gpu read-buffer) buffer 0 size))
               (pixels (make-array (* row h) (i32->u8 0))))
          ((● gpu destroy) (BufferObject buffer))
          (for-each (lambda (y) (array-copy! pixels (* y row) padded (* y pitch) row)) (iota h))
          pixels)))
    (define (render-still (gpu Gpu) (tracer Tracer) (camera Camera3D) (samples I64)
                          (bounces I64) (exposure F32)) (→ (Pair Tracer Bytes))
                          (unless (and (> samples 0) (<= samples 4096))
                            (panic "still samples must be in 1..4096"))
                          (let* ((width (● tracer targets width)) (height (● tracer targets height))
                                 (target (make-plane gpu
                                                     "still"
                                                     width
                                                     height
                                                     (Rgba8Unorm)
                                                     (list (RenderAttachment) (TextureCopySrc)))))
                            (let loop ((frame (discard-trace-history tracer)) (i 0))
                              (if (= i samples)
                                  (let ((pixels (read-rgba gpu target width height)))
                                    (release-plane gpu target)
                                    (new Pair (first frame) (second pixels)))
                                  (let ((next (draw-sampled-traced gpu frame (● target view) camera
                                                                   (/ 1.0 (i32->f32 height))
                                                                   exposure
                                                                   bounces
                                                                   #f
                                                                   (EveryPixel))))
                                    ;; Bound the queued frames for large offline sample counts.
                                    (when (= (modulo i 8) 7) ((● gpu work-done)))
                                    (loop next (+ i 1)))))))))
