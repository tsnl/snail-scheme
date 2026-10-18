(define-library (draw3d shaders)
  (export shader-entry)
  (import
   (scheme base)
   (webgpu shader)
   (browser application)
   (only (lofi core) ann -> I32))
  (begin
    (define program (compile-scene-shader (gpu (project position)) (gpu (lambert color normal))))
    (define shader-entry
      (ann (lambda (index)
             (let ((value (text-scalar (shader-text program) index)))
               (if (and (< index 0) (not (shader-valid? program))) (- 0 value) value)))
           (-> I32 I32)))))
