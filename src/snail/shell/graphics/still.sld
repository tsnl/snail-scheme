;; Read the display image or the scene-linear HDR attachment of a forward frame.
(define-library (snail shell graphics still)
  (export read-rgba read-plane read-linear)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (only (snail shell math) half-value)
   (only (snail shell little-endian) u16)
   (snail shell graphics raster)
   (snail shell graphics forward render))
  (begin
    (define (read-rgba (gpu Gpu) (target Plane) (width I32) (height I32)) (→ Bytes)
      (read-plane gpu target width height 4))

    ;; Native texture bytes in top-to-bottom rows, without WebGPU pitch padding.
    (define (read-plane (gpu Gpu) (target Plane) (width I32) (height I32) (texel-size I64))
      (→ Bytes)
      (let* ((row (* texel-size (i32->i64 width))) (h (i32->i64 height))
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

    ;; The on-disk comparison format is little-endian RGBA32F, in linear light.
    (define (read-linear (gpu Gpu) (r Forward)) (→ Bytes)
      (let* ((t (● r target)) (light (● t post targets))
             (p (new Plane (texture (● light light)) (view (● light light-view))))
             (half (read-plane gpu p (● t w) (● t h) 8))
             (bytes (make-array (* 2 (array-length half)) (i32->u8 0))))
        (let loop ((at 0))
          (when (< at (array-length half))
            (pod-write (f64->f32 (half-value (u16 half at))) bytes (* 2 at))
            (loop (+ at 2))))
        bytes))
    ))
